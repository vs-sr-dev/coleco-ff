# Dump ASCII visivo dei battle sprite estratti per sanity check.

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path "..\FF1Disassembly-master\Final Fantasy Disassembly\bank_09.bin"))
$classNames = @("FT", "TH", "BB", "RM", "WM", "BM")
$CLASS_BASE = 0x1000
$CLASS_STRIDE = 0x200

function Render-Tile($srcBytes, $offset) {
    # OR planes -> 8 byte 1bpp
    $rows = @()
    for ($r = 0; $r -lt 8; $r++) {
        $b = ($srcBytes[$offset + $r] -bor $srcBytes[$offset + 8 + $r]) -band 0xFF
        $line = ""
        for ($bit = 7; $bit -ge 0; $bit--) {
            if (($b -shr $bit) -band 1) { $line += "##" } else { $line += "  " }
        }
        $rows += $line
    }
    return $rows
}

function Render-2x3($srcBytes, $classOff) {
    # 6 tiles: UL UR ML MR DL DR
    $tiles = @()
    for ($t = 0; $t -lt 6; $t++) {
        $tiles += ,(Render-Tile $srcBytes ($classOff + $t * 16))
    }
    # Compose 2x3
    $out = @()
    # Rows 0-2 of NES tiles: UL+UR, ML+MR, DL+DR
    foreach ($pair in @(@(0,1), @(2,3), @(4,5))) {
        for ($r = 0; $r -lt 8; $r++) {
            $out += ($tiles[$pair[0]][$r] + $tiles[$pair[1]][$r])
        }
    }
    return $out
}

for ($c = 0; $c -lt 6; $c++) {
    Write-Host ""
    Write-Host "=== Class $($classNames[$c]) (offset 0x$('{0:X4}' -f ($CLASS_BASE + $c * $CLASS_STRIDE))) ==="
    $img = Render-2x3 $bytes ($CLASS_BASE + $c * $CLASS_STRIDE)
    foreach ($line in $img) { Write-Host $line }
}

Write-Host ""
Write-Host "=== Cursor (offset 0x2F00, tile F0 F1 F2 F3) - layout 2x2 ==="
$tiles = @()
for ($t = 0; $t -lt 4; $t++) {
    $tiles += ,(Render-Tile $bytes (0x2F00 + $t * 16))
}
# Layout UL UR / DL DR
foreach ($pair in @(@(0,1), @(2,3))) {
    for ($r = 0; $r -lt 8; $r++) {
        Write-Host ($tiles[$pair[0]][$r] + $tiles[$pair[1]][$r])
    }
}
