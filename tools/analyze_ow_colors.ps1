# analyze_ow_colors.ps1
#
# Analisi preliminare al colore vero della overworld (oggi: vfill 0x3C, verde
# piatto). Non genera nulla: MISURA, per sapere se il piano e' realizzabile
# prima di scrivere il generatore.
#
# Catena dati FF1 (da bank_0F.asm LoadOWTilesetData + variables.inc):
#   lut_OWTileset = bank_00.dat offset 0, $400 byte:
#     +$000 tileset_prop  256 (2 byte/metatile: gli attributi FIGHT/TELEPORT)
#     +$100 tsa_ul        128   \
#     +$180 tsa_ur        128    | i 4 quadranti CHR di ogni metatile
#     +$200 tsa_dl        128    |
#     +$280 tsa_dr        128   /
#     +$300 tsa_attr      128  <- byte attributo NES = quale sotto-palette
#     +$380 load_map_pal  $30  <- le palette VERE (BG 16 + SPR 16 + inroom 16)
#   CHR mappe = bank_02.dat (BANK_MAPCHR)
#
# LA DOMANDA CHE CONTA
#   Sul TMS9918 in mode 2 il colore e' legato all'ID DEL TILE, non alla
#   posizione a schermo: 8 byte di colore per tile (2 colori per riga).
#   Se lo stesso tile CHR compare con palette diverse, servono DUE tile
#   distinti. Quindi il tileset TMS va costruito sulle coppie (tile, palette).
#   Se le coppie distinte sono <= 256 il piano funziona; altrimenti serve un
#   ripiego (dedup per colore dominante, o tileset diversi per terzo schermo).

param(
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OwbgHdr = "$PSScriptRoot\..\src\ff1_owbg.h"
)

$ErrorActionPreference = 'Stop'

$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_00.dat'))
$b02 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_02.dat'))

$tsaUL = $b00[0x100..0x17F]
$tsaUR = $b00[0x180..0x1FF]
$tsaDL = $b00[0x200..0x27F]
$tsaDR = $b00[0x280..0x2FF]
$tsaAttr = $b00[0x300..0x37F]
$mapPal  = $b00[0x380..0x3AF]

Write-Host "=== load_map_pal (48 byte) ==="
Write-Host ("  BG  pal0: " + (($mapPal[0..3]   | ForEach-Object { $_.ToString('X2') }) -join ' '))
Write-Host ("  BG  pal1: " + (($mapPal[4..7]   | ForEach-Object { $_.ToString('X2') }) -join ' '))
Write-Host ("  BG  pal2: " + (($mapPal[8..11]  | ForEach-Object { $_.ToString('X2') }) -join ' '))
Write-Host ("  BG  pal3: " + (($mapPal[12..15] | ForEach-Object { $_.ToString('X2') }) -join ' '))
Write-Host ("  SPR     : " + (($mapPal[16..31] | ForEach-Object { $_.ToString('X2') }) -join ' '))

Write-Host ""
Write-Host "=== tsa_attr: distribuzione dei byte attributo ==="
$attrHist = @{}
foreach ($a in $tsaAttr) { if ($attrHist.ContainsKey($a)) { $attrHist[$a]++ } else { $attrHist[$a] = 1 } }
foreach ($k in ($attrHist.Keys | Sort-Object)) {
    Write-Host ("  attr 0x{0}  -> {1,3} metatile   (bit0-1 = {2})" -f $k.ToString('X2'), $attrHist[$k], ($k -band 3))
}

# Verifica empirica della sorgente CHR: OR-planare i tile di bank_02 e
# confrontarli con ff1_owbg_pattern gia' in repo (generato in slice precedenti).
Write-Host ""
Write-Host "=== verifica sorgente CHR (bank_02.dat offset 0) ==="
$hdrText = [System.IO.File]::ReadAllText($OwbgHdr)
$patStart = $hdrText.IndexOf('ff1_owbg_pattern')
$patEnd   = $hdrText.IndexOf('};', $patStart)
$patBody  = $hdrText.Substring($patStart, $patEnd - $patStart)
$hdrBytes = [regex]::Matches($patBody, '0x([0-9A-Fa-f]{2})') | ForEach-Object { [byte][Convert]::ToInt32($_.Groups[1].Value, 16) }
Write-Host ("  ff1_owbg_pattern nel repo: {0} byte ({1} tile)" -f $hdrBytes.Count, ($hdrBytes.Count / 8))

$nTiles = [int]($hdrBytes.Count / 8)
$match = 0
for ($t = 0; $t -lt $nTiles; $t++) {
    $ok = $true
    for ($i = 0; $i -lt 8; $i++) {
        $p0 = [int]$b02[$t * 16 + $i]
        $p1 = [int]$b02[$t * 16 + 8 + $i]
        $or = [byte](($p0 -bor $p1) -band 0xFF)
        if ($or -ne $hdrBytes[$t * 8 + $i]) { $ok = $false; break }
    }
    if ($ok) { $match++ }
}
Write-Host ("  tile che coincidono con OR-plane(bank_02): {0}/{1}" -f $match, $nTiles)
if ($match -eq $nTiles) {
    Write-Host "  -> CONFERMATO: la CHR della OW e' bank_02.dat offset 0" -ForegroundColor Green
} else {
    Write-Host "  -> NON confermato: la CHR viene da un'altra sorgente/offset" -ForegroundColor Yellow
}

# La misura decisiva: coppie (tile CHR, palette) distinte fra i 128 metatile.
Write-Host ""
Write-Host "=== coppie (tile, palette) distinte ==="
$combos   = @{}
$tileSeen = @{}
for ($m = 0; $m -lt 128; $m++) {
    $pal = [int]$tsaAttr[$m] -band 3
    foreach ($tid in @([int]$tsaUL[$m], [int]$tsaUR[$m], [int]$tsaDL[$m], [int]$tsaDR[$m])) {
        $combos["$tid/$pal"] = $true
        if ($tileSeen.ContainsKey($tid)) { $tileSeen[$tid][$pal] = $true }
        else { $h = @{}; $h[$pal] = $true; $tileSeen[$tid] = $h }
    }
}
Write-Host ("  tile CHR distinti usati        : {0}" -f $tileSeen.Count)
Write-Host ("  coppie (tile,palette) distinte : {0}" -f $combos.Count)
$multi = @($tileSeen.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
Write-Host ("  tile usati con PIU' di una palette: {0}" -f $multi.Count)
if ($combos.Count -le 256) {
    Write-Host ("  -> STA NEI 256 TILE del TMS9918: {0} liberi" -f (256 - $combos.Count)) -ForegroundColor Green
} else {
    Write-Host ("  -> SFORA di {0}: serve un ripiego" -f ($combos.Count - 256)) -ForegroundColor Red
}

# Quanti colori NES distinti servono davvero (per il mapping verso i 15 TMS).
Write-Host ""
Write-Host "=== colori NES usati dalle 4 palette BG ==="
$colors = @{}
for ($p = 0; $p -lt 4; $p++) {
    for ($c = 0; $c -lt 4; $c++) {
        $nes = [int]$mapPal[$p * 4 + $c]
        $colors[$nes] = $true
    }
}
Write-Host ("  colori NES distinti: {0} -> {1}" -f $colors.Count, (($colors.Keys | Sort-Object | ForEach-Object { '$' + $_.ToString('X2') }) -join ' '))
