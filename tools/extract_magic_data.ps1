# extract_magic_data.ps1
#
# Estrae magic data + class permissions dalla disasm FF1 NES e produce un
# annotated .asm da `include` in slice futuri (battle / magic menu / drink).
#
# Sources:
#   bin/0C_81E0_magicdata.bin = 92 entries * 8 byte = 736 byte
#     - entries 0x00..0x3F : 64 spells   (magic IDs $B0..$EF)
#     - entries 0x40..0x41 : 2 potions   (HEAL potion / PURE potion, "DRINK")
#     - entries 0x42..0x5B : 26 enemy attacks
#   bank_0E.bin[$2D00..$2D77] = lut_MagicPermisPtr (12 word ptr) + 12x8 byte blocks
#     NB: bank_0E e' un swappable bank mappato in NES a $8000..$BFFF; il ptr
#     table e' a NES $AD00 (bank_0E.asm:6046), che corrisponde a file offset
#     $AD00 - $8000 = $2D00 in bank_0E.bin.
#
# Layout per entry (8 byte):
#   byte 0 : HIT RATE   (accuracy %)
#   byte 1 : EFFECTIVITY(power)
#   byte 2 : ELEMENT    (mask: bit0=Status bit1=Poison bit2=Time bit3=Death
#                              bit4=Fire bit5=Ice bit6=Lit bit7=Earth)
#   byte 3 : TARGET     (mask: $01=AllEnemies $02=OneEnemy $04=Caster
#                              $08=WholeParty $10=OnePartyMember)
#   byte 4 : EFFECT     (effect ID -- handler jump in BtlMag_Effect_*)
#   byte 5 : GRAPHIC    (CHR tile slot in battle)
#   byte 6 : PALETTE    (battle palette idx)
#   byte 7 : UNUSED     ($00)
#
# Permissions: 12 classi x 8 byte (64 bit = 64 spells). Bit SET = CANNOT cast.
#   Layout per byte: byte N = level (N+1), bit 7..4 = white slots (0..3),
#                                          bit 3..0 = black slots (0..3).
#   Ordine classi: FT, TH, BB, RM, WM, BM, KN, NJ, MA, RW, WW, BW.
#
# Output: build/data/magic_data_7800.asm  (736 dati + 96 perm + costanti)
#
# NES BUG POLICY: per coerenza con la "NES-parity+bugfix policy" del progetto,
# l'estrattore emette i DATI ORIGINALI FEDELI ed annota nei commenti le spell
# notoriamente buggate. Il fix vero accade in fase di porting del battle engine.

param(
    [string]$MagBin = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_81E0_magicdata.bin",
    [string]$Bank0E = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_0E.bin",
    [string]$OutDir = "$PSScriptRoot\..\build\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$NSPELLS    = 64
$NPOTIONS   = 2
$NENEMYATK  = 26
$NTOTAL     = $NSPELLS + $NPOTIONS + $NENEMYATK   # 92
$ENTRYSIZE  = 8

# Permissions live in bank_0E. The ptr table is at NES $AD00 (bank_0E.asm:6046).
# bank_0E is a swappable bank mapped to NES $8000..$BFFF -> file offset = NES - $8000.
# Layout: 12 word ptrs @ $AD00 ($2D00 in file), 12 x 8-byte blocks @ $AD18 ($2D18).
$PERM_PTR_OFS   = 0x2D00
$PERM_BLOCK_OFS = 0x2D18
$BANK0E_BASE    = 0x8000
$NCLASSES       = 12
$PERMSIZE       = 8

$magBytes  = [System.IO.File]::ReadAllBytes($MagBin)
$bank0EArr = [System.IO.File]::ReadAllBytes($Bank0E)   # NB: NON $bank0E (param string)

if ($magBytes.Length -ne ($NTOTAL * $ENTRYSIZE)) {
    throw "magicdata bin size unexpected: $($magBytes.Length) (expected $($NTOTAL * $ENTRYSIZE))"
}

# Canonical FF1 NES spell names (64 spells, from Constants.inc MG_* mnemonics).
$spellNames = @(
    'CURE','HARM','FOG' ,'RUSE','FIRE','SLEP','LOCK','LIT' ,  # $00..$07 (L1)
    'LAMP','MUTE','ALIT','INVS','ICE' ,'DARK','TMPR','SLOW',  # $08..$0F (L2)
    'CUR2','HRM2','AFIR','HEAL','FIR2','HOLD','LIT2','LOK2',  # $10..$17 (L3)
    'PURE','FEAR','AICE','AMUT','SLP2','FAST','CONF','ICE2',  # $18..$1F (L4)
    'CUR3','LIFE','HRM3','HEL2','FIR3','BANE','WARP','SLO2',  # $20..$27 (L5)
    'SOFT','EXIT','FOG2','INV2','LIT3','RUB' ,'QAKE','STUN',  # $28..$2F (L6)
    'CUR4','HRM4','ARUB','HEL3','ICE3','BRAK','SABR','BLND',  # $30..$37 (L7)
    'LIF2','FADE','WALL','XFER','NUKE','STOP','ZAP' ,'XXXX'    # $38..$3F (L8)
)

$potionNames = @('HEAL-potion','PURE-potion')                      # $40..$41

$enemyAttackNames = @(                                              # $42..$5B
    'EnAtk_00','EnAtk_01','EnAtk_02','EnAtk_03','EnAtk_04','EnAtk_05',
    'EnAtk_06','EnAtk_07','EnAtk_08','EnAtk_09','EnAtk_0A','EnAtk_0B',
    'EnAtk_0C','EnAtk_0D','EnAtk_0E','EnAtk_0F','EnAtk_10','EnAtk_11',
    'EnAtk_12','EnAtk_13','EnAtk_14','EnAtk_15','EnAtk_16','EnAtk_17',
    'EnAtk_18','EnAtk_19'
)

# Spell bugs. Sources:
#   FFO = FFOrigins canonical "Faulty Spells" list (authoritative, fix-required)
#   DCH = Disch disasm "BUGGED" comments (handler code looks wrong but not
#         flagged by FFOrigins -- bug invisibile in gameplay o disagreement).
# Marked by spell idx (0..63). Value = (tag, reason).
$bugs = @{
    0x06 = @('FFO', 'LOCK always misses (effect routine broken)')
    0x0E = @('FFO', 'TMPR does not work at all (damage bonus lost Save/Load)')
    0x17 = @('FFO', 'LOK2 INVERTED: makes enemies HARDER to hit (opposite intent)')
    0x23 = @('FFO', 'HEL2 inside battle has effect of HEL3 (heals MORE than expected)')
    0x36 = @('FFO', 'SABR does not work at all (same bug as TMPR)')
    0x3B = @('FFO', 'XFER does not work at all (resist loaded from ROM not RAM)')

    0x03 = @('DCH', 'RUSE: evade bonus reads wrong stat (Disch disasm note)')
    0x0B = @('DCH', 'INVS: never adds defender evade (Disch disasm note)')
    0x0F = @('DCH', 'SLOW: re-cast stacks Ineffective wrongly (Disch disasm note)')
    0x25 = @('DCH', 'BANE: caster-level vs target-HP threshold check off (Disch note)')
    0x2A = @('DCH', 'FOG2: same handler issue as RUSE (Disch disasm note)')
    0x2B = @('DCH', 'INV2: same handler issue as INVS (Disch disasm note)')
}

# ---------------------------------------------------------------------------
# Console pretty-print
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "FF1 Magic Data (92 entries, 8 byte each):"
Write-Host "  Idx Name        Hit Eff Ele Tgt Eff Gfx Pal | NES bug?"
Write-Host "  --- ----------- --- --- --- --- --- --- --- | --------"

for ($i = 0; $i -lt $NTOTAL; $i++) {
    $b = $i * $ENTRYSIZE
    if ($i -lt $NSPELLS) {
        $name = $spellNames[$i]
    }
    elseif ($i -lt ($NSPELLS + $NPOTIONS)) {
        $name = $potionNames[$i - $NSPELLS]
    }
    else {
        $name = $enemyAttackNames[$i - $NSPELLS - $NPOTIONS]
    }

    $bugStr = if ($bugs.ContainsKey($i)) { '[' + $bugs[$i][0] + '] ' + $bugs[$i][1] } else { '' }

    Write-Host ("  {0,3:X2} {1,-11} {2,3} {3,3} {4,3} {5,3} {6,3} {7,3} {8,3} | {9}" `
        -f $i, $name, $magBytes[$b+0], $magBytes[$b+1], $magBytes[$b+2], $magBytes[$b+3], `
           $magBytes[$b+4], $magBytes[$b+5], $magBytes[$b+6], $bugStr)
}

# ---------------------------------------------------------------------------
# Permissions verification + decode
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Magic Permissions (12 classes x 8 byte = 64 bits each, bit SET = CANNOT cast):"
$classOrder = @('FT','TH','BB','RM','WM','BM','KN','NJ','MA','RW','WW','BW')
$classFull  = @('Fighter','Thief','BlackBelt','RedMage','WhiteMage','BlackMage',
                'Knight','Ninja','Master','RedWiz','WhiteWiz','BlackWiz')

# Permissions blocks are at $PERM_BLOCK_OFS + class * 8. Verify ptr table coherence.
$blocks = New-Object byte[] (12 * $PERMSIZE)
for ($c = 0; $c -lt $NCLASSES; $c++) {
    $pLo = [int]$bank0EArr[$PERM_PTR_OFS + $c * 2]
    $pHi = [int]$bank0EArr[$PERM_PTR_OFS + $c * 2 + 1]
    $addrNES = $pHi * 256 + $pLo                           # NES addr in bank_0E ($8000-$BFFF)
    $fileOfs = $addrNES - $BANK0E_BASE
    $expected = $PERM_BLOCK_OFS + $c * $PERMSIZE
    if ($fileOfs -ne $expected) {
        Write-Host ("  WARN class {0}: ptr=`${1:X4} file=`${2:X4} expected=`${3:X4}" `
            -f $classOrder[$c], $addrNES, $fileOfs, $expected)
    }
    for ($k = 0; $k -lt $PERMSIZE; $k++) {
        $blocks[$c * $PERMSIZE + $k] = $bank0EArr[$fileOfs + $k]
    }
}

Write-Host "  Class  L1 L2 L3 L4 L5 L6 L7 L8"
Write-Host "  -----  -- -- -- -- -- -- -- --"
for ($c = 0; $c -lt $NCLASSES; $c++) {
    $bytes = @()
    for ($k = 0; $k -lt $PERMSIZE; $k++) {
        $bytes += ('{0:X2}' -f $blocks[$c * $PERMSIZE + $k])
    }
    Write-Host ("  {0}({1,-9})  {2}" -f $classOrder[$c], $classFull[$c], ($bytes -join ' '))
}

# ---------------------------------------------------------------------------
# Emit magic_data_7800.asm
# ---------------------------------------------------------------------------
$out = "$OutDir\magic_data_7800.asm"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; FF1 Magic Data + Permissions  (auto-generated by tools/extract_magic_data.ps1)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Source: bin/0C_81E0_magicdata.bin + bank_0E.bin[$2D00 ptr / $2D18 blocks]')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; 92 entries total, 8 byte each = 736 byte:')
[void]$sb.AppendLine(';   $00..$3F  64 spells  (in-game magic IDs $B0..$EF)')
[void]$sb.AppendLine(';   $40..$41  2 potions  (HEAL-potion / PURE-potion / DRINK)')
[void]$sb.AppendLine(';   $42..$5B  26 enemy-only attacks')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Stat byte offsets (use these constants):')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('MAG_STAT_SIZE     = 8')
[void]$sb.AppendLine('MAG_STAT_HITRATE  = 0      ; accuracy %')
[void]$sb.AppendLine('MAG_STAT_POWER    = 1      ; effectivity (power)')
[void]$sb.AppendLine('MAG_STAT_ELEMENT  = 2      ; element mask (Fire/Ice/Lit/Earth/Status/Poison/Time/Death)')
[void]$sb.AppendLine('MAG_STAT_TARGET   = 3      ; target mask:')
[void]$sb.AppendLine(';                            $01 = AllEnemies   $02 = OneEnemy')
[void]$sb.AppendLine(';                            $04 = Caster       $08 = WholeParty')
[void]$sb.AppendLine(';                            $10 = OnePartyMember')
[void]$sb.AppendLine('MAG_STAT_EFFECT   = 4      ; effect id (BtlMag_Effect_* handler jump)')
[void]$sb.AppendLine('MAG_STAT_GFX      = 5      ; battle CHR tile slot')
[void]$sb.AppendLine('MAG_STAT_PAL      = 6      ; battle palette idx')
[void]$sb.AppendLine('MAG_STAT_UNUSED   = 7      ; $00')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Class permissions: each byte = 1 spell-level (L1..L8). Bit SET = CANNOT cast.')
[void]$sb.AppendLine(';   bit 7..4 = white-magic slots 0..3 in that level')
[void]$sb.AppendLine(';   bit 3..0 = black-magic slots 0..3 in that level')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Class permission order: FT TH BB RM WM BM KN NJ MA RW WW BW.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; NES bug tags in spell comments:')
[void]$sb.AppendLine(';   [FFO] = FFOrigins canonical "Faulty Spells" list (must-fix)')
[void]$sb.AppendLine(';   [DCH] = Disch disasm note (handler suspect; not flagged by FFOrigins')
[void]$sb.AppendLine(';           -- may be invisible in gameplay or false positive)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Per policy NES-parity+bugfix, byte values are LEFT AS-IS; fix happens')
[void]$sb.AppendLine('; in the ported battle engine effect handlers, not by rewriting this table.')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine('lut_MagicData:')

for ($i = 0; $i -lt $NTOTAL; $i++) {
    $b = $i * $ENTRYSIZE
    $bytes = @()
    for ($j = 0; $j -lt $ENTRYSIZE; $j++) {
        $bytes += ('${0:X2}' -f $magBytes[$b + $j])
    }
    if ($i -lt $NSPELLS) {
        $name = $spellNames[$i]
        $level = [Math]::Floor($i / 8) + 1
        $kind = if (($i % 8) -lt 4) { 'W' } else { 'B' }
        $tag = ('${0:X2} L{1}{2} {3,-5}' -f $i, $level, $kind, $name)
    }
    elseif ($i -lt ($NSPELLS + $NPOTIONS)) {
        $tag = ('${0:X2} {1}' -f $i, $potionNames[$i - $NSPELLS])
    }
    else {
        $tag = ('${0:X2} {1}' -f $i, $enemyAttackNames[$i - $NSPELLS - $NPOTIONS])
    }
    $bugTag = if ($bugs.ContainsKey($i)) { '  ; [' + $bugs[$i][0] + '] ' + $bugs[$i][1] } else { '' }
    [void]$sb.AppendLine(("    .byte " + ($bytes -join ', ') + " ; " + $tag + $bugTag))
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; lut_MagicPermissions: 12 classes x 8 byte (FT,TH,BB,RM,WM,BM,KN,NJ,MA,RW,WW,BW)')
[void]$sb.AppendLine('; Index: class_id * 8, then byte N = spell-level N+1 (1..8).')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('lut_MagicPermissions:')
for ($c = 0; $c -lt $NCLASSES; $c++) {
    $bytes = @()
    for ($k = 0; $k -lt $PERMSIZE; $k++) {
        $bytes += ('${0:X2}' -f $blocks[$c * $PERMSIZE + $k])
    }
    [void]$sb.AppendLine(("    .byte " + ($bytes -join ', ') + " ; " + $classOrder[$c] + ' ' + $classFull[$c]))
}

Set-Content -Path $out -Value $sb.ToString() -Encoding ASCII
Write-Host ""
Write-Host "Wrote $out  ($($NTOTAL * $ENTRYSIZE) byte magic data + $($NCLASSES * $PERMSIZE) byte permissions = $(($NTOTAL * $ENTRYSIZE) + ($NCLASSES * $PERMSIZE)) byte, annotated)."
Write-Host ""
