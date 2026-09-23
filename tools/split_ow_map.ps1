# tools/split_ow_map.ps1
#
# Split the full 256x256 FF1 OW macrotile map into 4 quadrant blobs of 16KB
# each, suitable for MegaCart banks 3-6 of slice43c+.
#
# Input  : data/ff1_ow_full.bin   (65536 bytes, row-major [y][x] -> macro id)
#          NB: questo e' l'output di extract_ow_tilemap.ps1 (full 256x256).
#          NON usare src/ff1_owmap_full.bin (artefatto stale/incompleto:
#          righe 144-255 vuote -> spawn verde). Vedi memory/slice44_real_root_causes.md.
# Output : build/owmap_nw_bank.bin  rows  0-127, cols   0-127  (16384B)
#          build/owmap_ne_bank.bin  rows  0-127, cols 128-255  (16384B)
#          build/owmap_sw_bank.bin  rows 128-255, cols   0-127  (16384B)
#          build/owmap_se_bank.bin  rows 128-255, cols 128-255  (16384B)
#
# Each quadrant has its 128 rows of 128 bytes contiguous: byte at offset
# (qy * 128 + qx) is the macrotile at quadrant-local (qx, qy).
# At runtime with the appropriate bank selected, the quadrant lives at $C000.

param(
    [string]$In     = "$PSScriptRoot\..\data\ff1_ow_full.bin",
    [string]$OutDir = "$PSScriptRoot\..\build"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $In)) { throw "input not found: $In" }
$src = [System.IO.File]::ReadAllBytes($In)
if ($src.Length -ne 65536) {
    throw ("expected 65536-byte input, got {0}" -f $src.Length)
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$names = @('nw', 'ne', 'sw', 'se')
for ($q = 0; $q -lt 4; $q++) {
    $rowBase = ($q -shr 1) * 128       # 0 or 128
    $colBase = ($q -band 1) * 128      # 0 or 128
    $blob = [System.Array]::CreateInstance([byte], 16384)
    for ($r = 0; $r -lt 128; $r++) {
        $srcOff = ($rowBase + $r) * 256 + $colBase
        $dstOff = $r * 128
        [Array]::Copy($src, $srcOff, $blob, $dstOff, 128)
    }
    $outPath = Join-Path $OutDir ("owmap_{0}_bank.bin" -f $names[$q])
    [System.IO.File]::WriteAllBytes($outPath, $blob)
    Write-Host ("Wrote {0} (16384 bytes -- rows {1}-{2}, cols {3}-{4})" -f `
        $outPath, $rowBase, ($rowBase + 127), $colBase, ($colBase + 127))
}

Write-Host ''
Write-Host 'Done. Splice into MC ROM with:'
Write-Host '  build_megacart.ps1 ... -Bank3 build\owmap_nw_bank.bin'
Write-Host '                         -Bank4 build\owmap_ne_bank.bin'
Write-Host '                         -Bank5 build\owmap_sw_bank.bin'
Write-Host '                         -Bank6 build\owmap_se_bank.bin'
