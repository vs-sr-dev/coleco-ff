# render_sm_reference.ps1 -- disegna l'INTERA citta' come PNG, dai dati
# generati, con l'ingresso segnato.
#
# Gemello di render_ow_reference.ps1. Serve a rispondere a una domanda che
# ne' lo schermo dell'emulatore ne' una mappa ASCII sanno risolvere: **dove
# cade davvero il punto di ingresso dentro la citta'?**
#
# L'emulatore mostra 32x24 celle su 128x128: un ventiquattresimo della mappa.
# Guardando quello si puo' dire "sono nel posto sbagliato" senza poter dire
# dove sia il posto giusto. Qui si vede tutta la citta' in una volta.
#
# Usa gli STESSI dati che finiscono nel banco 15 (pattern + color + TSA +
# mappa di ff1_towngfx.h), quindi se l'immagine e' giusta e lo schermo no, il
# difetto e' a valle dei dati; se e' sbagliata anche qui, e' nei dati.

param(
    [string]$Root  = (Split-Path -Parent $PSScriptRoot),
    [string]$Hdr   = 'src\ff1_towngfx.h',
    [string]$Out   = 'build\coneria_reference.png',
    [int]$EntryX = 16,
    [int]$EntryY = 23
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-CArray([string]$file, [string]$pattern) {
    $txt = Get-Content (Join-Path $Root $file) -Raw
    $m = [regex]::Match($txt, $pattern, 'Singleline')
    if (-not $m.Success) { throw "non trovato: $pattern" }
    return @([regex]::Matches($m.Groups[1].Value, '0x([0-9A-Fa-f]{2})') |
             ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) })
}

$pattern = Get-CArray $Hdr 'ff1_towngfx_pattern\[FF1_TOWNGFX_TILE_COUNT \* 8\]\s*=\s*\{(.*?)\n\};'
$color   = Get-CArray $Hdr 'ff1_towngfx_color\[FF1_TOWNGFX_TILE_COUNT \* 8\]\s*=\s*\{(.*?)\n\};'
$map     = Get-CArray $Hdr 'ff1_towngfx_map\[FF1_TOWNGFX_MAP_W \* FF1_TOWNGFX_MAP_H\]\s*=\s*\{(.*?)\n\};'
$tsa = @()
foreach ($q in 'ul','ur','dl','dr') {
    $tsa += ,(Get-CArray $Hdr "ff1_towngfx_tsa_$q\[FF1_TOWNGFX_MACRO_COUNT\]\s*=\s*\{(.*?)\n\};")
}

# Palette TMS9918 (RGB), l'ordine e' quello degli indici 0-15.
$TMS = @(
    @(0,0,0),       @(0,0,0),       @(33,200,66),   @(94,220,120),
    @(84,85,237),   @(125,118,252), @(212,82,77),   @(66,235,245),
    @(252,85,84),   @(255,121,120), @(212,193,84),  @(230,206,128),
    @(33,176,59),   @(201,91,186),  @(204,204,204), @(255,255,255)
)

# 1024x1024 pixel: SetPixel uno per uno sono un milione di chiamate e non
# finisce piu'. Si riempie un buffer di byte e lo si copia in un colpo solo.
$W = 1024
$buf = New-Object byte[] ($W * $W * 3)   # 24bpp, righe allineate a 4 -> 1024*3 e' gia' multiplo di 4

for ($my = 0; $my -lt 64; $my++) {
    for ($mx = 0; $mx -lt 64; $mx++) {
        $m = $map[$my * 64 + $mx]
        for ($q = 0; $q -lt 4; $q++) {
            $id = $tsa[$q][$m]
            $cx = $mx * 2 + ($q -band 1)
            # `-shr 1`, NON `[int]($q / 2)`: il cast [int] di PowerShell
            # arrotonda alla pari (bankers rounding), quindi 3/2 da' 2 e non 1,
            # e il quadrante in basso a destra finisce una riga troppo giu'.
            $cy = $my * 2 + ($q -shr 1)
            for ($row = 0; $row -lt 8; $row++) {
                $bits = $pattern[$id * 8 + $row]
                $col  = $color[$id * 8 + $row]
                $fg = $TMS[($col -shr 4) -band 0xF]
                $bg = $TMS[$col -band 0xF]
                $py = $cy * 8 + $row
                for ($x = 0; $x -lt 8; $x++) {
                    $c = if ((($bits -shr (7 - $x)) -band 1)) { $fg } else { $bg }
                    $o = ($py * $W + $cx * 8 + $x) * 3
                    $buf[$o]     = [byte]$c[2]   # BGR
                    $buf[$o + 1] = [byte]$c[1]
                    $buf[$o + 2] = [byte]$c[0]
                }
            }
        }
    }
}

$bmp  = New-Object System.Drawing.Bitmap $W, $W, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$rect = New-Object System.Drawing.Rectangle 0, 0, $W, $W
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $buf.Length)
$bmp.UnlockBits($data)

# L'ingresso: riquadro rosso sul MACROtile, piu' la finestra 32x24 celle che
# l'emulatore mostrerebbe con la telecamera calcolata come fa enter_town.
$g = [System.Drawing.Graphics]::FromImage($bmp)
$penEntry = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
$penView  = New-Object System.Drawing.Pen ([System.Drawing.Color]::Yellow), 3
$g.DrawRectangle($penEntry, $EntryX * 16, $EntryY * 16, 16, 16)

$camX = $EntryX * 2 - 15
$camY = $EntryY * 2 - 11
$g.DrawRectangle($penView, $camX * 8, $camY * 8, 32 * 8, 24 * 8)
$g.Dispose()

$outPath = Join-Path $Root $Out
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "scritto $outPath"
Write-Host ("  riquadro ROSSO  = macrotile di ingresso ({0},{1})" -f $EntryX, $EntryY)
Write-Host ("  riquadro GIALLO = la finestra che si vede all'ingresso, telecamera ({0},{1}) in celle" -f $camX, $camY)
