# Extract FF1 lut_BattlePalettes (64 palette x 4 colors) e mappa a TMS9918 fg color.
#
# Per ogni palette NES, scegliamo "dominant TMS fg" guardando colore[2] della
# sub-palette (tipicamente il colore "secondary/body" che varia maggiormente fra
# palette swap). Color [0] e' sempre $0F (transparent), [1] spesso identico fra
# palette swap (outline color), [2] e' il vero discriminatore.

$pal_bin = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_8F20_battlepalettes.bin"
$out_header = "$PSScriptRoot\..\src\ff1_palettes.h"

# NES master palette $XY -> TMS9918 fg color index.
# Mapping da docs/colors_nes_to_tms.md, esteso a tutti i 64 colori NES.
# TMS9918 ink indexes:
#   0=transparent 1=black 2=med_green 3=lt_green 4=dk_blue 5=lt_blue
#   6=dk_red 7=cyan 8=med_red 9=lt_red 10=dk_yellow 11=lt_yellow
#   12=dk_green 13=magenta 14=gray 15=white
function Map-NESToTMS([byte]$nesColor) {
    $h = $nesColor -shr 4   # brightness (0-3, with 0/4 = darkest/illegal)
    $l = $nesColor -band 0x0F # hue (0=grey, 1-12=hues, 13-15=greys/black)

    # Greys/black handling (low nibble 0 or D-F)
    if ($l -eq 0x0F -or $l -eq 0x0E -or $l -eq 0x0D) { return 1 }  # black
    if ($l -eq 0) {
        switch ($h) {
            0 { return 14 }  # gray
            1 { return 14 }  # gray
            2 { return 14 }  # gray
            3 { return 15 }  # white
            default { return 14 }
        }
    }

    # Hue colors: pick TMS based on hue + brightness
    # h=0,1: dark; h=2: bright; h=3: brightest
    $isDark = ($h -le 1)
    switch ($l) {
        1  { if ($isDark) { return 4  } else { return 5  } }  # blue
        2  { if ($isDark) { return 4  } else { return 5  } }  # blue
        3  { return 13 }                                       # purple -> magenta
        4  { return 13 }                                       # magenta
        5  { if ($isDark) { return 6  } else { return 9  } }  # red
        6  { if ($isDark) { return 6  } else { return 9  } }  # red
        7  { if ($isDark) { return 8  } else { return 9  } }  # orange -> red
        8  { if ($isDark) { return 10 } else { return 11 } }  # brown -> yellow
        9  { if ($isDark) { return 10 } else { return 11 } }  # yellow-green
        10 { if ($isDark) { return 12 } else { return 3  } }  # green
        11 { if ($isDark) { return 12 } else { return 3  } }  # green-cyan
        12 { return 7 }                                        # cyan
        default { return 1 }
    }
}

$bytes = [System.IO.File]::ReadAllBytes($pal_bin)
$nPalettes = $bytes.Length / 4

# Build per-palette dominant TMS fg.
# Strategy: usa colore [2] della sub-palette come discriminatore.
# Fallback se [2] e' nero/grigio: prova [3], poi [1].
$palette_fg = @()
for ($p = 0; $p -lt $nPalettes; $p++) {
    $c1 = $bytes[$p*4 + 1]
    $c2 = $bytes[$p*4 + 2]
    $c3 = $bytes[$p*4 + 3]
    $tms = Map-NESToTMS $c2
    if ($tms -le 1 -or $tms -eq 14) {
        # too neutral, try c3
        $tmsAlt = Map-NESToTMS $c3
        if ($tmsAlt -gt 1 -and $tmsAlt -ne 14) { $tms = $tmsAlt }
        else {
            $tmsAlt = Map-NESToTMS $c1
            if ($tmsAlt -gt 1 -and $tmsAlt -ne 14) { $tms = $tmsAlt }
        }
    }
    $palette_fg += $tms
}

# Generate header
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("// ff1_palettes.h - Generated from FF1 NES disasm")
[void]$sb.AppendLine("// 64 battle palettes from bin/0C_8F20_battlepalettes.bin.")
[void]$sb.AppendLine("// Each palette: 4 NES master colors. Color [0] = transparent always.")
[void]$sb.AppendLine("// Per-palette dominant TMS9918 fg (derived from color [2], with fallbacks).")
[void]$sb.AppendLine()
[void]$sb.AppendLine("#ifndef FF1_PALETTES_H")
[void]$sb.AppendLine("#define FF1_PALETTES_H")
[void]$sb.AppendLine()
[void]$sb.AppendLine("#define FF1_BATTLE_PALETTE_COUNT $nPalettes")
[void]$sb.AppendLine()

# Raw NES palette data (for future per-row dominant or OAM accent)
[void]$sb.AppendLine("// Raw NES palette data: 4 byte per palette (NES color indices).")
[void]$sb.AppendLine("static const unsigned char ff1_battle_palettes_nes[FF1_BATTLE_PALETTE_COUNT][4] = {")
for ($p = 0; $p -lt $nPalettes; $p++) {
    $line = "    { "
    for ($c = 0; $c -lt 4; $c++) {
        $line += "0x{0:X2}" -f $bytes[$p*4 + $c]
        if ($c -lt 3) { $line += ", " }
    }
    $line += " },  // pal $p"
    [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine()

# TMS fg dominant per palette
[void]$sb.AppendLine("// TMS9918 dominant fg color per palette (used for OR-plane silhouette).")
[void]$sb.AppendLine("// Mapping: pick palette color [2] -> TMS fg via NES master palette table.")
[void]$sb.AppendLine("static const unsigned char ff1_battle_palette_to_tms_fg[FF1_BATTLE_PALETTE_COUNT] = {")
$line = "    "
for ($p = 0; $p -lt $nPalettes; $p++) {
    $line += "{0,2}" -f $palette_fg[$p]
    if ($p -lt ($nPalettes - 1)) { $line += ", " }
    if ((($p + 1) % 8) -eq 0) {
        $line += "  // pal " + (($p - 7)).ToString("D2") + "-" + $p.ToString("D2")
        [void]$sb.AppendLine($line)
        $line = "    "
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine()

[void]$sb.AppendLine("#endif  // FF1_PALETTES_H")

[System.IO.File]::WriteAllText($out_header, $sb.ToString())
"Written: $out_header"
"First 16 palettes -> TMS fg:"
for ($p = 0; $p -lt 16; $p++) {
    "  pal {0:D2}: NES {1:X2} {2:X2} {3:X2} {4:X2}  ->  TMS fg {5}" -f $p, $bytes[$p*4], $bytes[$p*4+1], $bytes[$p*4+2], $bytes[$p*4+3], $palette_fg[$p]
}