# extract_battle_sprites.ps1 - Estrae i 6 battle sprite + cursor "manina" da FF1 NES.
#
# Source: bank_09.bin (build via ca65/ld65 nel disasm Disch).
#   - lut_BatSprCHR @ $9000 (offset $1000 nel bank): 6 classi x 2 rows = 12 rows = $C00 byte
#     Layout per classe: 32 tile in sequenza, prime 6 = "standing" stance (UL UR ML MR DL DR)
#     Stride classe: $200 byte (2 rows = 32 tile da 16 byte)
#   - lut_BatObjCHR + $700 @ $AF00 (offset $2F00 nel bank): 4 tile cursore (16x16 manina)
#
# Output: src/ff1_battle_sprites.h con
#   - ff1_class_sprite[6][6][8]            = 6 classi x 6 tile x 8 byte TMS9918 pattern (OR-plane)
#   - ff1_cursor_sprite[4][8]              = 4 tile (TL TR DL DR) per la manina
#   - ff1_class_walk_legs[6][2][8]         = WALK pose alt legs (DL/DR alternativi)
#   - ff1_class_sprite_color[6][6][8]      = 8 color byte per tile (per-row dominant) -- slice30
#   - ff1_class_walk_legs_color[6][2][8]   = 8 color byte per walk leg tile               -- slice30
#   - ff1_class_accent[6][6][8]            = 1bpp accent pattern per tile (NES color = accent_value)  -- slice31
#   - ff1_class_accent_color[6]            = TMS fg color per classe accent                            -- slice31
#
# Conversione NES 2bpp -> TMS9918 1bpp: "OR planes" come asset_pipeline.md.
#
# Per-row dominant: per ogni riga della tile, conta i pixel non-bg e scegli il
# NES color value dominante (1, 2, 3). Mappa al TMS9918 fg via sub-pal della classe.
# Sub-pal 0 (TH/BB/BM): $0F $28 $18 $21 = black, skin, dark_olive, light_blue
# Sub-pal 1 (FT/RM/WM): $0F $16 $30 $36 = black, red, white, pink
#
# Accent layer: per classe scegliamo il NES value (1, 2 o 3) meno frequente fra
# tile + non-bg = il colore dei dettagli (cap/feather, sash, ecc). Output OAM
# 1bpp pattern (16 byte per tile, top half pattern + bottom half pattern -> 2 OAM
# tile da 8x8 ciascuno per classe top-half).

# Emette la forma PIATTA + gated che il resto del progetto usa (vedi la nota in
# fondo, dove si scrive l'header). Fino a slice78 l'header veniva corretto a
# mano dopo ogni esecuzione e lo script aveva una guardia per non
# sovrascriverlo; ora non serve piu'.

param(
    [string]$bankPath = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_09.bin",
    [string]$outFile  = "$PSScriptRoot\..\src\ff1_battle_sprites.h"
)

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $bankPath))
Write-Host "Loaded bank_09.bin: $($bytes.Length) bytes"

$CLASS_BASE   = 0x1000   # $9000 - $8000
$CLASS_STRIDE = 0x200    # 32 tile per classe
$CURSOR_OFF   = 0x2F00   # tile $F0 nel right pattern table
$N_CLASSES    = 6
$N_TILES_STAND = 6        # UL UR ML MR DL DR (tiles 0-5 per classe)
# WALK pose share UL/UR/ML/MR (tiles 0-3) con STAND, ma usa walking legs (tiles 6,7)
# Da pose TSA bank_0C.asm:2855: WALK = $00 $02 $06 -> tiles {0,1, 2,3, 6,7}
$N_TILES_WALK_LEGS = 2    # solo tiles 6,7 sono diversi (walking DL, DR)

$classNames = @("FT", "TH", "BB", "RM", "WM", "BM")

function Convert-NesTileToTms($srcBytes, $offset) {
    # NES tile = 16 byte: byte 0-7 = low plane, byte 8-15 = high plane.
    # OR planes -> 8 byte pattern silhouette.
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$offset + $r]
        $hi = $srcBytes[$offset + 8 + $r]
        $out[$r] = ($lo -bor $hi) -band 0xFF
    }
    return $out
}

# Sub-palette battle FF1 (decoded from bank_0F.asm:10347)
# Class -> sub-pal: lutClassBatSprPalette (FT TH BB RM WM BM = 1 0 0 1 1 0)
$NES_SUBPAL = @(
    @(0x0F, 0x28, 0x18, 0x21),    # sub-pal 0 (TH BB BM)
    @(0x0F, 0x16, 0x30, 0x36)     # sub-pal 1 (FT RM WM)
)
$CLASS_SUBPAL = @(1, 0, 0, 1, 1, 0)   # FT TH BB RM WM BM
$TMS_BLACK = 1

# Sub-pal aware mapping: per FT/RM/WM (sub-pal 1) il value=3 ($36) e' skin tone
# (fronte/mani esposte). Forziamo TMS 11 (light_yellow, peach-like) per distinguerlo
# dal dark_red della tunica. Le altre classi usano Map-NESToTMS standard.
function Map-NESToTMSContext([byte]$nes, [int]$subpalIdx, [int]$valueIdx) {
    if ($subpalIdx -eq 1 -and $valueIdx -eq 3) {
        # NES $36 in sub-pal 1 = skin tone -> light_yellow (peach), not light_red
        return 11
    }
    return Map-NESToTMS $nes
}

# NES master color $XY -> TMS9918 fg index (consistent con extract_battle_palettes.ps1)
function Map-NESToTMS([byte]$nes) {
    $h = $nes -shr 4
    $l = $nes -band 0x0F
    if ($l -eq 0x0F -or $l -eq 0x0E -or $l -eq 0x0D) { return 1 }
    if ($l -eq 0) {
        switch ($h) {
            0 { return 14 }
            1 { return 14 }
            2 { return 14 }
            3 { return 15 }
            default { return 14 }
        }
    }
    $isDark = ($h -le 1)
    switch ($l) {
        1  { if ($isDark) { return 4  } else { return 5  } }
        2  { if ($isDark) { return 4  } else { return 5  } }
        3  { return 13 }
        4  { return 13 }
        5  { if ($isDark) { return 6  } else { return 9  } }
        6  { if ($isDark) { return 6  } else { return 9  } }
        7  { if ($isDark) { return 8  } else { return 9  } }
        8  { if ($isDark) { return 10 } else { return 11 } }
        9  { if ($isDark) { return 10 } else { return 11 } }
        10 { if ($isDark) { return 12 } else { return 3  } }
        11 { if ($isDark) { return 12 } else { return 3  } }
        12 { return 7 }
        default { return 1 }
    }
}

# Decoda 8x8 pixel grid (valori 0-3) da una NES tile (16 byte, planar 2bpp).
function Decode-NesTilePixels($srcBytes, $offset) {
    $px = New-Object 'int[,]' 8, 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$offset + $r]
        $hi = $srcBytes[$offset + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $bL = ($lo -shr $bit) -band 1
            $bH = ($hi -shr $bit) -band 1
            $px[$r, $c] = ($bH -shl 1) -bor $bL
        }
    }
    return ,$px
}

# Per-row dominant: 8 byte color (uno per riga). Riga vuota -> tile-level fallback.
function Get-PerRowColors($srcBytes, $offset, $subpalIdx) {
    $px = Decode-NesTilePixels $srcBytes $offset
    # Tile-level dominant (fallback per righe vuote)
    $tileCounts = @(0, 0, 0)
    for ($r = 0; $r -lt 8; $r++) {
        for ($c = 0; $c -lt 8; $c++) {
            $v = $px[$r, $c]
            if ($v -gt 0) { $tileCounts[$v - 1]++ }
        }
    }
    $tileMaxIdx = 0
    if ($tileCounts[1] -gt $tileCounts[$tileMaxIdx]) { $tileMaxIdx = 1 }
    if ($tileCounts[2] -gt $tileCounts[$tileMaxIdx]) { $tileMaxIdx = 2 }
    $hasTileColor = ($tileCounts[$tileMaxIdx] -gt 0)
    if ($hasTileColor) {
        $defValueIdx = $tileMaxIdx + 1
        $defNes = $NES_SUBPAL[$subpalIdx][$defValueIdx]
        $defFg = Map-NESToTMSContext $defNes $subpalIdx $defValueIdx
        $defByte = (([byte]$defFg) -shl 4) -bor $TMS_BLACK
    } else {
        $defByte = (15 -shl 4) -bor $TMS_BLACK   # white on black, fallback per tile vuote
    }

    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $rowCounts = @(0, 0, 0)
        for ($c = 0; $c -lt 8; $c++) {
            $v = $px[$r, $c]
            if ($v -gt 0) { $rowCounts[$v - 1]++ }
        }
        $rowMaxIdx = 0
        if ($rowCounts[1] -gt $rowCounts[$rowMaxIdx]) { $rowMaxIdx = 1 }
        if ($rowCounts[2] -gt $rowCounts[$rowMaxIdx]) { $rowMaxIdx = 2 }
        if ($rowCounts[$rowMaxIdx] -gt 0) {
            $valueIdx = $rowMaxIdx + 1
            $rNes = $NES_SUBPAL[$subpalIdx][$valueIdx]
            $rFg = Map-NESToTMSContext $rNes $subpalIdx $valueIdx
            $out[$r] = (([byte]$rFg) -shl 4) -bor $TMS_BLACK
        } else {
            $out[$r] = $defByte
        }
    }
    return $out
}

# Per-class accent value: NES value (1, 2 o 3) MENO frequente fra le 8 tile (6 stand + 2 walk).
# Idea: il colore dominante = silhouette/body (gia' coperto da per-row dominant), il colore
# meno frequente = dettagli accent (piuma FT, fascia BB, cappuccio mage, ecc).
function Get-AccentValueForClass($srcBytes, $classOff) {
    $totalCounts = @(0, 0, 0)
    # Conta su tutte e 8 le tile (stand 0-5 + walk 6-7)
    $tileIdxs = @(0, 1, 2, 3, 4, 5, 6, 7)
    foreach ($t in $tileIdxs) {
        $px = Decode-NesTilePixels $srcBytes ($classOff + $t * 16)
        for ($r = 0; $r -lt 8; $r++) {
            for ($c = 0; $c -lt 8; $c++) {
                $v = $px[$r, $c]
                if ($v -gt 0) { $totalCounts[$v - 1]++ }
            }
        }
    }
    # Trova min non-zero count
    $minIdx = -1
    $minVal = [int]::MaxValue
    for ($i = 0; $i -lt 3; $i++) {
        if ($totalCounts[$i] -gt 0 -and $totalCounts[$i] -lt $minVal) {
            $minVal = $totalCounts[$i]
            $minIdx = $i
        }
    }
    if ($minIdx -lt 0) { return 1 }   # fallback safe
    return ($minIdx + 1)   # NES value 1..3
}

# 1bpp accent pattern: bit set se pixel value == accent_value (NES 1..3).
function Get-AccentPattern($srcBytes, $offset, $accentValue) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $row = 0
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $lo = $srcBytes[$offset + $r]
            $hi = $srcBytes[$offset + 8 + $r]
            $bL = ($lo -shr $bit) -band 1
            $bH = ($hi -shr $bit) -band 1
            $v = ($bH -shl 1) -bor $bL
            if ($v -eq $accentValue) { $row = $row -bor (1 -shl $bit) }
        }
        $out[$r] = [byte]($row -band 0xFF)
    }
    return $out
}

# ============================================================================
# EMISSIONE -- forma PIATTA e dietro FF1_BATTLE_SPRITES_DEFINE_DATA.
#
# Fino a slice78 questo script emetteva sette array MULTIDIMENSIONALI e
# l'header veniva poi corretto a mano (appiattito, messo dietro la macro, e
# privato di cursore e gambe in camminata, che nessuno usa). Ora emette
# direttamente quella forma: rigenerare non perde piu' niente, e la ROM esce
# identica byte per byte.
# ============================================================================
function Format-Row8($arr) { return '  ' + (($arr | ForEach-Object { '0x{0:X2}' -f $_ }) -join ',') + ',' }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATED da bank_09.bin (FF1 disasm Disch)")
[void]$sb.AppendLine("// Battle sprites 16x24 (2x3 tile) per le 6 classi")
[void]$sb.AppendLine("// Conversione NES 2bpp -> TMS9918 1bpp via OR planes")
[void]$sb.AppendLine("// Layout per classe: tile 0-5 = UL UR ML MR DL DR (standing stance)")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// NB: array APPIATTITI a 1-D [288] (6 classi * 6 tile * 8 byte). sccz80 mette")
[void]$sb.AppendLine("// i const MULTIDIMENSIONALI in sezione DATA (RAM-resident, copiata da crt0_init).")
[void]$sb.AppendLine("// In un MegaCart bank blob (sgm_bank_crt0) crt0_init NON gira -> DATA mai")
[void]$sb.AppendLine("// copiata -> garbage. Gli array 1-D restano in rodata (= ROM del banco).")
[void]$sb.AppendLine("// Accesso flat: indice = (classe*6 + tile)*8 + byte (gia' usato dagli helper).")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_BATTLE_SPRITES_H")
[void]$sb.AppendLine("#define FF1_BATTLE_SPRITES_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifdef FF1_BATTLE_SPRITES_DEFINE_DATA")
[void]$sb.AppendLine("")

[void]$sb.AppendLine("static const unsigned char ff1_class_sprite[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    [void]$sb.AppendLine("  // [$c] $($classNames[$c])")
    for ($t = 0; $t -lt $N_TILES_STAND; $t++) {
        [void]$sb.AppendLine((Format-Row8 (Convert-NesTileToTms $bytes ($classOff + $t * 16))))
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# Per-row dominant color (slice30): 8 color byte per tile (uno per riga).
# Ogni byte = (tms_fg << 4) | TMS_BLACK.
[void]$sb.AppendLine("static const unsigned char ff1_class_sprite_color[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    [void]$sb.AppendLine("  // [$c] $($classNames[$c])")
    for ($t = 0; $t -lt $N_TILES_STAND; $t++) {
        [void]$sb.AppendLine((Format-Row8 (Get-PerRowColors $bytes ($classOff + $t * 16) $CLASS_SUBPAL[$c])))
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# OAM accent layer (slice31): 1bpp pattern per tile dove pixel == accent NES
# value (NES color 1, 2 o 3, scelto per classe come "min frequency" non-bg).
$accentValues = New-Object int[] $N_CLASSES
$accentColors = New-Object byte[] $N_CLASSES
[void]$sb.AppendLine("static const unsigned char ff1_class_accent[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    $subpal = $CLASS_SUBPAL[$c]
    # Class-specific accent override (per richiesta utente sessione 7).
    # FT: forza accent=3 (skin) invece di auto-picked value 2 (sword tip white).
    $classAccentOverride = @{ 0 = 3 }   # FT -> skin
    if ($classAccentOverride.ContainsKey($c)) {
        $accVal = $classAccentOverride[$c]
    } else {
        $accVal = Get-AccentValueForClass $bytes $classOff
    }
    $accentValues[$c] = $accVal
    $accNes = $NES_SUBPAL[$subpal][$accVal]
    $accentColors[$c] = [byte](Map-NESToTMSContext $accNes $subpal $accVal)
    [void]$sb.AppendLine("  // [$c] $($classNames[$c])")
    for ($t = 0; $t -lt $N_TILES_STAND; $t++) {
        [void]$sb.AppendLine((Format-Row8 (Get-AccentPattern $bytes ($classOff + $t * 16) $accVal)))
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

[void]$sb.AppendLine("static const unsigned char ff1_class_accent_color[6] = {")
$accLine = "    "
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $accLine += "{0,2}" -f $accentColors[$c]
    if ($c -lt ($N_CLASSES - 1)) { $accLine += ", " }
}
[void]$sb.AppendLine("$accLine    // FT TH BB RM WM BM")
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_BATTLE_SPRITES_DEFINE_DATA")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_BATTLE_SPRITES_H")

[System.IO.File]::WriteAllText($outFile, $sb.ToString())
Write-Host "Written: $outFile"
Write-Host "Accent values per class:"
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    Write-Host ("  {0}: NES value={1} -> TMS fg={2}" -f $classNames[$c], $accentValues[$c], $accentColors[$c])
}
