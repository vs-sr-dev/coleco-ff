# extract_battle_bg.ps1 - Estrae backdrop tiles da FF1 bank_07.dat / bank_08.dat
#
# Ogni backdrop = 18 tile NES 2bpp (288 byte). Layout NES:
#   1 row of 16 tiles + 2 extra tiles (totale 18 tile)
# Bank_07 contiene backdrops #0-7, bank_08 contiene #8-15.
# Ogni backdrop a offset (idx * $800) nel bank.
#
# Output: src/ff1_battle_bg.h con:
#   ff1_battle_bg_tile[18][8] - 18 tile silhouette OR-plane TMS9918 1bpp
#
# MVP: estrae solo backdrop #0 (default per slice35 demo). Estendere a tutti 16 quando area-aware lookup implementato.

param(
    [string]$bankPath = "..\FF1Disassembly-master\Final Fantasy Disassembly\bank_07.dat",
    [string]$outPath  = "..\src\ff1_battle_bg.h",
    [int]$backdropIdx = 0   # 0..7 in bank_07, 8..15 in bank_08
)

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $bankPath))
Write-Host "Loaded $bankPath : $($bytes.Length) bytes"

$slotOffset = $backdropIdx * 0x800
$backdropBytes = 18 * 16  # 18 tiles * 16 byte per NES 2bpp tile = 288 byte
Write-Host "Backdrop #$backdropIdx at offset 0x$('{0:X4}' -f $slotOffset), $backdropBytes byte"

function Convert-NesTile($srcBytes, [int]$tileOff) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$tileOff + $r]
        $hi = $srcBytes[$tileOff + 8 + $r]
        $out[$r] = [byte](($lo -bor $hi) -band 0xFF)
    }
    return $out
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATED da bank_07.dat (FF1 disasm Disch)")
[void]$sb.AppendLine("// Battle BG backdrop tiles (18 tile per backdrop, OR-plane silhouette)")
[void]$sb.AppendLine("// MVP: solo backdrop #$backdropIdx. Estendere quando area-aware implementato.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_BATTLE_BG_H")
[void]$sb.AppendLine("#define FF1_BATTLE_BG_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#define FF1_BATTLE_BG_TILE_COUNT 18")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("static const unsigned char ff1_battle_bg_tile[18][8] = {")

for ($t = 0; $t -lt 18; $t++) {
    $tileOff = $slotOffset + $t * 16
    $tile = Convert-NesTile $bytes $tileOff
    $hex = ""
    for ($i = 0; $i -lt 8; $i++) {
        $hex += ("0x{0:X2}" -f $tile[$i])
        if ($i -lt 7) { $hex += ", " }
    }
    [void]$sb.AppendLine("    { $hex }, // tile [$t]")
}

[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif")

[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $outPath), $sb.ToString())
Write-Host "Written: $outPath"
Write-Host "  18 tile x 8 byte = 144 byte TMS9918 backdrop data"
