# analyze_sm_colors.ps1 -- MISURA e basta, non genera niente.
#
# Stessa funzione che analyze_ow_colors.ps1 ha avuto per l'overworld in
# slice47, e per la stessa ragione: sul TMS9918 in modo 2 il colore e' legato
# all'ID DEL TILE, non alla posizione. Un tile CHR che compare con due palette
# diverse costa DUE tile TMS. Quindi il tileset si costruisce sulle coppie
# (tile, palette), e la domanda da farsi PRIMA di scrivere il generatore e'
# una sola: **le coppie stanno nei 256 tile?**
#
# Per l'overworld la risposta fu 236 su 256. Per una mappa standard non e'
# scontata, e se sfora il piano non regge: serve un ripiego (unire palette
# vicine, o allocare per terzo di schermo).
#
# Fonti (le stesse di extract_sm_coneria.ps1):
#   bank_00.dat  $0400 + T*128   SMTilesetAttr  (palette per macrotile)
#                $1000 + T*512   SMTilesetTSA   (4 blocchi CONTIGUI da 128,
#                                                NON interlacciati -- vedi
#                                                [[ff1-sm-tsa-layout]])
#                $2000 + T*$30   lut_SMPalettes (16 byte BG + 16 sprite + 16)
#   bank_03.dat  T*$800          CHR 2bpp, 128 tile da 16 byte

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$Tileset = 0,
    [int]$MapId = 0
)

$ErrorActionPreference = 'Stop'

function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }
$b0 = ReadBank 'bank_00.dat'
$b3 = ReadBank 'bank_03.dat'

$ATTR = 0x0400 + $Tileset * 128
$TSA  = 0x1000 + $Tileset * 512
$PAL  = 0x2000 + $Tileset * 0x30

Write-Host "=== tileset $Tileset ===" -ForegroundColor Cyan

# ---- 1. le 4 sotto-palette BG -------------------------------------------
Write-Host "`n4 sotto-palette BG (NES):"
for ($p = 0; $p -lt 4; $p++) {
    $c = @(); for ($k = 0; $k -lt 4; $k++) { $c += $b0[$PAL + $p*4 + $k].ToString('X2') }
    Write-Host ("  pal {0}: {1}" -f $p, ($c -join ' '))
}

# ---- 2. come e' fatto l'attributo ---------------------------------------
# Sul NES un byte di attributo impacchetta 4 quadranti da 2 bit. Nella OW i
# soli valori presenti erano 00/55/AA/FF, cioe' l'indice replicato: una palette
# per macrotile e non per quadrante. Se qui NON fosse cosi', ogni quadrante
# avrebbe la sua e il conto delle coppie cambierebbe.
$attrVals = @{}
for ($m = 0; $m -lt 128; $m++) { $a = $b0[$ATTR + $m]; $attrVals[$a] = $attrVals[$a] + 1 }
$replicated = $true
foreach ($a in $attrVals.Keys) {
    $q = @(($a -band 3), (($a -shr 2) -band 3), (($a -shr 4) -band 3), (($a -shr 6) -band 3))
    if (($q | Select-Object -Unique).Count -ne 1) { $replicated = $false }
}
Write-Host "`nvalori di attributo distinti: $($attrVals.Count)"
Write-Host ("  " + (($attrVals.Keys | Sort-Object | ForEach-Object { '$' + $_.ToString('X2') + "x" + $attrVals[$_] }) -join '  '))
if ($replicated) {
    Write-Host "  -> l'indice e' REPLICATO nei 4 quadranti: una palette per macrotile" -ForegroundColor Green
} else {
    Write-Host "  -> NON replicato: la palette cambia per QUADRANTE, il generatore deve tenerne conto" -ForegroundColor Yellow
}

# ---- 3. le coppie (tile, palette) ---------------------------------------
# Si contano solo i macrotile USATI DALLA MAPPA: un tileset ne definisce 128,
# ma se Coneria ne usa 60 le coppie da pagare sono quelle. E' la differenza
# fra "ci sta" e "non ci sta".
$usedMacro = @{}
if ($MapId -ge 0) {
    # decompressione RLE, come in extract_sm_coneria.ps1
    $sm = New-Object byte[] (16384 * 4)
    $i = 0
    foreach ($n in 'bank_04.dat','bank_05.dat','bank_06.dat','bank_07.dat') {
        [Array]::Copy((ReadBank $n), 0, $sm, $i, 16384); $i += 16384
    }
    $lo = [int]$sm[$MapId*2]; $hi = [int]$sm[$MapId*2+1]
    $src = (($hi -shr 6) -band 3) * 16384 + (((($hi -band 0x3F) -bor 0x80) -shl 8) -bor $lo) - 0x8000
    $n = 0
    while ($n -lt 4096) {
        $v = $sm[$src]; $src++
        if ($v -eq 0xFF) { break }
        if ($v -lt 0x80) { $usedMacro[$v] = 1; $n++ }
        else {
            $t = $v -band 0x7F; $len = [int]$sm[$src]; $src++
            if ($len -eq 0) { $len = 256 }
            $usedMacro[$t] = 1; $n += $len
        }
    }
    Write-Host "`nmacrotile distinti usati dalla mappa $MapId : $($usedMacro.Count) su 128"
} else {
    for ($m = 0; $m -lt 128; $m++) { $usedMacro[$m] = 1 }
}

$pairs = @{}
$tilePals = @{}
foreach ($m in $usedMacro.Keys) {
    $pal = $b0[$ATTR + $m] -band 3
    foreach ($qoff in 0, 128, 256, 384) {
        $tile = $b0[$TSA + $qoff + $m]
        $key = "$tile/$pal"
        $pairs[$key] = 1
        if (-not $tilePals.ContainsKey($tile)) { $tilePals[$tile] = @{} }
        $tilePals[$tile][$pal] = 1
    }
}

$multi = @($tilePals.Keys | Where-Object { $tilePals[$_].Count -gt 1 })
Write-Host "`nCOPPIE (tile, palette) DISTINTE: $($pairs.Count)" -ForegroundColor Cyan
Write-Host "  tile CHR distinti usati : $($tilePals.Count)"
Write-Host "  di cui con PIU' palette : $($multi.Count)   (sono quelli che costano un tile in piu' a testa)"
if ($pairs.Count -le 256) {
    Write-Host "  -> CI STANNO nei 256 tile TMS, con $(256 - $pairs.Count) di margine" -ForegroundColor Green
} else {
    Write-Host "  -> NON CI STANNO: sforano di $($pairs.Count - 256). Serve un ripiego." -ForegroundColor Red
}

# Il mapman e le sprite vivono anch'essi nei 256 tile del banco pattern? No:
# le sprite hanno una tabella loro. Ma il testo delle finestre di dialogo NO --
# e quello va tenuto da parte adesso, non scoperto dopo.
Write-Host "`nNB: i 256 sono TUTTI i tile di sfondo. Vanno tolti quelli che servono"
Write-Host "    al TESTO delle finestre (negozi, dialoghi): il font BIOS ne occupa 96."
if ($pairs.Count -le 160) {
    Write-Host "    $($pairs.Count) + 96 di font = $($pairs.Count + 96): ci stanno anche col testo." -ForegroundColor Green
} else {
    Write-Host "    $($pairs.Count) + 96 di font = $($pairs.Count + 96): NON ci stanno col testo insieme." -ForegroundColor Yellow
}
