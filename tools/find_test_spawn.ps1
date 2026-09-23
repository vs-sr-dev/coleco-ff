# =====================================================================
#  find_test_spawn.ps1 -- una casella dove far partire una build di PROVA
# =====================================================================
# Il problema che risolve: dal continente iniziale non si raggiunge nessun
# nemico dotato di IA (tools/find_ai_domains.ps1 lo dimostra: i domini 0x2B e
# 0x2C sono gli unici due senza). Per osservare la magia nemica serve far
# partire una build di prova altrove -- ma "altrove" dev'essere una casella
# CAMMINABILE e con il bit FIGHT acceso, se no il gruppo resta piantato o non
# tira mai l'incontro. Indovinarla a occhio e' costato tempo altre volte.
#
# Ingressi: src/ff1_owmap_full.bin (256x256 macro-id) e ff1_ow_attr.
# Uscita: le prime N caselle valide, con il loro dominio.

param([int]$Want = 6, [int]$MinCoverage = 7)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$map = [System.IO.File]::ReadAllBytes((Join-Path $root 'src\ff1_owmap_full.bin'))
if ($map.Length -ne 65536) { throw "mappa di $($map.Length) byte, attesi 65536" }

# ff1_ow_attr: 128 coppie. Byte 0 = maschera dei DIVIETI, byte 1 = fight/teleport.
$attr0 = New-Object 'int[]' 128
$attr1 = New-Object 'int[]' 128
$i = 0
foreach ($l in Get-Content (Join-Path $root 'src\ff1_encounter.h')) {
    if ($l -match '^\s*\{0x([0-9A-Fa-f]{2}),\s*0x([0-9A-Fa-f]{2})\}') {
        if ($i -lt 128) {
            $attr0[$i] = [Convert]::ToInt32($matches[1], 16)
            $attr1[$i] = [Convert]::ToInt32($matches[2], 16)
            $i++
        }
    }
}
if ($i -ne 128) { throw "lette $i coppie di attributi, attese 128" }

# I domini che contengono nemici con IA, dalla tabella gia' incrociata.
$aiDom = @{}
foreach ($line in (& (Join-Path $PSScriptRoot 'find_ai_domains.ps1')) ) { }
# find_ai_domains stampa e basta: qui rifacciamo il conto minimo che serve,
# cioe' "questo dominio ha almeno un nemico con IA", leggendo le stesse tabelle.
$domains = @()
$formations = @()
$inside = ''
foreach ($l in Get-Content (Join-Path $root 'src\ff1_encounter.h')) {
    if ($l -match 'ff1_domains\[128\]\[8\]')          { $inside = 'dom'; continue }
    if ($l -match 'ff1_battle_formations\[128 \* 16\]') { $inside = 'form'; continue }
    if ($l -match '^\s*\};') { $inside = ''; continue }
    if ($inside -eq '') { continue }
    foreach ($h in [regex]::Matches($l, '0x([0-9A-Fa-f]{2})')) {
        $v = [Convert]::ToInt32($h.Groups[1].Value, 16)
        if ($inside -eq 'dom') { $domains += $v } else { $formations += $v }
    }
}
$enemyAi = @{}
$prev = $null
foreach ($l in Get-Content (Join-Path $root 'src\data\enemy_data.h')) {
    if ($l -match '^\s*0x') { $prev = $l; continue }
    if ($l -match '^// \$([0-9A-F]{2})\s+(\S+)' -and $prev) {
        $b = ($prev -split ',') | ForEach-Object { $_.Trim() }
        $enemyAi[[Convert]::ToInt32($matches[1],16)] = [Convert]::ToInt32(($b[7] -replace '0x',''),16)
    }
}
# Non basta "il dominio ha almeno un nemico con IA": la formazione la sceglie
# battlecounter, e con una sola casella su otto si puo' combattere per mezz'ora
# senza incontrarlo -- e' successo, quattro battaglie di fila con nemici senza
# IA. Qui si conta su QUANTE delle 8 caselle esce almeno un nemico dotato di
# IA, e piu' avanti si pretende una copertura alta.
# Solo le PRIME QUATTRO caselle contano davvero. ff1_formation_weight le pesca
# con 12 possibilita' su 64 ciascuna, contro 6 per la quinta e la sesta, 3 per
# la settima e UNA per l'ottava. Contare tutte e otto ha portato a scegliere un
# dominio con copertura 5/8 dove pero' l'IA stava nelle caselle rare: quattro
# battaglie di fila senza vederla.
for ($d = 0; $d -lt 128; $d++) {
    $cov = 0
    for ($s = 0; $s -lt 4; $s++) {
        $f = ($domains[$d * 8 + $s] -band 0x7F) * 16
        $has = $false
        for ($g = 2; $g -le 5; $g++) {
            $eid = $formations[$f + $g]
            if ($enemyAi.ContainsKey($eid) -and $enemyAi[$eid] -ne 0xFF) { $has = $true }
        }
        if ($has) { $cov++ }
    }
    if ($cov -gt 0) { $aiDom[$d] = $cov }
}

# compute_domain per le caselle di TERRA (sub-dominio 00):
#   dominio = ((y & 0xE0) >> 2) | (x >> 5)
$found = 0
Write-Host "  cerco caselle camminabili con FIGHT, in domini che hanno nemici con IA"
for ($y = 0; $y -lt 256 -and $found -lt $Want; $y++) {
    for ($x = 0; $x -lt 256 -and $found -lt $Want; $x++) {
        $dom = ((($y -band 0xE0) -shr 2) -bor ($x -shr 5))
        if (-not $aiDom.ContainsKey($dom)) { continue }
        if ($aiDom[$dom] -lt $MinCoverage) { continue }
        # Non basta la singola casella: serve un INTORNO libero. La prima
        # ricerca aveva scelto una lingua di terra larga una casella fra il
        # mare e un deserto, e il gruppo di prova ci e' rimasto piantato per
        # 20000 frame senza tirare un solo incontro -- il tiro e' legato al
        # PASSO, e li' i passi non si facevano. 11 caselle per lato sono
        # abbastanza da far pattugliare il driver senza sbattere.
        $ok = $true
        for ($dy = -5; $dy -le 5 -and $ok; $dy++) {
            for ($dx = -5; $dx -le 5 -and $ok; $dx++) {
                $nx = ($x + $dx) -band 0xFF
                $ny = ($y + $dy) -band 0xFF
                $mm = $map[$ny * 256 + $nx] -band 0x7F
                if (($attr0[$mm] -band 0x01) -ne 0) { $ok = $false }   # NOWALK
                elseif (($attr1[$mm] -band 0x40) -eq 0) { $ok = $false } # no FIGHT
                elseif (($attr1[$mm] -band 0x03) -ne 0) { $ok = $false } # non terra
            }
        }
        if (-not $ok) { continue }
        $m = $map[$y * 256 + $x] -band 0x7F
        Write-Host ("  x={0,3} y={1,3}  macro=0x{2}  dominio=0x{3}" -f `
              $x, $y, $m.ToString('X2'), $dom.ToString('X2')) + "  copertura=$($aiDom[$dom])/8"
        $found++
    }
}
if ($found -eq 0) { Write-Host "  nessuna casella trovata" }
