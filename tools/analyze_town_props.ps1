# analyze_town_props.ps1 -- che cosa dicono davvero i due byte di SMTilesetProp
# per la mappa standard indicata. Non genera niente: MISURA, e serve a non
# costruire le collisioni sopra una lettura sbagliata dei bit.
#
# Sorgenti (le stesse di extract_sm_colors.ps1):
#   bank_00.dat  $0800 + T*256   SMTilesetProp   2 byte per macrotile
#                $2CC0 + M       lut_Tilesets    tileset della mappa
#   bank_04..07  bitstream RLE delle mappe
#
# Semantica dei due byte (Constants.inc + bank_0F.asm:3539):
#   byte 0 bit 0     TP_NOMOVE      1 = NON si passa
#   byte 0 bit 1-4   TP_SPEC_MASK   $02 = porta, $08 = tesoro, ...
#   byte 0 bit 5     TP_BATTLEMARKER
#   byte 0 bit 6-7   TP_TELE_MASK   %01 warp, %10 normale, %11 uscita
#   byte 1           se la casella e' una PORTA: shop_id (0 = non e' un negozio)
#                    altrimenti: id di teleport / dialogo / tesoro

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$MapId = 0
)

$ErrorActionPreference = 'Stop'
function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }

$b00 = ReadBank 'bank_00.dat'
$tileset = [int]$b00[0x2CC0 + $MapId]
$PROP_BASE = 0x0800 + $tileset * 256

# --- mappa: stessa decompressione di extract_sm_colors.ps1 ------------------
$sm = New-Object byte[] (16384 * 4)
$i = 0
foreach ($n in 'bank_04.dat','bank_05.dat','bank_06.dat','bank_07.dat') {
    [Array]::Copy((ReadBank $n), 0, $sm, $i, 16384); $i += 16384
}
$lo = [int]$sm[$MapId*2]; $hi = [int]$sm[$MapId*2+1]
$srcp = (($hi -shr 6) -band 3) * 16384 + (((($hi -band 0x3F) -bor 0x80) -shl 8) -bor $lo) - 0x8000

$map = New-Object byte[] 4096
$n = 0
while ($n -lt 4096) {
    $v = $sm[$srcp]; $srcp++
    if ($v -eq 0xFF) { break }
    if ($v -lt 0x80) { $map[$n] = $v; $n++ }
    else {
        $t = [byte]($v -band 0x7F); $len = [int]$sm[$srcp]; $srcp++
        if ($len -eq 0) { $len = 256 }
        for ($k = 0; $k -lt $len -and $n -lt 4096; $k++) { $map[$n] = $t; $n++ }
    }
}
if ($n -ne 4096) { throw "mappa $MapId decompressa a $n macrotile, attesi 4096" }

$entryX = [int]$b00[0x2C00 + 1]
$entryY = [int]$b00[0x2C20 + 1]

Write-Host ("mappa {0}, tileset {1}, ingresso ({2},{3})" -f $MapId, $tileset, $entryX, $entryY)

# --- inventario dei macrotile che la mappa USA davvero ----------------------
$used = @{}
foreach ($m in $map) { $used[[int]$m] = 1 }
$usedIds = @($used.Keys | Sort-Object)
Write-Host ("macrotile distinti usati: {0}" -f $usedIds.Count)

$nomove = 0; $doors = @(); $teles = @()
Write-Host ''
Write-Host 'id   b0  b1   NOMOVE SPEC      TELE        note'
foreach ($m in $usedIds) {
    $p0 = [int]$b00[$PROP_BASE + $m*2]
    $p1 = [int]$b00[$PROP_BASE + $m*2 + 1]
    $nm = if ($p0 -band 1) { 'si    ' } else { 'no    ' }
    if ($p0 -band 1) { $nomove++ }
    $spec = $p0 -band 0x1E
    $specName = switch ($spec) {
        0x00 { '-        ' }
        0x02 { 'DOOR     ' }
        0x04 { 'LOCKED   ' }
        0x06 { 'CLOSEROOM' }
        0x08 { 'TREASURE ' }
        0x0A { 'BATTLE   ' }
        0x0C { 'DAMAGE   ' }
        default { ('$' + $spec.ToString('X2') + '      ') }
    }
    $tele = $p0 -band 0xC0
    $teleName = switch ($tele) {
        0x00 { '-        ' }
        0x40 { 'WARP     ' }
        0x80 { 'NORM     ' }
        0xC0 { 'EXIT     ' }
    }
    $note = ''
    if ($spec -eq 0x02 -and $p1 -ne 0) { $note = "NEGOZIO shop_id=$p1"; $doors += $m }
    if ($tele -ne 0) { $note = ($note + " tele_id=$p1").Trim(); $teles += $m }
    $cnt = 0; foreach ($q in $map) { if ([int]$q -eq $m) { $cnt++ } }
    Write-Host ("{0}  {1}  {2}   {3} {4} {5} {6} (x{7})" -f `
        ('$' + $m.ToString('X2')), $p0.ToString('X2'), $p1.ToString('X2'), `
        $nm, $specName, $teleName, $note, $cnt)
}
Write-Host ''
Write-Host ("invalicabili: {0} su {1}" -f $nomove, $usedIds.Count)

# --- dove stanno, sulla mappa ------------------------------------------------
if ($doors.Count) {
    Write-Host ''
    Write-Host 'ingressi di negozio, posizione in macrotile:'
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            $m = [int]$map[$y*64 + $x]
            if ($doors -contains $m) {
                $sid = [int]$b00[$PROP_BASE + $m*2 + 1]
                Write-Host ("  ({0,2},{1,2})  macro `${2}  shop_id {3}" -f $x, $y, $m.ToString('X2'), $sid)
            }
        }
    }
}

# --- ritaglio attorno all'ingresso: si vede subito se le mura contengono -----
Write-Host ''
Write-Host ("intorno dell'ingresso ({0},{1}), 21x13 macrotile  (# = invalicabile, . = libero," -f $entryX, $entryY)
Write-Host ' W = warp/uscita, S = negozio, @ = ingresso):'
for ($y = $entryY - 6; $y -le $entryY + 6; $y++) {
    $row = '  '
    for ($x = $entryX - 10; $x -le $entryX + 10; $x++) {
        if ($y -lt 0 -or $y -ge 64 -or $x -lt 0 -or $x -ge 64) { $row += ' '; continue }
        $m = [int]$map[$y*64 + $x]
        $p0 = [int]$b00[$PROP_BASE + $m*2]
        $p1 = [int]$b00[$PROP_BASE + $m*2 + 1]
        $c = '.'
        if ($p0 -band 1) { $c = '#' }
        if (($p0 -band 0x1E) -eq 0x02 -and $p1 -ne 0) { $c = 'S' }
        if (($p0 -band 0xC0) -ne 0) { $c = 'W' }
        if ($x -eq $entryX -and $y -eq $entryY) { $c = '@' }
        $row += $c
    }
    Write-Host $row
}
