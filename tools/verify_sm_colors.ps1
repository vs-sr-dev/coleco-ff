# verify_sm_colors.ps1 -- la TSA rimappata dice le stesse cose di quella vecchia?
#
# extract_sm_colors.ps1 sostituisce gli id di tile NES con id di COPPIA
# (tile, palette). E' una traduzione: se e' giusta, ritradotta all'indietro
# deve ridare esattamente la TSA monocroma di ff1_town_coneria.h, che era gia'
# validata a schermo in slice40.
#
# Serve perche' un errore qui NON da' errore: da' una citta' con la geometria
# giusta e i tile sbagliati -- che a occhio somiglia a "sono spawnato nel posto
# sbagliato", ed e' esattamente il modo in cui e' stato riportato.

param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

function Get-CArray([string]$file, [string]$pattern) {
    $txt = Get-Content (Join-Path $Root $file) -Raw
    $m = [regex]::Match($txt, $pattern, 'Singleline')
    if (-not $m.Success) { throw "non trovato in ${file}: $pattern" }
    return @([regex]::Matches($m.Groups[1].Value, '0x([0-9A-Fa-f]{2})') |
             ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) })
}

$oldTsa = @()
foreach ($q in 'ul','ur','dl','dr') {
    $oldTsa += ,(Get-CArray 'src\ff1_town_coneria.h' "ff1_town_tsa_$q\[128\]\s*=\s*\{(.*?)\n\};")
}
$newTsa = @()
foreach ($q in 'ul','ur','dl','dr') {
    $newTsa += ,(Get-CArray 'src\ff1_towngfx.h' "ff1_towngfx_tsa_$q\[FF1_TOWNGFX_MACRO_COUNT\]\s*=\s*\{(.*?)\n\};")
}
$map = Get-CArray 'src\ff1_towngfx.h' 'ff1_towngfx_map\[FF1_TOWNGFX_MAP_W \* FF1_TOWNGFX_MAP_H\]\s*=\s*\{(.*?)\n\};'

# Ricostruisco la tabella delle coppie con lo STESSO ordine dell'estrattore.
$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Root 'FF1Disassembly-master\Final Fantasy Disassembly\bank_00.dat'))
$ATTR_BASE = 0x0400
$TSA_BASE  = 0x1000
$used = @{}
foreach ($v in $map) { $used[$v] = 1 }

$comboId = @{}
$comboTile = New-Object System.Collections.ArrayList
for ($m = 0; $m -lt 128; $m++) {
    if (-not $used.ContainsKey($m)) { continue }
    $pal = [int]$b00[$ATTR_BASE + $m] -band 3
    foreach ($qoff in 0, 128, 256, 384) {
        $tid = [int]$b00[$TSA_BASE + $qoff + $m]
        $key = "$tid/$pal"
        if (-not $comboId.ContainsKey($key)) {
            $comboId[$key] = $comboTile.Count
            [void]$comboTile.Add($tid)
        }
    }
}
Write-Host "coppie ricostruite: $($comboTile.Count)"

# --- il controllo vero -------------------------------------------------------
$bad = 0; $checked = 0; $examples = @()
for ($m = 0; $m -lt 128; $m++) {
    if (-not $used.ContainsKey($m)) { continue }
    for ($q = 0; $q -lt 4; $q++) {
        $checked++
        $backTile = [int]$comboTile[$newTsa[$q][$m]]
        $wantTile = [int]$oldTsa[$q][$m]
        if ($backTile -ne $wantTile) {
            $bad++
            if ($examples.Count -lt 8) {
                $examples += ("  macro 0x{0:X2} quad {1}: nuova={2} -> tile {3}, la vecchia diceva {4}" -f
                              $m, $q, $newTsa[$q][$m], $backTile, $wantTile)
            }
        }
    }
}
Write-Host "controllati $checked quadranti di macrotile usati"
if ($bad -eq 0) {
    Write-Host "TSA COERENTE: ritradotta all'indietro da' la stessa di slice40" -ForegroundColor Green
} else {
    Write-Host "TSA INCOERENTE: $bad quadranti su $checked" -ForegroundColor Red
    $examples | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
