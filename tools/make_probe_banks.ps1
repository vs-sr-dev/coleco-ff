# make_probe_banks.ps1
#
# Genera i blob sentinella per slice45 (MegaCart bank probe).
#
# Ogni banco N produce un blob da 16384 byte:
#   offset 0..16319   = byte sentinella $B0+N (unico per banco)
#   offset 16320..16383 = $FF (zona trigger $FFC0-$FFFF: mai dati veri, o la
#                         lettura re-banca involontariamente la finestra alta)
#
# Uso:
#   .\make_probe_banks.ps1                       # banchi 1..14 in ..\build
#   .\make_probe_banks.ps1 -MaxBank 6 -OutDir X  # solo 1..6

param(
    [int]$MaxBank  = 14,
    [string]$OutDir = "$PSScriptRoot\..\build"
)

$ErrorActionPreference = 'Stop'

if ($MaxBank -lt 1 -or $MaxBank -gt 62) { throw "MaxBank fuori range (1..62), ricevuto $MaxBank" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$bankSize    = 16384
$triggerZone = 64
$dataLen     = $bankSize - $triggerZone

$paths = @()
for ($n = 1; $n -le $MaxBank; $n++) {
    $sentinel = [byte](0xB0 + $n)
    $blob = [System.Array]::CreateInstance([byte], $bankSize)
    for ($i = 0; $i -lt $dataLen; $i++)  { $blob[$i] = $sentinel }
    for ($i = $dataLen; $i -lt $bankSize; $i++) { $blob[$i] = [byte]0xFF }

    $name = 'probe_bank_{0:D2}.bin' -f $n
    $path = Join-Path $OutDir $name
    [System.IO.File]::WriteAllBytes($path, $blob)
    $paths += "$n=$path"
    Write-Host ("bank {0,2} -> {1}  (sentinel 0x{2})" -f $n, $name, $sentinel.ToString('X2'))
}

# Stampa la riga -Banks pronta da incollare in build_megacart.ps1
Write-Host ""
Write-Host "-Banks argument:"
Write-Host ("  -Banks " + (($paths | ForEach-Object { "'$_'" }) -join ','))
