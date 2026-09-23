# =====================================================================
#  find_ai_domains.ps1 -- quali domini di incontro contengono nemici con IA
# =====================================================================
# A che serve: la validazione della magia nemica ha bisogno di incontrare un
# nemico che l'IA ce l'abbia (ENROMSTAT_AI != $FF). Intorno a Coneria ci sono
# solo IMP, che non ce l'hanno. Invece di camminare a caso, si incrociano le
# tre tabelle gia' in casa e si stampa DOVE andare.
#
# Catena: dominio -> 8 formazioni -> fino a 4 gruppi -> id nemico -> byte 7.
# Le coordinate del mondo si ricavano invertendo compute_domain:
#   dominio = ((nes_y & 0xE0) >> 2) | (nes_x >> 5)
# quindi y sta nel blocco di 32 dato dai bit alti e x pure.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Read-ByteRows([string]$path, [string]$startPattern) {
    $lines = Get-Content (Join-Path $root $path)
    $rows = @()
    $inside = $false
    foreach ($l in $lines) {
        if (-not $inside) { if ($l -match $startPattern) { $inside = $true }; continue }
        if ($l -match '^\s*\};') { break }
        $hexes = [regex]::Matches($l, '0x([0-9A-Fa-f]{2})')
        if ($hexes.Count -gt 0) {
            foreach ($h in $hexes) { $rows += [Convert]::ToInt32($h.Groups[1].Value, 16) }
        }
    }
    return $rows
}

# --- IA per id nemico -------------------------------------------------
$enemyAi = @{}
$lines = Get-Content (Join-Path $root 'src\data\enemy_data.h')
$prev = $null
foreach ($l in $lines) {
    if ($l -match '^\s*0x') { $prev = $l; continue }
    if ($l -match '^// \$([0-9A-F]{2})\s+(\S+)' -and $prev) {
        $id = [Convert]::ToInt32($matches[1], 16)
        $nm = $matches[2]
        $b = ($prev -split ',') | ForEach-Object { $_.Trim() }
        $ai = [Convert]::ToInt32(($b[7] -replace '0x', ''), 16)
        $enemyAi[$id] = @{ name = $nm; ai = $ai }
    }
}

$domains    = Read-ByteRows 'src\ff1_encounter.h' 'ff1_domains\[128\]\[8\]'
$formations = Read-ByteRows 'src\ff1_encounter.h' 'ff1_battle_formations\[128 \* 16\]'

Write-Host "  domini: $($domains.Count / 8)   formazioni: $($formations.Count / 16)"

$hits = @()
for ($d = 0; $d -lt 128; $d++) {
    $names = @{}
    for ($s = 0; $s -lt 8; $s++) {
        $fid = $domains[$d * 8 + $s]
        $f = ($fid -band 0x7F) * 16
        # byte 2-5 = i quattro gruppi (id nemico), byte 1 = slot grafici
        for ($g = 2; $g -le 5; $g++) {
            $eid = $formations[$f + $g]
            if ($enemyAi.ContainsKey($eid) -and $enemyAi[$eid].ai -ne 0xFF) {
                $names[$enemyAi[$eid].name] = $enemyAi[$eid].ai
            }
        }
    }
    if ($names.Count -gt 0) {
        # Inversione di compute_domain: y nei bit 6-4 del dominio, x nei 3-0
        $ybase = (($d -band 0x78) -shl 2)
        $xbase = (($d -band 0x07) -shl 5)
        $lst = ($names.Keys | Sort-Object) -join ','
        $hits += [pscustomobject]@{
            Dom = '0x' + $d.ToString('X2')
            X   = "$xbase-$($xbase + 31)"
            Y   = "$ybase-$($ybase + 31)"
            Con = $lst
        }
    }
}

Write-Host "  domini con nemici dotati di IA: $($hits.Count) su 128"
$hits | Format-Table -AutoSize
