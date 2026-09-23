# extract_ow_colors.ps1
#
# Genera la grafica OW A COLORI VERI per il TMS9918, sostituendo il
# placeholder verde piatto (slice44 faceva vdp_vfill(0x2000, 0x3C, ...)).
#
# PERCHE' FUNZIONA (misurato da analyze_ow_colors.ps1):
#   Sul TMS9918 mode 2 il colore e' legato all'ID del tile, non alla posizione.
#   Se un tile CHR compare con due palette diverse servono due tile distinti.
#   Nella OW di FF1 le coppie (tile, palette) distinte sono 236 <= 256: ci
#   stanno tutte, con 20 tile di margine.
#
# SORGENTI (verificate empiricamente, non ipotizzate)
#   bank_02.dat offset 0      : CHR NES 2bpp, 256 tile x 16 byte
#   bank_00.dat +$100..+$2FF  : tsa_ul/ur/dl/dr (4 quadranti per metatile)
#   bank_00.dat +$300         : tsa_attr  -> palette del metatile (attr & 3)
#   bank_00.dat +$380         : load_map_pal -> le 4 sotto-palette BG NES
#
# RIDUZIONE COLORE (schema "per-row dominant" validato in slice30)
#   Ogni riga di 8 pixel puo' avere 2 colori sul TMS. Per ogni riga si contano
#   i colori TMS dei pixel, si prendono i due piu' frequenti come fg/bg e i
#   restanti si assegnano al piu' vicino per luminanza. Molto meglio dell'OR
#   dei piani (che collassava tutto in una silhouette monocroma).
#
# OUTPUT
#   src/ff1_owgfx.h -- header "gated": i dati veri vengono emessi solo se il
#   chiamante fa #define FF1_OWGFX_DEFINE_DATA (lo fa src/owgfx_bank.c, che
#   possiede il banco). Cosi' la slice principale non se li ritrova in rodata.

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$Out    = "$PSScriptRoot\..\src\ff1_owgfx.h"
)

$ErrorActionPreference = 'Stop'

$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_00.dat'))
$b02 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_02.dat'))

$tsa    = @($b00[0x100..0x17F], $b00[0x180..0x1FF], $b00[0x200..0x27F], $b00[0x280..0x2FF])
$tsaAttr = $b00[0x300..0x37F]
$mapPal  = $b00[0x380..0x3AF]

# --- NES master color -> indice TMS9918 -------------------------------------
# Base da docs/colors_nes_to_tms.md, estesa ai colori che la OW usa davvero
# ($1A $27 $29 $31 $37, misurati da analyze_ow_colors.ps1).
$NES2TMS = @{
    0x0F = 1;   0x0D = 1;             # nero
    0x00 = 14;  0x10 = 14; 0x20 = 14; # grigi
    0x30 = 15;                        # bianco
    0x01 = 4;   0x11 = 4;  0x12 = 4;  # blu scuro
    0x21 = 5;   0x22 = 5;             # blu chiaro (acqua bassa)
    0x31 = 7;                         # ciano pallido (acqua)
    0x15 = 6;   0x16 = 8;  0x26 = 9; 0x36 = 9;
    0x18 = 10;  0x27 = 10;            # oliva / sabbia deserto
    0x28 = 11;  0x37 = 11;            # sabbia chiara / crema
    0x19 = 12;                        # verde scuro (foresta fitta)
    0x1A = 2;                         # verde medio (erba: il colore base OW)
    0x29 = 3;   0x2A = 3;             # verde chiaro
}

# Luminanza approssimata dei colori TMS9918, per assegnare i pixel "avanzati"
# al piu' vicino fra i due scelti.
$TMSLUM = @{ 0 = 0; 1 = 0; 2 = 110; 3 = 160; 4 = 70; 5 = 120; 6 = 90;
             7 = 175; 8 = 110; 9 = 145; 10 = 150; 11 = 200; 12 = 95;
             13 = 130; 14 = 190; 15 = 255 }

function Get-TmsColor([int]$nes) {
    $key = $nes -band 0x3F
    if ($NES2TMS.ContainsKey($key)) { return [int]$NES2TMS[$key] }
    # Fallback prudente: non inventare, segnala.
    Write-Host ("  ATTENZIONE: colore NES 0x{0} non mappato -> uso nero" -f $key.ToString('X2')) -ForegroundColor Yellow
    return 1
}

# --- assegnazione degli ID: una coppia (tile, palette) = un tile TMS ---------
$comboId  = @{}
$comboList = New-Object System.Collections.ArrayList
# NB: ogni New-Object va fra parentesi -- `New-Object byte[] 128, (...)` farebbe
# legare la virgola come lista di argomenti di New-Object, non come elementi
# dell'array (stessa famiglia di trappole di [[powershell -f operator]]).
$tsaNew = @((New-Object byte[] 128), (New-Object byte[] 128), (New-Object byte[] 128), (New-Object byte[] 128))

for ($m = 0; $m -lt 128; $m++) {
    $pal = [int]$tsaAttr[$m] -band 3
    for ($q = 0; $q -lt 4; $q++) {
        $tid = [int]$tsa[$q][$m]
        $key = "$tid/$pal"
        if (-not $comboId.ContainsKey($key)) {
            $id = $comboList.Count
            if ($id -gt 255) { throw "sforato il limite di 256 tile TMS: la riduzione per coppie non basta" }
            $comboId[$key] = $id
            [void]$comboList.Add(@{ Tile = $tid; Pal = $pal })
        }
        $tsaNew[$q][$m] = [byte]$comboId[$key]
    }
}
$nCombo = $comboList.Count
Write-Host ("coppie (tile,palette) -> tile TMS: {0} (max 256)" -f $nCombo)

# --- generazione pattern + colore per ogni tile TMS -------------------------
$pattern = New-Object byte[] (256 * 8)
$color   = New-Object byte[] (256 * 8)

for ($id = 0; $id -lt $nCombo; $id++) {
    $tid = [int]$comboList[$id].Tile
    $pal = [int]$comboList[$id].Pal

    # I 4 colori TMS di questa sotto-palette.
    $palTms = New-Object int[] 4
    for ($c = 0; $c -lt 4; $c++) {
        $palTms[$c] = Get-TmsColor ([int]$mapPal[$pal * 4 + $c])
    }

    for ($row = 0; $row -lt 8; $row++) {
        $p0 = [int]$b02[$tid * 16 + $row]
        $p1 = [int]$b02[$tid * 16 + 8 + $row]

        # Colore TMS di ciascuno degli 8 pixel + istogramma.
        $px = New-Object int[] 8
        $hist = @{}
        for ($x = 0; $x -lt 8; $x++) {
            $bit = 7 - $x
            $ci = ((($p0 -shr $bit) -band 1)) -bor ((($p1 -shr $bit) -band 1) -shl 1)
            $tms = $palTms[$ci]
            $px[$x] = $tms
            if ($hist.ContainsKey($tms)) { $hist[$tms]++ } else { $hist[$tms] = 1 }
        }

        # fg = piu' frequente, bg = secondo. Parita' risolta dal colore piu'
        # chiaro come fg, cosi' il risultato e' deterministico.
        $ranked = @($hist.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, @{Expression={$TMSLUM[[int]$_.Key]}; Descending=$true})
        $fg = [int]$ranked[0].Key
        if ($ranked.Count -gt 1) { $bg = [int]$ranked[1].Key } else { $bg = 1 }
        if ($fg -eq $bg) { $bg = 1 }

        # Bit = 1 -> fg. I colori diversi da fg/bg vanno al piu' vicino per luminanza.
        $bits = 0
        for ($x = 0; $x -lt 8; $x++) {
            $c = $px[$x]
            $isFg = $false
            if ($c -eq $fg) { $isFg = $true }
            elseif ($c -eq $bg) { $isFg = $false }
            else {
                $dFg = [Math]::Abs($TMSLUM[$c] - $TMSLUM[$fg])
                $dBg = [Math]::Abs($TMSLUM[$c] - $TMSLUM[$bg])
                $isFg = ($dFg -le $dBg)
            }
            if ($isFg) { $bits = $bits -bor (1 -shl (7 - $x)) }
        }

        $pattern[$id * 8 + $row] = [byte]$bits
        $color[$id * 8 + $row]   = [byte](($fg -shl 4) -bor $bg)
    }
}

# I tile inutilizzati (236..255) restano vuoti su nero.
for ($id = $nCombo; $id -lt 256; $id++) {
    for ($row = 0; $row -lt 8; $row++) {
        $pattern[$id * 8 + $row] = 0
        $color[$id * 8 + $row]   = 0x11
    }
}

# --- emissione header --------------------------------------------------------
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
[void]$sb.AppendLine("// AUTO-GENERATO da tools/extract_ow_colors.ps1 -- non modificare a mano.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Grafica overworld FF1 a COLORI VERI per TMS9918.")
[void]$sb.AppendLine("// Ogni tile TMS = una coppia (tile CHR NES, sotto-palette). Coppie usate:")
[void]$sb.AppendLine("//   $nCombo su 256 disponibili.")
[void]$sb.AppendLine("// Colore: 8 byte per tile, (fg << 4) | bg per riga (schema per-row dominant).")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Header GATED: i dati sono emessi solo con FF1_OWGFX_DEFINE_DATA definito")
[void]$sb.AppendLine("// (lo fa src/owgfx_bank.c, proprietario del banco). La slice principale")
[void]$sb.AppendLine("// include questo file solo per le costanti.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifndef FF1_OWGFX_H")
[void]$sb.AppendLine("#define FF1_OWGFX_H")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#define FF1_OWGFX_TILE_COUNT 256")
[void]$sb.AppendLine("#define FF1_OWGFX_COMBO_USED $nCombo")
[void]$sb.AppendLine("#define FF1_OWGFX_METATILE_COUNT 128")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#ifdef FF1_OWGFX_DEFINE_DATA")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("static const unsigned char ff1_owgfx_pattern[FF1_OWGFX_TILE_COUNT * 8] = {")
[void]$sb.Append((Format-ByteArray $pattern))
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("static const unsigned char ff1_owgfx_color[FF1_OWGFX_TILE_COUNT * 8] = {")
[void]$sb.Append((Format-ByteArray $color))
[void]$sb.AppendLine("};")
[void]$sb.AppendLine("")
$names = @('ul', 'ur', 'dl', 'dr')
for ($q = 0; $q -lt 4; $q++) {
    [void]$sb.AppendLine(("static const unsigned char ff1_owgfx_tsa_{0}[FF1_OWGFX_METATILE_COUNT] = {{" -f $names[$q]))
    [void]$sb.Append((Format-ByteArray $tsaNew[$q]))
    [void]$sb.AppendLine("};")
    [void]$sb.AppendLine("")
}
[void]$sb.AppendLine("#endif // FF1_OWGFX_DEFINE_DATA")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("#endif // FF1_OWGFX_H")

[System.IO.File]::WriteAllText($Out, $sb.ToString())
Write-Host ("scritto {0}" -f $Out)

# Riepilogo leggibile delle 4 palette risultanti.
Write-Host ""
Write-Host "palette risultanti (NES -> TMS):"
$tmsName = @('transp','black','med green','light green','dark blue','light blue','dark red','cyan',
             'med red','light red','dark yellow','light yellow','dark green','magenta','gray','white')
for ($p = 0; $p -lt 4; $p++) {
    $parts = @()
    for ($c = 0; $c -lt 4; $c++) {
        $nes = [int]$mapPal[$p * 4 + $c]
        $t = Get-TmsColor $nes
        $parts += ("`${0}->{1}" -f $nes.ToString('X2'), $tmsName[$t])
    }
    Write-Host ("  pal {0}: {1}" -f $p, ($parts -join ',  '))
}
