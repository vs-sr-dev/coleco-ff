# render_ow_reference.ps1
#
# Rende la stessa vista overworld che disegna la slice, ma con i COLORI NES
# VERI a 2bpp (nessuna riduzione TMS9918). Serve come metro di paragone
# oggettivo: affiancandolo alla cattura dell'emulatore si vede esattamente
# quali tile perdono qualcosa nella riduzione a 2 colori per riga.
#
# Non tocca il gioco: e' puro strumento diagnostico.
#
# Uso:
#   .\render_ow_reference.ps1                        # vista di spawn (Coneria)
#   .\render_ow_reference.ps1 -MacroX 153 -MacroY 165 -Scale 4

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$MapBin = "$PSScriptRoot\..\data\ff1_ow_full.bin",
    [int]$MacroX = 153,      # posizione del giocatore in macrotile (spawn FF1)
    [int]$MacroY = 165,
    [int]$Scale  = 1,
    [string]$Out = "$PSScriptRoot\..\build\ow_reference_nes.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_00.dat'))
$b02 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_02.dat'))
$map = [System.IO.File]::ReadAllBytes($MapBin)

$tsa     = @($b00[0x100..0x17F], $b00[0x180..0x1FF], $b00[0x200..0x27F], $b00[0x280..0x2FF])
$tsaAttr = $b00[0x300..0x37F]
$mapPal  = $b00[0x380..0x3AF]

# Palette master NES 2C02 (RGB), solo le righe che servono.
$NESRGB = @{}
$rows = @(
    @(0x00, @(124,124,124), @(0,0,252), @(0,0,188), @(68,40,188), @(148,0,132), @(168,0,32), @(168,16,0), @(136,20,0), @(80,48,0), @(0,120,0), @(0,104,0), @(0,88,0), @(0,64,88)),
    @(0x10, @(188,188,188), @(0,120,248), @(0,88,248), @(104,68,252), @(216,0,204), @(228,0,88), @(248,56,0), @(228,92,16), @(172,124,0), @(0,184,0), @(0,168,0), @(0,168,68), @(0,136,136)),
    @(0x20, @(248,248,248), @(60,188,252), @(104,136,252), @(152,120,248), @(248,120,248), @(248,88,152), @(248,120,88), @(252,160,68), @(248,184,0), @(184,248,24), @(88,216,84), @(88,248,152), @(0,232,216)),
    @(0x30, @(252,252,252), @(164,228,252), @(184,184,248), @(216,184,248), @(248,184,248), @(248,164,192), @(240,208,176), @(252,224,168), @(248,216,120), @(216,248,120), @(184,248,184), @(184,248,216), @(0,252,252))
)
foreach ($row in $rows) {
    $base = [int]$row[0]
    for ($i = 1; $i -lt $row.Count; $i++) {
        $NESRGB[$base + $i - 1] = $row[$i]
    }
}
$NESRGB[0x0F] = @(0, 0, 0)
$NESRGB[0x0D] = @(0, 0, 0)
$NESRGB[0x1F] = @(0, 0, 0)
$NESRGB[0x2F] = @(0, 0, 0)
$NESRGB[0x3F] = @(0, 0, 0)

# Stessa geometria della slice: il giocatore sta alla cella (15,11), quindi
# la cella in alto a sinistra e' (macroX*2 - 15, macroY*2 - 11). Ogni cella
# e' meta' macrotile: il quadrante e' dato dai bit bassi delle coordinate.
$originCellX = $MacroX * 2 - 15
$originCellY = $MacroY * 2 - 11

$W = 32 * 8
$H = 24 * 8
$bmp = New-Object System.Drawing.Bitmap $W, $H

for ($cy = 0; $cy -lt 24; $cy++) {
    for ($cx = 0; $cx -lt 32; $cx++) {
        $wx = ($originCellX + $cx) -band 511   # 256 macro * 2 celle, toroidale
        $wy = ($originCellY + $cy) -band 511
        $mx = ($wx -shr 1) -band 255
        $my = ($wy -shr 1) -band 255
        $q  = (($wy -band 1) * 2) + ($wx -band 1)   # 0=UL 1=UR 2=DL 3=DR

        $macro = [int]$map[$my * 256 + $mx] -band 0x7F
        $tid   = [int]$tsa[$q][$macro]
        $pal   = [int]$tsaAttr[$macro] -band 3

        for ($row = 0; $row -lt 8; $row++) {
            $p0 = [int]$b02[$tid * 16 + $row]
            $p1 = [int]$b02[$tid * 16 + 8 + $row]
            for ($x = 0; $x -lt 8; $x++) {
                $bit = 7 - $x
                $ci = ((($p0 -shr $bit) -band 1)) -bor ((($p1 -shr $bit) -band 1) -shl 1)
                $nes = [int]$mapPal[$pal * 4 + $ci]
                $rgb = $NESRGB[$nes -band 0x3F]
                if (-not $rgb) { $rgb = @(255, 0, 255) }   # magenta = colore non in tabella
                $bmp.SetPixel($cx * 8 + $x, $cy * 8 + $row,
                    [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))
            }
        }
    }
}

if ($Scale -gt 1) {
    $big = New-Object System.Drawing.Bitmap ($W * $Scale), ($H * $Scale)
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($bmp, 0, 0, ($W * $Scale), ($H * $Scale))
    $g.Dispose()
    $bmp.Dispose()
    $bmp = $big
}

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("scritto {0} (vista macro {1},{2})" -f $Out, $MacroX, $MacroY)
