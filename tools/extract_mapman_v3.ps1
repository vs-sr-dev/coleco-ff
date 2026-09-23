# extract_mapman_v3.ps1
#
# Genera src/ff1_mapman_flat.h: gli sprite mapman overworld delle 6 classi,
# a TRE strati OAM, con i colori presi dalle palette NES VERE.
#
# COSA CAMBIA RISPETTO ALLA v2 (extract_mapman.ps1)
#   La v2 aveva colori indovinati a mano (`$classMainColor = 15, 3, 11, ...`,
#   cioe' Fighter BIANCO) e un accent_value diverso per classe. Guardando i
#   dati veri:
#     - lut_MapmanPalettes (bank_00.dat +$3A0) da' DUE colori per classe;
#     - gli attributi dei tile nella LUT sprite valgono 0x00/0x40 per i due
#       quadranti ALTI e 0x01/0x41 per i due BASSI: la meta' superiore usa la
#       sotto-palette sprite 0, quella inferiore la 1.
#     - in entrambe le sotto-palette il colore 3 e' $36 (incarnato), il colore
#       1 e' $0F (nero di contorno).
#   Quindi il mapman NES ha: contorno nero + colore corpo alto + colore corpo
#   basso + incarnato. Il Fighter e' $16 (rosso-arancio), non bianco.
#
# I QUATTRO STRATI (TMS9918: uno sprite = un colore)
#   SAT[0] incarnato   = pixel di valore 3
#   SAT[1] meta' alta  = pixel di valore 2 nei quadranti TL/TR, sotto-palette 0
#   SAT[2] meta' bassa = pixel di valore 2 nei quadranti BL/BR, sotto-palette 1
#   SAT[3] contorno    = pixel di valore 1 ($0F nero in entrambe le palette)
#
#   Gli strati sono DISGIUNTI: ogni pixel NES appartiene a uno solo di essi in
#   base al proprio valore. Per questo gli strati corpo NON sono silhouette
#   piene (l'OR dei due piani) -- lo erano nella v2, ed e' il motivo per cui
#   coprivano il contorno nero facendolo sparire.
#
#   Quattro strati riproducono per intero la resa NES: contorno + due colori
#   corpo + incarnato. Sono anche esattamente il limite di 4 sprite per
#   scanline del TMS9918: sta in piedi perche' in overworld e in citta' il
#   mapman e' l'unico sprite a schermo. Aggiungere altri sprite sulle sue
#   righe ne farebbe sparire uno.
#
# Emette array 1-D e header gated: i multidimensionali finirebbero in sezione
# DATA, mai inizializzata dentro un banco ([[slice44-real-root-causes]] #3).

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$Out    = "$PSScriptRoot\..\src\ff1_mapman_flat.h",
    # Colore TMS dell'incarnato. Il NES usa $36 (240,208,176), un pesca pallido
    # che sul TMS9918 non esiste. I due candidati:
    #   11 light yellow (230,206,128) -- il piu' vicino in RGB, ma giallognolo
    #    9 light red    (255,121,120) -- piu' rosato, ma quasi identico al
    #                                    medium red del corpo di FT/RM
    # 0 = usa la conversione automatica di $36 (che da' 11).
    [int]$SkinTms = 0
)

$ErrorActionPreference = 'Stop'

$chr = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_02.dat'))
$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_00.dat'))

$classNames = @('FT', 'TH', 'BB', 'RM', 'WM', 'BM')
$classBase  = @(0x1000, 0x1100, 0x1200, 0x1300, 0x1400, 0x1500)

# LUT sprite NES, ordine R0 R1 L0 L1 U0 U1 D0 D1; ogni voce = 4 x (tile, attr)
# nell'ordine UL, DL, UR, DR.
$lutFrames = @(
    @(@(0x09,0x40), @(0x0B,0x41), @(0x08,0x40), @(0x0A,0x41)), # R0
    @(@(0x0D,0x40), @(0x0F,0x41), @(0x0C,0x40), @(0x0E,0x41)), # R1
    @(@(0x08,0x00), @(0x0A,0x01), @(0x09,0x00), @(0x0B,0x01)), # L0
    @(@(0x0C,0x00), @(0x0E,0x01), @(0x0D,0x00), @(0x0F,0x01)), # L1
    @(@(0x04,0x00), @(0x06,0x01), @(0x05,0x00), @(0x07,0x01)), # U0
    @(@(0x04,0x00), @(0x07,0x41), @(0x05,0x00), @(0x06,0x41)), # U1
    @(@(0x00,0x00), @(0x02,0x01), @(0x01,0x00), @(0x03,0x01)), # D0
    @(@(0x00,0x00), @(0x03,0x41), @(0x01,0x00), @(0x02,0x41))  # D1
)
# Ordine di uscita: DOWN, UP, LEFT, RIGHT (convenzione delle slice).
$order = @(6, 7, 4, 5, 2, 3, 0, 1)

# Mappa NES -> TMS9918, coerente con docs/colors_nes_to_tms.md.
$NES2TMS = @{
    0x0F = 1;  0x30 = 15; 0x10 = 14; 0x00 = 14;
    0x12 = 4;  0x11 = 4;  0x01 = 4;
    0x21 = 5;  0x22 = 5;
    0x15 = 6;  0x16 = 8;  0x26 = 9;  0x36 = 11;
    0x17 = 10; 0x18 = 10; 0x27 = 10; 0x28 = 11; 0x37 = 11;
    0x19 = 12; 0x1A = 2;  0x29 = 3;  0x2A = 3;
}
function Get-TmsColor([int]$nes) {
    $k = $nes -band 0x3F
    if ($NES2TMS.ContainsKey($k)) { return [int]$NES2TMS[$k] }
    throw ("colore NES 0x{0} non mappato: aggiungerlo a NES2TMS" -f $k.ToString('X2'))
}

function Reverse-Bits([byte]$b) {
    $r = 0
    for ($i = 0; $i -lt 8; $i++) { if (($b -shr $i) -band 1) { $r = $r -bor (1 -shl (7 - $i)) } }
    return [byte]($r -band 0xFF)
}

# Silhouette: OR dei due piani (tutti i pixel non trasparenti).
function Convert-Silhouette($src, [int]$off, [bool]$hflip) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $v = ([int]$src[$off + $r] -bor [int]$src[$off + 8 + $r]) -band 0xFF
        if ($hflip) { $v = Reverse-Bits ([byte]$v) }
        $out[$r] = [byte]$v
    }
    return $out
}

# Accent: bit acceso solo dove il pixel NES vale esattamente $wanted.
function Convert-Match($src, [int]$off, [bool]$hflip, [int]$wanted) {
    $out = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = [int]$src[$off + $r]
        $hi = [int]$src[$off + 8 + $r]
        $bits = 0
        for ($b = 0; $b -lt 8; $b++) {
            $sh = 7 - $b
            $val = (((($hi -shr $sh) -band 1) -shl 1) -bor (($lo -shr $sh) -band 1))
            if ($val -eq $wanted) { $bits = $bits -bor (1 -shl $sh) }
        }
        if ($hflip) { $bits = Reverse-Bits ([byte]$bits) }
        $out[$r] = [byte]$bits
    }
    return $out
}

# Verifica dell'assunto sulle palette: quadranti alti (UL,UR) devono stare in
# palette 0, bassi (DL,DR) in palette 1. Se salta, tutto il ragionamento cade.
foreach ($slot in $lutFrames) {
    if ((([int]$slot[0][1]) -band 3) -ne 0 -or (([int]$slot[2][1]) -band 3) -ne 0) {
        throw "assunto rotto: un quadrante ALTO non usa la sotto-palette 0"
    }
    if ((([int]$slot[1][1]) -band 3) -ne 1 -or (([int]$slot[3][1]) -band 3) -ne 1) {
        throw "assunto rotto: un quadrante BASSO non usa la sotto-palette 1"
    }
}
Write-Host "assunto palette alto/basso verificato su tutti gli 8 frame"

$N = 6 * 8 * 32
$top     = New-Object byte[] $N
$bot     = New-Object byte[] $N
$accent  = New-Object byte[] $N
$outline = New-Object byte[] $N

for ($c = 0; $c -lt 6; $c++) {
    for ($f = 0; $f -lt 8; $f++) {
        $slot = $lutFrames[$order[$f]]
        $frameOff = $c * 256 + $f * 32
        for ($q = 0; $q -lt 4; $q++) {
            $tileNum = [int]$slot[$q][0]
            $attr    = [int]$slot[$q][1]
            $hflip   = ($attr -band 0x40) -ne 0
            $off     = $classBase[$c] + ($tileNum * 16)
            $isTop   = ($q -eq 0 -or $q -eq 2)     # q: 0=UL(TL) 1=DL(BL) 2=UR(TR) 3=DR(BR)

            # Strati disgiunti per valore di pixel: 1 = contorno, 2 = corpo,
            # 3 = incarnato. Il valore 0 e' trasparente.
            $body = Convert-Match $chr $off $hflip 2
            $skin = Convert-Match $chr $off $hflip 3
            $line = Convert-Match $chr $off $hflip 1
            for ($i = 0; $i -lt 8; $i++) {
                $idx = $frameOff + $q * 8 + $i
                if ($isTop) { $top[$idx] = $body[$i] } else { $bot[$idx] = $body[$i] }
                $accent[$idx]  = $skin[$i]
                $outline[$idx] = $line[$i]
            }
        }
    }
}

# Colori: due per classe da lut_MapmanPalettes ($83A0 -> offset 0x3A0),
# piu' l'incarnato $36 comune a entrambe le sotto-palette sprite.
$topCol = New-Object byte[] 6
$botCol = New-Object byte[] 6
$accCol = New-Object byte[] 6
$SKIN_NES = 0x36
Write-Host ""
Write-Host "colori per classe (NES -> TMS):"
$tmsName = @('transp','black','med green','light green','dark blue','light blue','dark red','cyan',
             'med red','light red','dark yellow','light yellow','dark green','magenta','gray','white')
for ($c = 0; $c -lt 6; $c++) {
    $nesTop = [int]$b00[0x3A0 + $c * 2]
    $nesBot = [int]$b00[0x3A0 + $c * 2 + 1]
    $topCol[$c] = [byte](Get-TmsColor $nesTop)
    $botCol[$c] = [byte](Get-TmsColor $nesBot)
    if ($SkinTms -gt 0) { $accCol[$c] = [byte]$SkinTms } else { $accCol[$c] = [byte](Get-TmsColor $SKIN_NES) }
    Write-Host ("  {0}: alto `${1}->{2,-13} basso `${3}->{4,-13} pelle `${5}->{6}" -f `
        $classNames[$c], $nesTop.ToString('X2'), $tmsName[$topCol[$c]],
        $nesBot.ToString('X2'), $tmsName[$botCol[$c]],
        $SKIN_NES.ToString('X2'), $tmsName[$accCol[$c]])
}

function Format-ByteArray([byte[]]$arr, [int]$perLine = 16) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $arr.Length; $i++) {
        if ($i % $perLine -eq 0) { [void]$sb.Append("    ") }
        [void]$sb.Append(("0x{0:X2}" -f $arr[$i]))
        if ($i -ne $arr.Length - 1) { [void]$sb.Append(",") }
        if ($i % $perLine -eq $perLine - 1) { [void]$sb.AppendLine() } else { [void]$sb.Append(" ") }
    }
    if ($arr.Length % $perLine -ne 0) { [void]$sb.AppendLine() }
    return $sb.ToString()
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATO da tools/extract_mapman_v3.ps1 -- non modificare a mano.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Mapman overworld delle 6 classi FF1 a QUATTRO strati OAM disgiunti,")
[void]$sb.AppendLine("// uno per valore di pixel NES:")
[void]$sb.AppendLine("//   SAT[0] accent  = incarnato (valore 3)")
[void]$sb.AppendLine("//   SAT[1] top     = corpo (valore 2) meta' alta, sotto-palette sprite 0")
[void]$sb.AppendLine("//   SAT[2] bot     = corpo (valore 2) meta' bassa, sotto-palette sprite 1")
[void]$sb.AppendLine("//   SAT[3] outline = contorno (valore 1), nero")
[void]$sb.AppendLine("// Quattro sprite sulla stessa scanline = limite esatto del TMS9918.")
[void]$sb.AppendLine("// I colori vengono da lut_MapmanPalettes (bank_00.dat +\$3A0), non piu'")
[void]$sb.AppendLine("// scelti a mano: il Fighter e' rosso-arancio (\$16), non bianco.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Indici: [cls * 256 + frame * 32 + b]")
[void]$sb.AppendLine("//   cls 0..5 = FT TH BB RM WM BM")
[void]$sb.AppendLine("//   frame 0..7 = dir*2 + passo, dir 0=DOWN 1=UP 2=LEFT 3=RIGHT")
[void]$sb.AppendLine("//   layout 32 byte = TL(8) BL(8) TR(8) BR(8)")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Header GATED: i dati escono solo con FF1_MAPMAN_DEFINE_DATA definito.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_MAPMAN_FLAT_H")
[void]$sb.AppendLine("#define FF1_MAPMAN_FLAT_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#define FF1_MAPMAN_CLASSES     6")
[void]$sb.AppendLine("#define FF1_MAPMAN_FRAMES      8")
[void]$sb.AppendLine("#define FF1_MAPMAN_FRAME_BYTES 32")
[void]$sb.AppendLine("#define FF1_MAPMAN_CLASS_BYTES (FF1_MAPMAN_FRAMES * FF1_MAPMAN_FRAME_BYTES)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifdef FF1_MAPMAN_DEFINE_DATA")
[void]$sb.AppendLine("")
foreach ($pair in @(@('ff1_mapman_top_flat', $top), @('ff1_mapman_bot_flat', $bot),
                    @('ff1_mapman_accent_flat', $accent),
                    @('ff1_mapman_outline_flat', $outline),
                    @('ff1_mapman_top_color_flat', $topCol),
                    @('ff1_mapman_bot_color_flat', $botCol),
                    @('ff1_mapman_accent_color_flat', $accCol))) {
    [void]$sb.AppendLine(("static const unsigned char {0}[{1}] = {{" -f $pair[0], $pair[1].Length))
    [void]$sb.Append((Format-ByteArray $pair[1]))
    [void]$sb.AppendLine("};")
    [void]$sb.AppendLine("")
}
[void]$sb.AppendLine("#endif // FF1_MAPMAN_DEFINE_DATA")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_MAPMAN_FLAT_H")

[System.IO.File]::WriteAllText($Out, $sb.ToString())
Write-Host ""
Write-Host ("scritto {0}" -f $Out)
