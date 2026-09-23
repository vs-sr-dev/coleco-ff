# extract_cheer_sprites.ps1 -- estrae la posa di ESULTANZA dei 4 personaggi.
#
# FONTE (bank_0C.asm:2852, lut_CharacterPoseTSA):
#     .BYTE $00, $02, $04, $00      ; 00 = standing pose
#     .BYTE $00, $02, $06, $00      ; 04 = walking pose
#     .BYTE $0E, $10, $12, $00      ; 10 = cheering pose   <-- questa
# Ogni byte e' la tile SINISTRA di una riga 16x8; la destra e' quella dopo.
# Quindi la posa di esultanza usa le tile NES $0E $0F / $10 $11 / $12 $13,
# cioe' UL UR ML MR DL DR come lo standing, ma da un'altra zona del CHR.
#
# E la fanfara e' confermata dallo stesso disassembly (bank_0C.asm:2436,
# PlayFanfareAndCheer): `LDA #$53` -> sng53, che sta gia' nel banco 10.
#
# PERCHE' UNO SCRIPT SEPARATO E NON UN'AGGIUNTA A extract_battle_sprites.ps1
# Quello emette ancora array MULTIDIMENSIONALI, che sccz80 piazza in sezione
# DATA -- mai inizializzata in un banco MegaCart. src/ff1_battle_sprites.h e'
# stato corretto a mano dopo, appiattito a 1-D e messo dietro una macro di
# gate. Rieseguire quello script oggi riporterebbe indietro la correzione e
# darebbe sprite di spazzatura. Le funzioni di conversione qui sotto sono
# quindi COPIATE da li' invece che condivise: e' duplicazione consapevole,
# preferita a un dot-source che eseguirebbe anche la scrittura di quel file.
# (Vedi la guardia aggiunta in cima a extract_battle_sprites.ps1.)

param(
    [string]$bankPath = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_09.bin",
    [string]$outPath  = "$PSScriptRoot\..\src\ff1_cheer_sprites.h"
)

$ErrorActionPreference = 'Stop'

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $bankPath))
Write-Host "Caricato bank_09.bin: $($bytes.Length) byte"

$CLASS_BASE   = 0x1000   # $9000 - $8000
$CLASS_STRIDE = 0x200    # 32 tile per classe
$N_CLASSES    = 6
# Tile NES della posa di esultanza, nell'ordine UL UR ML MR DL DR.
$CHEER_TILES  = @(0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13)

$classNames = @("FT", "TH", "BB", "RM", "WM", "BM")

$NES_SUBPAL = @(
    @(0x0F, 0x28, 0x18, 0x21),    # sub-pal 0 (TH BB BM)
    @(0x0F, 0x16, 0x30, 0x36)     # sub-pal 1 (FT RM WM)
)
$CLASS_SUBPAL = @(1, 0, 0, 1, 1, 0)
$TMS_BLACK = 1

function Convert-NesTileToTms($srcBytes, $offset) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $out[$r] = ($srcBytes[$offset + $r] -bor $srcBytes[$offset + 8 + $r]) -band 0xFF
    }
    return $out
}

function Map-NESToTMS([byte]$nes) {
    $h = $nes -shr 4
    $l = $nes -band 0x0F
    if ($l -eq 0x0F -or $l -eq 0x0E -or $l -eq 0x0D) { return 1 }
    if ($l -eq 0) {
        switch ($h) { 0 { return 14 } 1 { return 14 } 2 { return 14 } 3 { return 15 } default { return 14 } }
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
function Map-NESToTMSContext([byte]$nes, [int]$subpalIdx, [int]$valueIdx) {
    if ($subpalIdx -eq 1 -and $valueIdx -eq 3) { return 11 }   # incarnato
    return Map-NESToTMS $nes
}

function Decode-NesTilePixels($srcBytes, $offset) {
    $px = New-Object 'int[,]' 8, 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $srcBytes[$offset + $r]; $hi = $srcBytes[$offset + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $px[$r, $c] = (((($hi -shr $bit) -band 1) -shl 1) -bor (($lo -shr $bit) -band 1))
        }
    }
    return ,$px
}

function Get-PerRowColors($srcBytes, $offset, $subpalIdx) {
    $px = Decode-NesTilePixels $srcBytes $offset
    $tileCounts = @(0, 0, 0)
    for ($r = 0; $r -lt 8; $r++) { for ($c = 0; $c -lt 8; $c++) {
        $v = $px[$r, $c]; if ($v -gt 0) { $tileCounts[$v - 1]++ } } }
    $tileMaxIdx = 0
    if ($tileCounts[1] -gt $tileCounts[$tileMaxIdx]) { $tileMaxIdx = 1 }
    if ($tileCounts[2] -gt $tileCounts[$tileMaxIdx]) { $tileMaxIdx = 2 }
    if ($tileCounts[$tileMaxIdx] -gt 0) {
        $defValueIdx = $tileMaxIdx + 1
        $defFg = Map-NESToTMSContext $NES_SUBPAL[$subpalIdx][$defValueIdx] $subpalIdx $defValueIdx
        $defByte = (([byte]$defFg) -shl 4) -bor $TMS_BLACK
    } else {
        $defByte = (15 -shl 4) -bor $TMS_BLACK
    }
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $rowCounts = @(0, 0, 0)
        for ($c = 0; $c -lt 8; $c++) { $v = $px[$r, $c]; if ($v -gt 0) { $rowCounts[$v - 1]++ } }
        $rowMaxIdx = 0
        if ($rowCounts[1] -gt $rowCounts[$rowMaxIdx]) { $rowMaxIdx = 1 }
        if ($rowCounts[2] -gt $rowCounts[$rowMaxIdx]) { $rowMaxIdx = 2 }
        if ($rowCounts[$rowMaxIdx] -gt 0) {
            $valueIdx = $rowMaxIdx + 1
            $rFg = Map-NESToTMSContext $NES_SUBPAL[$subpalIdx][$valueIdx] $subpalIdx $valueIdx
            $out[$r] = (([byte]$rFg) -shl 4) -bor $TMS_BLACK
        } else { $out[$r] = $defByte }
    }
    return $out
}

# STESSO valore di accento della posa in piedi: il colore OAM per classe e'
# gia' in ff1_class_accent_color e non va ricalcolato, quindi il pattern deve
# selezionare lo stesso valore NES o l'accento cambierebbe colore a meta'
# animazione. Conteggio sulle tile 0-7 come nell'estrattore originale, con lo
# stesso override per il FIGHTER (accento = incarnato, deciso in sessione 7).
function Get-AccentValueForClass($srcBytes, $classOff) {
    $totalCounts = @(0, 0, 0)
    foreach ($t in @(0,1,2,3,4,5,6,7)) {
        $px = Decode-NesTilePixels $srcBytes ($classOff + $t * 16)
        for ($r = 0; $r -lt 8; $r++) { for ($c = 0; $c -lt 8; $c++) {
            $v = $px[$r, $c]; if ($v -gt 0) { $totalCounts[$v - 1]++ } } }
    }
    $minIdx = -1; $minVal = [int]::MaxValue
    for ($i = 0; $i -lt 3; $i++) {
        if ($totalCounts[$i] -gt 0 -and $totalCounts[$i] -lt $minVal) { $minVal = $totalCounts[$i]; $minIdx = $i }
    }
    if ($minIdx -lt 0) { return 1 }
    return ($minIdx + 1)
}

function Get-AccentPattern($srcBytes, $offset, $accentValue) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $row = 0
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $v = (((($srcBytes[$offset + 8 + $r] -shr $bit) -band 1) -shl 1) -bor
                  (($srcBytes[$offset + $r] -shr $bit) -band 1))
            if ($v -eq $accentValue) { $row = $row -bor (1 -shl $bit) }
        }
        $out[$r] = [byte]($row -band 0xFF)
    }
    return $out
}

$labels = @("UL","UR","ML","MR","DL","DR")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATO da tools/extract_cheer_sprites.ps1 (bank_09.bin, disasm Disch)")
[void]$sb.AppendLine("// Posa di ESULTANZA (CHARPOSE_CHEER) dei 6 personaggi giocabili.")
[void]$sb.AppendLine("// TSA sorgente: lut_CharacterPoseTSA voce \$10 = \$0E \$10 \$12")
[void]$sb.AppendLine("//   -> tile NES \$0E \$0F / \$10 \$11 / \$12 \$13 = UL UR ML MR DL DR")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Array 1-D come in ff1_battle_sprites.h, e per la stessa ragione: sccz80")
[void]$sb.AppendLine("// mette i const MULTIDIMENSIONALI in sezione DATA, che in un banco MegaCart")
[void]$sb.AppendLine("// non viene mai inizializzata (crt0_init non gira) -> spazzatura.")
[void]$sb.AppendLine("// Accesso: indice = (classe*6 + tile)*8 + byte.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_CHEER_SPRITES_H")
[void]$sb.AppendLine("#define FF1_CHEER_SPRITES_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifdef FF1_CHEER_SPRITES_DEFINE_DATA")
[void]$sb.AppendLine("")

# --- pattern ---
[void]$sb.AppendLine("// Silhouette 1bpp (OR dei due piani NES): 6 classi x 6 tile x 8 byte")
[void]$sb.AppendLine("static const unsigned char ff1_class_cheer[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    [void]$sb.AppendLine("  // [$c] $($classNames[$c])")
    for ($t = 0; $t -lt 6; $t++) {
        $tms = Convert-NesTileToTms $bytes ($classOff + $CHEER_TILES[$t] * 16)
        $hex = ($tms | ForEach-Object { "0x{0:X2}" -f $_ }) -join ","
        [void]$sb.AppendLine("  $hex,   // $($labels[$t])")
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# --- colore per riga ---
[void]$sb.AppendLine("// Colore dominante per riga (schema slice30): (fg << 4) | nero")
[void]$sb.AppendLine("static const unsigned char ff1_class_cheer_color[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    $subpal = $CLASS_SUBPAL[$c]
    [void]$sb.AppendLine("  // [$c] $($classNames[$c]) (sub-pal $subpal)")
    for ($t = 0; $t -lt 6; $t++) {
        $col = Get-PerRowColors $bytes ($classOff + $CHEER_TILES[$t] * 16) $subpal
        $hex = ($col | ForEach-Object { "0x{0:X2}" -f $_ }) -join ","
        [void]$sb.AppendLine("  $hex,   // $($labels[$t])")
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")

# --- accento OAM ---
$accentValues = New-Object int[] $N_CLASSES
[void]$sb.AppendLine("// Strato accento OAM (schema slice31), stesso valore NES della posa in piedi")
[void]$sb.AppendLine("static const unsigned char ff1_class_cheer_accent[288] = {")
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    $classOff = $CLASS_BASE + ($c * $CLASS_STRIDE)
    $classAccentOverride = @{ 0 = 3 }   # FT -> incarnato
    if ($classAccentOverride.ContainsKey($c)) { $accVal = $classAccentOverride[$c] }
    else { $accVal = Get-AccentValueForClass $bytes $classOff }
    $accentValues[$c] = $accVal
    [void]$sb.AppendLine("  // [$c] $($classNames[$c]) accent NES value=$accVal")
    for ($t = 0; $t -lt 6; $t++) {
        $pat = Get-AccentPattern $bytes ($classOff + $CHEER_TILES[$t] * 16) $accVal
        $hex = ($pat | ForEach-Object { "0x{0:X2}" -f $_ }) -join ","
        [void]$sb.AppendLine("  $hex,   // $($labels[$t])")
    }
}
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_CHEER_SPRITES_DEFINE_DATA")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_CHEER_SPRITES_H")

$dest = $outPath
[System.IO.File]::WriteAllText($dest, $sb.ToString())
Write-Host "Scritto: $dest"
Write-Host "  3 array da 288 byte = 864 byte (pattern + colore + accento)"
Write-Host "Valori di accento per classe (devono coincidere con la posa in piedi):"
for ($c = 0; $c -lt $N_CLASSES; $c++) {
    Write-Host ("  {0}: NES value={1}" -f $classNames[$c], $accentValues[$c])
}
