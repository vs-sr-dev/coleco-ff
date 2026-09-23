# extract_enemy_data.ps1
#
# Estrae enemy stats + enemy names dalla disasm FF1 NES e produce annotated
# .asm da `include` in slice futuri (battle / formation / bestiary).
#
# Sources:
#   bin/0C_8520_enemydata.bin = 128 enemies x 20 byte = 2560 byte (data_EnemyStats)
#   bin/0B_94E0_enemynames.bin = 1136 byte (128 word ptr + ~880 byte strings)
#     - Ptr table @ file ofs 0; ptrs sono NES address in bank_0B ($94E0..$98EF)
#     - Bank_0B mapped to NES $8000..$BFFF; bin starts at $94E0 (file ofs 0)
#     - Strings null-terminated, FF1 NES text encoding (table_standard.tbl)
#
# Layout enemy (20 byte/entry, ENROMSTAT_* in Constants.inc:35):
#   00-01 : EXP        (word LE)
#   02-03 : GP_REWARD  (word LE)
#   04-05 : HP_MAX     (word LE)
#   06    : MORALE
#   07    : AI         ($FF = no AI; else index into lut_EnemyAi)
#   08    : EVADE      (used for hit/evasion)
#   09    : ABSORB     (physical defense)
#   0A    : NUMHITS
#   0B    : HITRATE
#   0C    : DAMAGE
#   0D    : CRITRATE
#   0E    : UNKNOWN_E
#   0F    : ATTACKAIL  (status on hit)
#   10    : CATEGORY   (bitmask: bit1=Dragon bit2=Giant bit3=Undead bit4=Were
#                                bit5=Water bit6=Mage bit7=Regen)
#   11    : MAGDEF
#   12    : ELEMWEAK   (element mask)
#   13    : ELEMRESIST (element mask)

param(
    [string]$EnemyBin = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_8520_enemydata.bin",
    [string]$NamesBin = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0B_94E0_enemynames.bin",
    [string]$TblStd   = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\table_standard.tbl",
    [string]$OutDir   = "$PSScriptRoot\..\build\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$NENEMIES   = 128
$ENTRYSIZE  = 20
$NAMES_PTR_COUNT = 128
$NAMES_PTR_SIZE  = $NAMES_PTR_COUNT * 2     # 256
$NAMES_NES_BASE  = 0x94E0                    # NES address where names blob starts

$enemyBytes = [System.IO.File]::ReadAllBytes($EnemyBin)
$namesBytes = [System.IO.File]::ReadAllBytes($NamesBin)

if ($enemyBytes.Length -ne ($NENEMIES * $ENTRYSIZE)) {
    throw "enemydata bin size unexpected: $($enemyBytes.Length) (expected $($NENEMIES * $ENTRYSIZE))"
}

# Load FF1 standard char table -> map byte_int -> string
$charMap = @{}
foreach ($line in Get-Content $TblStd) {
    if ($line -match '^([0-9A-Fa-f]{2})=(.*)$') {
        $code = [Convert]::ToInt32($Matches[1], 16)
        $val  = $Matches[2]
        $charMap[$code] = $val
    }
}

# Decode a null-terminated name at file_ofs, return ASCII string + raw byte count
function Decode-Name([byte[]]$buf, [int]$ofs) {
    $sb = New-Object System.Text.StringBuilder
    $i = $ofs
    while ($i -lt $buf.Length) {
        $b = [int]$buf[$i]
        if ($b -eq 0x00) { break }
        if ($charMap.ContainsKey($b)) {
            [void]$sb.Append($charMap[$b])
        } else {
            [void]$sb.Append(('<' + ('{0:X2}' -f $b) + '>'))
        }
        $i++
    }
    return @{ Text = $sb.ToString(); Length = $i - $ofs }
}

# Resolve names: ptr table @ file 0..255, each ptr = NES addr -> file_ofs = ptr - $94E0
$enemyNames = @()
for ($i = 0; $i -lt $NENEMIES; $i++) {
    $pLo = [int]$namesBytes[$i * 2]
    $pHi = [int]$namesBytes[$i * 2 + 1]
    $nesAddr = $pHi * 256 + $pLo
    $fileOfs = $nesAddr - $NAMES_NES_BASE
    if ($fileOfs -lt 0 -or $fileOfs -ge $namesBytes.Length) {
        $enemyNames += @{ Text = "<INVALID `$$('{0:X4}' -f $nesAddr)>"; Length = 0; FileOfs = -1 }
        continue
    }
    $r = Decode-Name $namesBytes $fileOfs
    $enemyNames += @{ Text = $r.Text; Length = $r.Length; FileOfs = $fileOfs; NesAddr = $nesAddr }
}

# ---------------------------------------------------------------------------
# Console pretty-print
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "FF1 Enemy Stats (128 enemies, 20 byte each):"
Write-Host "  ID  Name      Exp   GP   HP  Mor AI  Ev Ab Hi% Hit Dmg Cr ? Ail Cat MDf EWk ERs"
Write-Host "  --- --------- ----- ---- ---- --- --- -- -- --- --- --- -- - --- --- --- --- ---"
for ($i = 0; $i -lt $NENEMIES; $i++) {
    $b = $i * $ENTRYSIZE
    $exp  = [int]$enemyBytes[$b+0] + 256 * [int]$enemyBytes[$b+1]
    $gp   = [int]$enemyBytes[$b+2] + 256 * [int]$enemyBytes[$b+3]
    $hp   = [int]$enemyBytes[$b+4] + 256 * [int]$enemyBytes[$b+5]
    $mor  = [int]$enemyBytes[$b+6]
    $ai   = [int]$enemyBytes[$b+7]
    $ev   = [int]$enemyBytes[$b+8]
    $ab   = [int]$enemyBytes[$b+9]
    $nh   = [int]$enemyBytes[$b+10]
    $hit  = [int]$enemyBytes[$b+11]
    $dmg  = [int]$enemyBytes[$b+12]
    $cr   = [int]$enemyBytes[$b+13]
    $unk  = [int]$enemyBytes[$b+14]
    $ail  = [int]$enemyBytes[$b+15]
    $cat  = [int]$enemyBytes[$b+16]
    $mdf  = [int]$enemyBytes[$b+17]
    $ewk  = [int]$enemyBytes[$b+18]
    $ers  = [int]$enemyBytes[$b+19]
    $name = $enemyNames[$i].Text
    Write-Host ("  {0,3:X2} {1,-9} {2,5} {3,4} {4,4} {5,3} {6,3} {7,2} {8,2} {9,3} {10,3} {11,3} {12,2} {13,1} {14,3:X2} {15,3:X2} {16,3} {17,3:X2} {18,3:X2}" `
        -f $i, $name, $exp, $gp, $hp, $mor, $ai, $ev, $ab, $nh, $hit, $dmg, $cr, $unk, $ail, $cat, $mdf, $ewk, $ers)
}

# ---------------------------------------------------------------------------
# Emit enemy_data_7800.asm
# ---------------------------------------------------------------------------
$out = "$OutDir\enemy_data_7800.asm"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; FF1 Enemy Stats + Names  (auto-generated by tools/extract_enemy_data.ps1)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Source: bin/0C_8520_enemydata.bin  (2560 byte: 128 enemies x 20 byte)')
[void]$sb.AppendLine(';         bin/0B_94E0_enemynames.bin (1136 byte: 128 word ptr + strings)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Stat byte offsets (ENROMSTAT_* in Constants.inc):')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('ENROMSTAT_SIZE       = 20      ; $14')
[void]$sb.AppendLine('ENROMSTAT_EXP        = $00     ; 2 byte LE')
[void]$sb.AppendLine('ENROMSTAT_GP         = $02     ; 2 byte LE')
[void]$sb.AppendLine('ENROMSTAT_HPMAX      = $04     ; 2 byte LE')
[void]$sb.AppendLine('ENROMSTAT_MORALE     = $06')
[void]$sb.AppendLine('ENROMSTAT_AI         = $07     ; $FF = no AI; else index into lut_EnemyAi')
[void]$sb.AppendLine('ENROMSTAT_EVADE      = $08')
[void]$sb.AppendLine('ENROMSTAT_ABSORB     = $09     ; physical defense')
[void]$sb.AppendLine('ENROMSTAT_NUMHITS    = $0A')
[void]$sb.AppendLine('ENROMSTAT_HITRATE    = $0B')
[void]$sb.AppendLine('ENROMSTAT_DAMAGE     = $0C')
[void]$sb.AppendLine('ENROMSTAT_CRITRATE   = $0D')
[void]$sb.AppendLine('ENROMSTAT_UNKNOWN_E  = $0E')
[void]$sb.AppendLine('ENROMSTAT_ATTACKAIL  = $0F     ; status on hit (AIL_*)')
[void]$sb.AppendLine('ENROMSTAT_CATEGORY   = $10     ; bitmask CATEGORY_* (Dragon/Giant/Undead/Were/Water/Mage/Regen)')
[void]$sb.AppendLine('ENROMSTAT_MAGDEF     = $11')
[void]$sb.AppendLine('ENROMSTAT_ELEMWEAK   = $12     ; element mask')
[void]$sb.AppendLine('ENROMSTAT_ELEMRESIST = $13     ; element mask')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Category bits (Constants.inc:25):')
[void]$sb.AppendLine(';   CATEGORY_DRAGON = $02   CATEGORY_GIANT  = $04   CATEGORY_UNDEAD = $08')
[void]$sb.AppendLine(';   CATEGORY_WERE   = $10   CATEGORY_WATER  = $20   CATEGORY_MAGE   = $40')
[void]$sb.AppendLine(';   CATEGORY_REGEN  = $80')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine('data_EnemyStats:')

for ($i = 0; $i -lt $NENEMIES; $i++) {
    $b = $i * $ENTRYSIZE
    $hexes = @()
    for ($j = 0; $j -lt $ENTRYSIZE; $j++) {
        $hexes += ('${0:X2}' -f $enemyBytes[$b + $j])
    }
    $exp  = [int]$enemyBytes[$b+0] + 256 * [int]$enemyBytes[$b+1]
    $hp   = [int]$enemyBytes[$b+4] + 256 * [int]$enemyBytes[$b+5]
    $name = $enemyNames[$i].Text
    [void]$sb.AppendLine(("    .byte " + ($hexes -join ', ')))
    [void]$sb.AppendLine(("    ; `$" + ('{0:X2}' -f $i) + ' ' + $name.PadRight(10) + ' HP=' + $hp + ' XP=' + $exp))
}

# ---------------------------------------------------------------------------
# Emit enemy names (raw bytes preserved + readable comment)
# ---------------------------------------------------------------------------
[void]$sb.AppendLine()
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; data_EnemyNames: 128 word ptr table + null-terminated FF1-encoded strings')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Layout in source (NES $94E0..):')
[void]$sb.AppendLine(';   $94E0-$95DF : 128 LE word pointers (each points to a name string)')
[void]$sb.AppendLine(';   $95E0+      : null-terminated strings in FF1 NES text encoding')
[void]$sb.AppendLine(';                 (table_standard.tbl: $80-$E0 letters/digits/punct,')
[void]$sb.AppendLine(';                  DTE pairs $1A-$69 not used here -- names too short)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; NB: pointers below are KEPT as NES addresses ($94E0..). Per il 7800,')
[void]$sb.AppendLine(';     andranno rebased al nuovo indirizzo della tabella in cart.')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine('data_EnemyNames:')
[void]$sb.AppendLine('  ; --- pointer table (128 word LE, NES addresses) ---')
for ($i = 0; $i -lt $NENEMIES; $i++) {
    $pLo = $namesBytes[$i * 2]
    $pHi = $namesBytes[$i * 2 + 1]
    $nm  = $enemyNames[$i].Text
    [void]$sb.AppendLine(("    .byte `${0:X2}, `${1:X2}    ; `${2:X2} {3,-10} (-> `${4:X4})" `
        -f $pLo, $pHi, $i, $nm, ($pHi * 256 + $pLo)))
}
[void]$sb.AppendLine()
[void]$sb.AppendLine('  ; --- string blob (preserved order, raw bytes) ---')

# Dump string bytes from offset 256 to end, in 16-byte rows, with inline name markers
$stringStart = $NAMES_PTR_SIZE
$blockSize = 16
$nameStartByOfs = @{}
foreach ($n in $enemyNames) {
    if ($n.FileOfs -ge 0) { $nameStartByOfs[$n.FileOfs] = $n.Text }
}

for ($p = $stringStart; $p -lt $namesBytes.Length; $p += $blockSize) {
    $end = [Math]::Min($p + $blockSize, $namesBytes.Length)
    $hexes = @()
    for ($q = $p; $q -lt $end; $q++) {
        $hexes += ('${0:X2}' -f $namesBytes[$q])
    }
    # Find any name that starts within this block
    $tags = @()
    for ($q = $p; $q -lt $end; $q++) {
        if ($nameStartByOfs.ContainsKey($q)) {
            $tags += ('@`$' + ('{0:X4}' -f ($q + $NAMES_NES_BASE)) + ' ' + $nameStartByOfs[$q])
        }
    }
    $tag = if ($tags.Count -gt 0) { '  ; ' + ($tags -join ' | ') } else { '' }
    [void]$sb.AppendLine(("    .byte " + ($hexes -join ', ') + $tag))
}

Set-Content -Path $out -Value $sb.ToString() -Encoding ASCII
Write-Host ""
Write-Host "Wrote $out  ($($NENEMIES * $ENTRYSIZE) byte stats + $($namesBytes.Length) byte names = $(($NENEMIES * $ENTRYSIZE) + $namesBytes.Length) byte, annotated)."
Write-Host ""
