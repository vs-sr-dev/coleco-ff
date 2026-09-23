# extract_mapman.ps1 v2 - Estrae i 6 mapman field sprite + accent layer + colors.
#
# Source: bank_02.dat. Ogni classe ha 16 tile NES (8x8 2bpp = 256 byte) a:
#   FT $1000, TH $1100, BB $1200, RM $1300, WM $1400, BM $1500
#
# Frame composition via lut_PlayerMapmanSprTbl (bank_0F $E427): per ogni frame
# 4 tile (UL DL UR DR) con attr byte (bit $40 = h-flip).
# 8 frame totali: 4 direzioni x 2 frame walk.
#
# Output: src/ff1_mapman_all.h con
#   ff1_mapman_frames[6][8][32]        # silhouette (OR-plane 1bpp), v1
#   ff1_mapman_accent[6][8][32]        # accent pattern (1bpp where pixel == accent), v2
#   ff1_mapman_main_color[6]           # TMS fg dominant color, v2
#   ff1_mapman_accent_color[6]         # TMS fg accent color, v2
#
# Indici direzione: 0=DOWN, 1=UP, 2=LEFT, 3=RIGHT (parity slice08 ff1_fighter.h)
# Indice frame: dir*2 + (0 idle/1 step)
# Layout TMS9918 16x16: TL(8) + BL(8) + TR(8) + BR(8) = 32 byte
#
# Conversione NES 2bpp -> TMS9918 1bpp via OR planes (silhouette) o accent_value
# match (accent), h-flip se attr $40.

param(
    [string]$bankPath = "..\FF1Disassembly-master\Final Fantasy Disassembly\bank_02.dat",
    [string]$outPath  = "..\src\ff1_mapman_all.h",
    [switch]$IncludeAlt = $false   # se true, emette ff1_mapman_accent_alt (4608 byte) per slice34c debug
)

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $bankPath))
Write-Host "Loaded bank_02.dat: $($bytes.Length) bytes"

$classNames = @("FT","TH","BB","RM","WM","BM")
$classBase = @(0x1000, 0x1100, 0x1200, 0x1300, 0x1400, 0x1500)

# lut_PlayerMapmanSprTbl. Ogni frame = 4 quadranti (tile, attr) ordine UL DL UR DR.
# Indici qui sotto seguono ordine della LUT NES: R0 R1 L0 L1 U0 U1 D0 D1.
$lutFrames = @(
    @(@(0x09,0x40), @(0x0B,0x41), @(0x08,0x40), @(0x0A,0x41)), # 0 R0
    @(@(0x0D,0x40), @(0x0F,0x41), @(0x0C,0x40), @(0x0E,0x41)), # 1 R1
    @(@(0x08,0x00), @(0x0A,0x01), @(0x09,0x00), @(0x0B,0x01)), # 2 L0
    @(@(0x0C,0x00), @(0x0E,0x01), @(0x0D,0x00), @(0x0F,0x01)), # 3 L1
    @(@(0x04,0x00), @(0x06,0x01), @(0x05,0x00), @(0x07,0x01)), # 4 U0
    @(@(0x04,0x00), @(0x07,0x41), @(0x05,0x00), @(0x06,0x41)), # 5 U1
    @(@(0x00,0x00), @(0x02,0x01), @(0x01,0x00), @(0x03,0x01)), # 6 D0
    @(@(0x00,0x00), @(0x03,0x41), @(0x01,0x00), @(0x02,0x41))  # 7 D1
)

# Riordino in DOWN, UP, LEFT, RIGHT (slice08 convention)
$desiredOrder = @(
    @{ label="DOWN_F0";  idx=6 },
    @{ label="DOWN_F1";  idx=7 },
    @{ label="UP_F0";    idx=4 },
    @{ label="UP_F1";    idx=5 },
    @{ label="LEFT_F0";  idx=2 },
    @{ label="LEFT_F1";  idx=3 },
    @{ label="RIGHT_F0"; idx=0 },
    @{ label="RIGHT_F1"; idx=1 }
)

function Reverse-Bits([byte]$b) {
    $r = 0
    for ($i = 0; $i -lt 8; $i++) {
        if (($b -shr $i) -band 1) { $r = $r -bor (1 -shl (7 - $i)) }
    }
    return [byte]($r -band 0xFF)
}

function Convert-NesTile($srcBytes, [int]$tileOff, [bool]$hflip) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$tileOff + $r]
        $hi = $srcBytes[$tileOff + 8 + $r]
        $or = ($lo -bor $hi) -band 0xFF
        if ($hflip) { $or = Reverse-Bits ([byte]$or) }
        $out[$r] = [byte]$or
    }
    return $out
}

# v2: estrae 1bpp pattern per accent (bit set se pixel NES == accent_value).
function Convert-NesTileAccent($srcBytes, [int]$tileOff, [bool]$hflip, [int]$accentValue) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$tileOff + $r]
        $hi = $srcBytes[$tileOff + 8 + $r]
        $accent = 0
        for ($bit = 0; $bit -lt 8; $bit++) {
            $loBit = ($lo -shr (7 - $bit)) -band 1
            $hiBit = ($hi -shr (7 - $bit)) -band 1
            $val = ($hiBit -shl 1) -bor $loBit
            if ($val -eq $accentValue) {
                $accent = $accent -bor (1 -shl (7 - $bit))
            }
        }
        if ($hflip) { $accent = Reverse-Bits ([byte]$accent) }
        $out[$r] = [byte]$accent
    }
    return $out
}

# v2: conta frequency dei 4 valori NES per scegliere accent_value automaticamente.
function Get-PixelHistogram($srcBytes, [int]$classBaseOff) {
    $hist = @(0, 0, 0, 0)
    # Tutti i 16 tile della classe (256 byte = 16 tile x 16 byte/tile)
    for ($t = 0; $t -lt 16; $t++) {
        $tileOff = $classBaseOff + ($t * 16)
        for ($r = 0; $r -lt 8; $r++) {
            $lo = $srcBytes[$tileOff + $r]
            $hi = $srcBytes[$tileOff + 8 + $r]
            for ($bit = 0; $bit -lt 8; $bit++) {
                $loBit = ($lo -shr (7 - $bit)) -band 1
                $hiBit = ($hi -shr (7 - $bit)) -band 1
                $val = ($hiBit -shl 1) -bor $loBit
                $hist[$val]++
            }
        }
    }
    return $hist
}

# Build 32-byte TMS frame: TL BL TR BR a partire dalla LUT-slot UL DL UR DR
function Build-Frame($srcBytes, [int]$classBaseOff, $lutSlot) {
    $out = New-Object byte[] 32
    # lutSlot[0]=UL -> TL, [1]=DL -> BL, [2]=UR -> TR, [3]=DR -> BR (stesso ordine!)
    for ($q = 0; $q -lt 4; $q++) {
        $tileNum = [int]$lutSlot[$q][0]
        $attr    = [int]$lutSlot[$q][1]
        $hflip   = ($attr -band 0x40) -ne 0
        $tileOff = $classBaseOff + ($tileNum * 16)
        $tms = Convert-NesTile $srcBytes $tileOff $hflip
        for ($i = 0; $i -lt 8; $i++) { $out[$q * 8 + $i] = $tms[$i] }
    }
    return $out
}

# v2: come Build-Frame ma applica accent extraction (1bpp solo dove pixel == accentValue).
function Build-AccentFrame($srcBytes, [int]$classBaseOff, $lutSlot, [int]$accentValue) {
    $out = New-Object byte[] 32
    for ($q = 0; $q -lt 4; $q++) {
        $tileNum = [int]$lutSlot[$q][0]
        $attr    = [int]$lutSlot[$q][1]
        $hflip   = ($attr -band 0x40) -ne 0
        $tileOff = $classBaseOff + ($tileNum * 16)
        $tms = Convert-NesTileAccent $srcBytes $tileOff $hflip $accentValue
        for ($i = 0; $i -lt 8; $i++) { $out[$q * 8 + $i] = $tms[$i] }
    }
    return $out
}

# v2 default values - color/accent polish in sospeso (slice34c iter 2026-05-10
# inconcluded per disallineamento numerazione av nelle istruzioni). Re-iterare in slice34c
# rispettando av visualizzato (1->idx 0, ecc) per locking definitivo.
$classAccentValue = @(
    3,  # FT - skin (auto-min frequency)
    2,  # TH - cap detail
    3,  # BB - skin
    3,  # RM - skin
    3,  # WM - skin
    2   # BM - olive body detail
)
$classMainColor = @(
    15,  # FT - WHITE
    3,   # TH - LIGHT_GREEN
    11,  # BB - LIGHT_YELLOW
    9,   # RM - LIGHT_RED
    15,  # WM - WHITE
    5    # BM - LIGHT_BLUE
)
$classAccentColor = @(
    11,  # FT - light_yellow (skin)
    5,   # TH - light_blue (cap)
    11,  # BB - skin (NB: same as main -> mono bug, polish TODO)
    11,  # RM - skin
    11,  # WM - skin
    10   # BM - dark_yellow (olive)
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATED da bank_02.dat (FF1 disasm Disch)")
[void]$sb.AppendLine("// 6 mapman field sprite (overworld walk cycle) per le 6 classi FF1.")
[void]$sb.AppendLine("// Layout 16x16: TL(8) + BL(8) + TR(8) + BR(8) = 32 byte per frame")
[void]$sb.AppendLine("// Indice direzione: 0=DOWN, 1=UP, 2=LEFT, 3=RIGHT")
[void]$sb.AppendLine("// Indice frame: dir*2 + (0=idle/1=step)")
[void]$sb.AppendLine("// Indice classe: 0=FT 1=TH 2=BB 3=RM 4=WM 5=BM")
[void]$sb.AppendLine("// H-flip applicato manualmente (TMS9918 mode 2 non supporta hw flip su sprite)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_MAPMAN_ALL_H")
[void]$sb.AppendLine("#define FF1_MAPMAN_ALL_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("static const unsigned char ff1_mapman_frames[6][8][32] = {")

for ($c = 0; $c -lt $classNames.Length; $c++) {
    [void]$sb.AppendLine("  // ====== Class [$c] $($classNames[$c]) (base 0x$('{0:X4}' -f $classBase[$c])) ======")
    [void]$sb.AppendLine("  {")
    for ($f = 0; $f -lt $desiredOrder.Length; $f++) {
        $slot = $lutFrames[$desiredOrder[$f].idx]
        $frame = Build-Frame $bytes $classBase[$c] $slot
        [void]$sb.AppendLine("    // [$f] $($desiredOrder[$f].label)")
        [void]$sb.AppendLine("    {")
        # Print 4 quadrants 8 byte ciascuno (TL BL TR BR)
        $qLabels = @("TL","BL","TR","BR")
        for ($q = 0; $q -lt 4; $q++) {
            $hex = ""
            for ($i = 0; $i -lt 8; $i++) {
                $hex += ("0x{0:X2}" -f $frame[$q * 8 + $i])
                if ($i -lt 7) { $hex += ", " }
            }
            [void]$sb.AppendLine("      $hex, // $($qLabels[$q])")
        }
        [void]$sb.AppendLine("    },")
    }
    [void]$sb.AppendLine("  },")
}

[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# v2: ff1_mapman_accent[6][8][32] - default best accent_value per class (slice34b)
[void]$sb.AppendLine("// v2: accent pattern (1bpp set dove pixel NES == per-class accent_value)")
[void]$sb.AppendLine("static const unsigned char ff1_mapman_accent[6][8][32] = {")
for ($c = 0; $c -lt $classNames.Length; $c++) {
    $accent = [int]$classAccentValue[$c]
    [void]$sb.AppendLine("  // ====== Class [$c] $($classNames[$c]) accent_value=$accent ======")
    [void]$sb.AppendLine("  {")
    for ($f = 0; $f -lt $desiredOrder.Length; $f++) {
        $slot = $lutFrames[$desiredOrder[$f].idx]
        $frame = Build-AccentFrame $bytes $classBase[$c] $slot $accent
        [void]$sb.AppendLine("    // [$f] $($desiredOrder[$f].label)")
        [void]$sb.AppendLine("    {")
        $qLabels = @("TL","BL","TR","BR")
        for ($q = 0; $q -lt 4; $q++) {
            $hex = ""
            for ($i = 0; $i -lt 8; $i++) {
                $hex += ("0x{0:X2}" -f $frame[$q * 8 + $i])
                if ($i -lt 7) { $hex += ", " }
            }
            [void]$sb.AppendLine("      $hex, // $($qLabels[$q])")
        }
        [void]$sb.AppendLine("    },")
    }
    [void]$sb.AppendLine("  },")
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# v3: ff1_mapman_accent_alt[18][8][32] - flattened, OPTIONAL (param -IncludeAlt)
if ($IncludeAlt) {
    [void]$sb.AppendLine("// v3: accent_alt flattened a 3D [18][8][32] per evitare 4D sccz80 quirk.")
    [void]$sb.AppendLine("// Indice = cls*3 + (accent_value-1). Es. FT av=3 -> idx 2, TH av=2 -> idx 4.")
    [void]$sb.AppendLine("// EMESSO solo con -IncludeAlt (per slice34c debug). 4608 byte DATA.")
    [void]$sb.AppendLine("static const unsigned char ff1_mapman_accent_alt[18][8][32] = {")
    for ($c = 0; $c -lt $classNames.Length; $c++) {
        for ($av = 1; $av -le 3; $av++) {
            $idx = $c * 3 + ($av - 1)
            [void]$sb.AppendLine("  // [$idx] Class $($classNames[$c]) accent_value=$av")
            [void]$sb.AppendLine("  {")
            for ($f = 0; $f -lt $desiredOrder.Length; $f++) {
                $slot = $lutFrames[$desiredOrder[$f].idx]
                $frame = Build-AccentFrame $bytes $classBase[$c] $slot $av
                [void]$sb.AppendLine("    // [$f] $($desiredOrder[$f].label)")
                [void]$sb.AppendLine("    {")
                $qLabels = @("TL","BL","TR","BR")
                for ($q = 0; $q -lt 4; $q++) {
                    $hex = ""
                    for ($i = 0; $i -lt 8; $i++) {
                        $hex += ("0x{0:X2}" -f $frame[$q * 8 + $i])
                        if ($i -lt 7) { $hex += ", " }
                    }
                    [void]$sb.AppendLine("      $hex, // $($qLabels[$q])")
                }
                [void]$sb.AppendLine("    },")
            }
            [void]$sb.AppendLine("  },")
        }
    }
    [void]$sb.AppendLine("};")
    [void]$sb.AppendLine("")
}

# v2: TMS fg colors (main + accent)
[void]$sb.AppendLine("// v2: TMS9918 fg color per classe")
[void]$sb.AppendLine("static const unsigned char ff1_mapman_main_color[6] = {")
$mainHex = ($classMainColor | ForEach-Object { "$_" }) -join ", "
[void]$sb.AppendLine("    $mainHex   // FT TH BB RM WM BM")
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("static const unsigned char ff1_mapman_accent_color[6] = {")
$accHex = ($classAccentColor | ForEach-Object { "$_" }) -join ", "
[void]$sb.AppendLine("    $accHex   // FT TH BB RM WM BM")
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif")

[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $outPath), $sb.ToString())
Write-Host "Written: $outPath"
Write-Host "  ff1_mapman_frames:        6 x 8 x 32 = 1536 byte"
Write-Host "  ff1_mapman_accent:        6 x 8 x 32 = 1536 byte (v2)"
Write-Host "  ff1_mapman_main_color:    6 byte (v2)"
Write-Host "  ff1_mapman_accent_color:  6 byte (v2)"

# Diagnostic: dump pixel histograms per scegliere accent_value
Write-Host ""
Write-Host "Pixel value frequency per classe (per validare accent_value choice):"
for ($c = 0; $c -lt $classNames.Length; $c++) {
    $hist = Get-PixelHistogram $bytes $classBase[$c]
    $name = $classNames[$c]
    $av = $classAccentValue[$c]
    Write-Host ("  {0}: bg={1,5} v1={2,4} v2={3,4} v3={4,4}  accent_value={5}" -f $name, $hist[0], $hist[1], $hist[2], $hist[3], $av)
}
