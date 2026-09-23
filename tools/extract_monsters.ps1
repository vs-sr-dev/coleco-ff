# Extract FF1 monster sprite (small enemy gfx 0) da BG 0 di bank_07.dat
# Output: ff1_monsters.h con un array TMS9918 OR-plane silhouette
#
# Layout reference (decoded da bank_0B.asm:3340 DrawSmallEnemy):
# - Battle BG = $800 byte:
#     $000-$0FF: 1 row backdrop (16 tiles, scenery)
#     $100-$7FF: 7 rows enemy CHR (112 tiles)
# - Small enemy gfx 0 = tile $12-$21 = 16 tiles (4x4, 32x32 px)
#   In CHR file: offset $120-$21F (16 tiles * $10 byte/tile = $100 byte)
# - Small enemy gfx 1 = tile $22-$31 = offset $220-$31F
# - Large enemy gfx 0 = tile $32-$55 = offset $320-$55F (6x6 = 36 tiles, 48x48 px)
# - Large enemy gfx 1 = tile $56-$79 = offset $560-$79F
#
# Pipeline NES->TMS9918:
# - Per ogni tile NES (16 byte = 2bpp interleaved planes):
#   row_byte = low_plane[r] | high_plane[r] (OR-plane silhouette)
# - Tile order in NES sprite a 4x4: row-major (cols 0-3 row 0, cols 0-3 row 1, ...)
# - Output: 16 tile pattern (8 byte/tile), TMS9918 BG style

$bank07 = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_07.dat"
$bank0B_names = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0B_94E0_enemynames.bin"
$out_header = "$PSScriptRoot\..\src\ff1_monsters.h"

$bytes = [System.IO.File]::ReadAllBytes($bank07)
"bank_07 size: $($bytes.Length)"

function Convert-NESTileToTMS([byte[]]$tile) {
    # Input: 16 bytes (NES 2bpp)
    # Output: 8 bytes (TMS9918 OR-plane silhouette)
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $out[$r] = $tile[$r] -bor $tile[$r + 8]
    }
    return ,$out
}

# Extract small enemy 0 from BG 0 (offset $120 in bank_07)
$base = 0x120
$tile_count = 16  # 4x4
$small0 = New-Object 'byte[][]' $tile_count
for ($t = 0; $t -lt $tile_count; $t++) {
    $tile = $bytes[($base + $t * 16) .. ($base + $t * 16 + 15)]
    $small0[$t] = Convert-NESTileToTMS $tile
}

# Extract small enemy 1 from BG 0 (offset $220)
$base = 0x220
$small1 = New-Object 'byte[][]' $tile_count
for ($t = 0; $t -lt $tile_count; $t++) {
    $tile = $bytes[($base + $t * 16) .. ($base + $t * 16 + 15)]
    $small1[$t] = Convert-NESTileToTMS $tile
}

# Decode 128 enemy names
function Decode-FF1Name($bytes, $offset, $maxLen=8) {
    $name = ""
    for ($j = 0; $j -lt $maxLen; $j++) {
        $b = $bytes[$offset + $j]
        if ($b -eq 0) { break }
        if ($b -ge 0x8A -and $b -le 0xA3) { $name += [char]([byte][char]'A' + $b - 0x8A) }
        elseif ($b -ge 0xA4 -and $b -le 0xBD) { $name += [char]([byte][char]'a' + $b - 0xA4) }
        else { $name += '?' }
    }
    while ($name.Length -lt $maxLen) { $name += ' ' }
    return $name
}

$nameBytes = [System.IO.File]::ReadAllBytes($bank0B_names)
$ptr_base = 0x94E0
$names = @()
for ($i = 0; $i -lt 128; $i++) {
    $lo = [int]$nameBytes[$i*2]
    $hi = [int]$nameBytes[$i*2+1]
    $addr = ($hi * 256) + $lo
    $off = $addr - $ptr_base
    if ($off -ge 0 -and $off -lt $nameBytes.Length) {
        $names += Decode-FF1Name $nameBytes $off 8
    } else {
        $names += "?       "
    }
}

# Generate header
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("// ff1_monsters.h - Generated from FF1 NES disasm")
[void]$sb.AppendLine("// Small enemy graphics extracted from bank_07.dat BG 0.")
[void]$sb.AppendLine("// OR-plane silhouette TMS9918 BG tile format.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Each small enemy = 16 tiles arranged 4 wide x 4 tall (32x32 px).")
[void]$sb.AppendLine("// Tile order: row-major (col0..3 row0, col0..3 row1, ...).")
[void]$sb.AppendLine()
[void]$sb.AppendLine("#ifndef FF1_MONSTERS_H")
[void]$sb.AppendLine("#define FF1_MONSTERS_H")
[void]$sb.AppendLine()
[void]$sb.AppendLine("#define FF1_SMALL_ENEMY_TILES 16")
[void]$sb.AppendLine()

# Small enemy 0
[void]$sb.AppendLine("static const unsigned char ff1_small_enemy_bg0_gfx0[FF1_SMALL_ENEMY_TILES][8] = {")
for ($t = 0; $t -lt $tile_count; $t++) {
    $line = "    { "
    for ($r = 0; $r -lt 8; $r++) {
        $line += "0x{0:X2}" -f $small0[$t][$r]
        if ($r -lt 7) { $line += ", " }
    }
    $line += " },  // tile $t"
    [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine()

# Small enemy 1
[void]$sb.AppendLine("static const unsigned char ff1_small_enemy_bg0_gfx1[FF1_SMALL_ENEMY_TILES][8] = {")
for ($t = 0; $t -lt $tile_count; $t++) {
    $line = "    { "
    for ($r = 0; $r -lt 8; $r++) {
        $line += "0x{0:X2}" -f $small1[$t][$r]
        if ($r -lt 7) { $line += ", " }
    }
    $line += " },  // tile $t"
    [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine()

# Enemy names array
[void]$sb.AppendLine("// Enemy names (decoded from custom NES charset, max 8 chars + null).")
[void]$sb.AppendLine("// Source: bin/0B_94E0_enemynames.bin")
[void]$sb.AppendLine("#define FF1_ENEMY_COUNT 128")
[void]$sb.AppendLine("static const char ff1_enemy_names[FF1_ENEMY_COUNT][9] = {")
for ($i = 0; $i -lt 128; $i++) {
    $n = $names[$i]
    [void]$sb.AppendLine("    `"$n`",  // $i")
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine()
[void]$sb.AppendLine("#endif  // FF1_MONSTERS_H")

[System.IO.File]::WriteAllText($out_header, $sb.ToString())

"Written: $out_header"
"First 8 enemy names: $($names[0..7] -join ', ')"
