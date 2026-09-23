# extract_sm_coneria.ps1
#
# Extract FF1 NES Standard Map data for Coneria Town (Map ID 0, tileset 0).
#
# Sources (FF1Disassembly-master / Final Fantasy Disassembly):
#   bank_00.dat — SMTilesetAttr (offset $0400), SMTilesetProp ($0800),
#                  SMTilesetTSA ($1000), EntrTele_X/Y/Map ($2C00..$2C7F),
#                  lut_Tilesets ($2CC0).
#   bank_03.dat — Tileset CHR (NES 2bpp): tileset T at offset T*$800.
#   bank_04..07.dat — Standard Map RLE bitstreams. The pointer table
#                     (lut_SMPtrTbl) lives at offset 0 of bank_04, 128 maps
#                     * 2 bytes each. Pointer encodes (bank_offset:2) in the
#                     high two bits of the high byte; address inside the
#                     bank is (((hi & $3F) | $80) << 8) | lo.
#
# RLE format (see DecompressMap in bank_0F.asm $D04F):
#   $00-$7F : literal macrotile
#   $80-$FE : run header (tile = byte & $7F), next byte = run length
#             (length 0 = 256)
#   $FF     : end-of-map terminator
# The decoder may cross bank boundaries; treating bank_04..07 as one
# concatenated 64KB buffer keeps the source pointer linear since
# @NextBank resets address to $8000 while advancing the bank — the file
# offset is unchanged.
#
# Output:
#   src/ff1_town_coneria.h
#     - ff1_town_coneria_map[64][64]    decompressed macrotile grid
#     - ff1_town_tsa_ul/ur/dl/dr[128]   NES 8x8 tile id per quadrant
#     - ff1_town_attr[128]              SMTilesetAttr (palette bits)
#     - ff1_town_prop[128][2]           SMTilesetProp (walk/teleport bits)
#     - ff1_town_pattern[128*8]         OR-planed TMS9918 1bpp patterns
#     - FF1_TOWN_CONERIA_ENTRY_X/Y      player entry coords in town map
#     - FF1_TOWN_CONERIA_MAP_ID / FF1_TOWN_CONERIA_TILESET_ID
#
# Usage:
#   .\extract_sm_coneria.ps1

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OutHdr = "$PSScriptRoot\..\src\ff1_town_coneria.h",
    [int]$MapId = 0
)

$ErrorActionPreference = 'Stop'

function ReadBank([string]$name) {
    $p = Join-Path $Disasm $name
    if (-not (Test-Path $p)) { throw "missing $p" }
    [System.IO.File]::ReadAllBytes($p)
}

$b0 = ReadBank 'bank_00.dat'
$b3 = ReadBank 'bank_03.dat'
$b4 = ReadBank 'bank_04.dat'
$b5 = ReadBank 'bank_05.dat'
$b6 = ReadBank 'bank_06.dat'
$b7 = ReadBank 'bank_07.dat'

# Concatenate banks 04..07 for linear RLE decode
$sm = New-Object byte[] (16384 * 4)
[Array]::Copy($b4, 0, $sm, 0,      16384)
[Array]::Copy($b5, 0, $sm, 16384,  16384)
[Array]::Copy($b6, 0, $sm, 32768,  16384)
[Array]::Copy($b7, 0, $sm, 49152,  16384)

# Resolve map pointer
$lo = [int]$sm[$MapId * 2]
$hi = [int]$sm[$MapId * 2 + 1]
$bankIdx = ($hi -shr 6) -band 3
$addr = ((($hi -band 0x3F) -bor 0x80) -shl 8) -bor $lo
$src = $bankIdx * 16384 + ($addr - 0x8000)
$ptrHex = '0x{0:X2}{1:X2}' -f $hi, $lo
$addrHex = '0x{0:X4}' -f $addr
Write-Host ("Map {0}: ptr={1} addr={2} (bank+{3}, concat off=0x{4:X5})" -f $MapId, $ptrHex, $addrHex, $bankIdx, $src)

# Decompress to 64x64 = 4096 macrotiles
$map = New-Object byte[] 4096
$written = 0
$srcStart = $src
while ($written -lt 4096) {
    if ($src -ge $sm.Length) { throw "src overflow (off=0x$($src.ToString('X5')))" }
    $b = [int]$sm[$src]; $src++
    if ($b -eq 0xFF) { break }
    if ($b -lt 0x80) {
        $map[$written] = [byte]$b
        $written++
    } else {
        $tile = $b -band 0x7F
        $len = [int]$sm[$src]; $src++
        if ($len -eq 0) { $len = 256 }
        for ($i = 0; $i -lt $len; $i++) {
            if ($written -ge 4096) { throw "RLE run overflow (tile=0x$($tile.ToString('X2')) len=$len)" }
            $map[$written] = [byte]$tile
            $written++
        }
    }
}
$srcEnd = $src
Write-Host ("Decompressed {0}/4096 tiles, consumed {1} compressed bytes" -f $written, ($srcEnd - $srcStart))
if ($written -ne 4096) { throw "expected 4096 tiles, got $written" }

# Identify tileset and entry coords
$tilesetId = [int]$b0[0x2CC0 + $MapId]
$entryX = [int]$b0[0x2C00 + 1]   # ID 01 = Coneria town entrance teleport
$entryY = [int]$b0[0x2C20 + 1]
$entryMap = [int]$b0[0x2C40 + 1]
if ($entryMap -ne $MapId) { Write-Host ("WARN: EntrTele[1].Map = {0} != requested {1}" -f $entryMap, $MapId) }
Write-Host ("Tileset {0} | Entry ({1},{2}) from EntrTele ID 01" -f $tilesetId, $entryX, $entryY)

# Tileset 0 SM data (per-tileset blocks in bank_00)
$attr = $b0[(0x0400 + $tilesetId * 128)..(0x0400 + $tilesetId * 128 + 127)]
$prop = $b0[(0x0800 + $tilesetId * 256)..(0x0800 + $tilesetId * 256 + 255)]
$tsa  = $b0[(0x1000 + $tilesetId * 512)..(0x1000 + $tilesetId * 512 + 511)]

# Tileset CHR (bank_03): 128 NES tiles * 16 bytes = 2048 bytes per tileset.
$chrStart = $tilesetId * 0x800
$chrNes = $b3[$chrStart..($chrStart + 0x7FF)]
# OR-plane the 2bpp -> 1bpp (silhouette). Same scheme as ff1_owbg_pattern.
$chr1bpp = New-Object byte[] (128 * 8)
for ($t = 0; $t -lt 128; $t++) {
    for ($i = 0; $i -lt 8; $i++) {
        $p0 = [int]$chrNes[$t * 16 + $i]
        $p1 = [int]$chrNes[$t * 16 + 8 + $i]
        $chr1bpp[$t * 8 + $i] = [byte](($p0 -bor $p1) -band 0xFF)
    }
}

# Emit header
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATED by tools/extract_sm_coneria.ps1")
[void]$sb.AppendLine(("// FF1 Standard Map ID {0} (Coneria Town), tileset {1}." -f $MapId, $tilesetId))
[void]$sb.AppendLine(("// Decompressed 64x64 macrotiles from bank_04+ concat offset 0x{0:X5}." -f $srcStart))
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_TOWN_CONERIA_H")
[void]$sb.AppendLine("#define FF1_TOWN_CONERIA_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine(("#define FF1_TOWN_CONERIA_MAP_ID     {0}" -f $MapId))
[void]$sb.AppendLine(("#define FF1_TOWN_CONERIA_TILESET_ID {0}" -f $tilesetId))
[void]$sb.AppendLine(("#define FF1_TOWN_CONERIA_ENTRY_X    {0}" -f $entryX))
[void]$sb.AppendLine(("#define FF1_TOWN_CONERIA_ENTRY_Y    {0}" -f $entryY))
[void]$sb.AppendLine("#define FF1_TOWN_TILE_COUNT          128")
[void]$sb.AppendLine("")

# Macrotile grid
[void]$sb.AppendLine("static const unsigned char ff1_town_coneria_map[64][64] = {")
for ($y = 0; $y -lt 64; $y++) {
    [void]$sb.Append("    {")
    for ($x = 0; $x -lt 64; $x++) {
        [void]$sb.Append(("0x{0:X2}" -f $map[$y * 64 + $x]))
        if ($x -lt 63) { [void]$sb.Append(",") }
    }
    [void]$sb.Append("}")
    if ($y -lt 63) { [void]$sb.Append(",") }
    [void]$sb.AppendLine(("  // y={0}" -f $y))
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# TSA per quadrant. lut_SMTilesetTSA layout (per LoadSMTilesetData in
# bank_0F.asm + variables.inc tsa_ul/ur/dl/dr): four CONTIGUOUS 128-byte
# blocks — NOT interleaved (m*4+q). The 512-byte tileset slice is
# [tsa_ul 128][tsa_ur 128][tsa_dl 128][tsa_dr 128].
$labels = @('ul','ur','dl','dr')
$offsets = @(0, 128, 256, 384)
for ($q = 0; $q -lt 4; $q++) {
    $base = $offsets[$q]
    [void]$sb.AppendLine(("static const unsigned char ff1_town_tsa_{0}[128] = {{" -f $labels[$q]))
    for ($row = 0; $row -lt 8; $row++) {
        [void]$sb.Append("    ")
        for ($col = 0; $col -lt 16; $col++) {
            $t = $row * 16 + $col
            [void]$sb.Append(("0x{0:X2}" -f $tsa[$base + $t]))
            if ($t -lt 127) { [void]$sb.Append(",") }
        }
        [void]$sb.AppendLine()
    }
    [void]$sb.AppendLine("};")
    [void]$sb.AppendLine("")
}

# Attr (1 byte per macrotile)
[void]$sb.AppendLine("static const unsigned char ff1_town_attr[128] = {")
for ($row = 0; $row -lt 8; $row++) {
    [void]$sb.Append("    ")
    for ($col = 0; $col -lt 16; $col++) {
        $t = $row * 16 + $col
        [void]$sb.Append(("0x{0:X2}" -f $attr[$t]))
        if ($t -lt 127) { [void]$sb.Append(",") }
    }
    [void]$sb.AppendLine()
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# Prop (2 bytes per macrotile). Use string interpolation — PowerShell's -f
# operator only consumes the first arg if you give it a comma list.
[void]$sb.AppendLine("static const unsigned char ff1_town_prop[128][2] = {")
for ($t = 0; $t -lt 128; $t++) {
    $p0 = $prop[$t * 2].ToString('X2')
    $p1 = $prop[$t * 2 + 1].ToString('X2')
    [void]$sb.Append("    {0x$p0,0x$p1}")
    if ($t -lt 127) { [void]$sb.Append(",") }
    if (($t % 4) -eq 3) { [void]$sb.AppendLine() } else { [void]$sb.Append(" ") }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# OR-planed 1bpp pattern (TMS9918 silhouette)
[void]$sb.AppendLine("static const unsigned char ff1_town_pattern[FF1_TOWN_TILE_COUNT * 8] = {")
for ($t = 0; $t -lt 128; $t++) {
    [void]$sb.Append("    ")
    for ($i = 0; $i -lt 8; $i++) {
        [void]$sb.Append(("0x{0:X2}" -f $chr1bpp[$t * 8 + $i]))
        if (-not ($t -eq 127 -and $i -eq 7)) { [void]$sb.Append(",") }
    }
    [void]$sb.AppendLine(("  // tile {0}" -f $t))
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif")

$outDir = Split-Path $OutHdr -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllText($OutHdr, $sb.ToString())
Write-Host ("Wrote {0} ({1} bytes)" -f $OutHdr, (Get-Item $OutHdr).Length)
