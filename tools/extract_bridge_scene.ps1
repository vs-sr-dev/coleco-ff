# extract_bridge_scene.ps1 -- la schermata della SCENA DEL PONTE per TMS9918.
#
# PERCHE' E' DIVERSA DA TUTTI GLI ALTRI ESTRATTORI (slice78)
#   Le mappe (overworld, citta') sono fatte di TILE RIPETUTE: poche centinaia
#   di coppie (tile CHR, sotto-palette) coprono migliaia di celle, e il lavoro
#   dell'estrattore e' proprio trovare quelle coppie. Qui no: questa e' UNA
#   IMMAGINE, la title card di FF1, e ogni cella e' diversa dalle altre.
#
#   Il TMS9918 in Mode 2 sa fare esattamente questo, ed e' il motivo per cui la
#   schermata ci sta senza compromessi: la tabella dei pattern e' divisa in tre
#   blocchi da 2KB, uno per terzo di schermo, e ogni blocco tiene 256 tile --
#   cioe' ESATTAMENTE quante celle ha un terzo di schermo (8 righe x 32).
#   Quindi ogni cella puo' avere una tile tutta sua e la name table diventa
#   banale: NT[i] = i & 0xFF. E' il "modo bitmap" del TMS.
#
#   Costo: 6144 byte di pattern + 6144 di colore = 12KB, che e' il motivo per
#   cui la scena si prende un banco tutto suo.
#
# SORGENTI (banco $0B del ROM, mappato a $8000)
#   $B400  data_BridgeCHR   128 tile 2bpp NES ($800 byte)
#   $BC00  data_BridgeNT    una name table intera (32x30 + 64 di attributi)
#   lut_BridgeBGPal (bank_0D.asm) le 16 tinte NES della schermata
#
#   I tile di indice >= 128 nella NT NON stanno in data_BridgeCHR: sono il
#   font e la cornice del riquadro, che sul NES `LoadMenuCHR` carica dopo e
#   che il gioco disegna a runtime. Qui diventano SFONDO -- il riquadro di
#   testo ce lo disegna il nostro overlay dove vuole lui.
#
# IL RITAGLIO: 30 righe NES -> 24 righe TMS
#   Si tolgono le prime `-TopRow` righe, che sono cielo pieno. Con il valore
#   di partenza (6) restano le righe NES 6-29, cioe' TUTTO quello che si vede:
#   il logo, la rupe con i quattro eroi, gli uccelli, il prato.
#
# I CREDITI: -DropNintendo / -DropSquare
#   Il "TM&(C) 1990 NINTENDO" e il "(C)1987 SQUARE" sono COTTI nell'immagine
#   come tutto il resto. Si tolgono riempiendo le loro celle col colore che
#   hanno intorno, e intorno c'e' tinta unita in tutti e due i casi -- prato
#   verde a sinistra, rupe nera a destra -- quindi non si ricostruisce niente
#   e non si vede la giuntura.
#
#   Il valore di partenza TOGLIE Nintendo e TIENE Square, ed e' una scelta, non
#   una svista: Nintendo ha pubblicato la versione NES e con questo port non
#   c'entra niente -- lasciare il suo marchio sarebbe un'attribuzione falsa.
#   Square ha scritto il gioco da cui questo port viene, e quella riga e' vera.

param(
    [string]$Root    = (Split-Path -Parent $PSScriptRoot),
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$TopRow     = 6,
    [bool]$DropNintendo = $true,
    [bool]$DropSquare   = $false,
    [string]$OutHdr  = 'src\data\bridge_scene.h',
    [string]$OutPng  = 'build\bridge_scene_tms.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$COLS = 32
$ROWS = 24

$b0B = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_0B.bin'))
$CHR_OFF = 0xB400 - 0x8000
$NT_OFF  = 0xBC00 - 0x8000

# lut_BridgeBGPal, bank_0D.asm. Si RICOPIA qui perche' e' una riga sola di
# .BYTE e leggerla dall'asm vorrebbe piu' codice del valore che protegge --
# ma se cambiasse, cambierebbe l'immagine in modo vistoso, non silenzioso.
$PAL = @(0x0F,0x00,0x02,0x30, 0x0F,0x3B,0x11,0x24, 0x0F,0x3B,0x0B,0x2B, 0x0F,0x00,0x0F,0x30)

# --- NES master color -> indice TMS9918 -------------------------------------
# Stessa base di extract_sm_colors.ps1 / extract_ow_colors.ps1. Le cinque voci
# in fondo sono NUOVE: sono le tinte che questa schermata usa e le mappe no.
$NES2TMS = @{
    0x0F = 1;   0x0D = 1;             # nero
    0x00 = 14;  0x10 = 14; 0x20 = 14; # grigi
    0x30 = 15;                        # bianco
    0x01 = 4;   0x11 = 4;  0x12 = 4;  # blu scuro
    0x21 = 5;   0x22 = 5;             # blu chiaro
    0x31 = 7;                         # ciano pallido
    0x19 = 12;                        # verde scuro
    0x1A = 2;                         # verde medio
    0x29 = 3;   0x2A = 3;             # verde chiaro
    # --- slice78, le tinte della title card ---
    0x02 = 4;                         # blu notte    -> blu scuro
    0x3B = 7;                         # celeste palli -> ciano chiaro (il cielo)
    0x24 = 13;                        # rosa carico  -> magenta (il logo)
    0x0B = 12;                        # verde cupo   -> verde scuro
    0x2B = 3;                         # verde chiaro -> verde chiaro (il prato)
}
$TMSLUM = @{ 0 = 0; 1 = 0; 2 = 110; 3 = 160; 4 = 70; 5 = 120; 6 = 90;
             7 = 175; 8 = 110; 9 = 145; 10 = 150; 11 = 200; 12 = 95;
             13 = 130; 14 = 190; 15 = 255 }
# Le tinte vere del TMS9918, che qui NON servono solo all'anteprima: il terzo
# colore di una riga si assegna per distanza RGB (vedi sotto).
$TMSRGB = @(
    @(0,0,0), @(0,0,0), @(33,200,66), @(94,220,120), @(84,85,237), @(125,118,252),
    @(212,82,77), @(66,235,245), @(252,85,84), @(255,121,120), @(212,193,84),
    @(230,206,128), @(33,176,59), @(201,91,186), @(204,204,204), @(255,255,255)
)
function Color-Dist([int]$a, [int]$b) {
    $dr = $TMSRGB[$a][0] - $TMSRGB[$b][0]
    $dg = $TMSRGB[$a][1] - $TMSRGB[$b][1]
    $db = $TMSRGB[$a][2] - $TMSRGB[$b][2]
    return $dr*$dr + $dg*$dg + $db*$db
}

# Otto pixel TMS -> (bits, colore) di una riga in Mode 2.
#
# DIFFERENZA VOLUTA da extract_sm_colors.ps1: quando una riga ha PIU' di due
# colori, il terzo si assegna per DISTANZA RGB, non per luminanza. Sulle mappe
# la luminanza va bene (i tile sono piccoli e i colori pochi); su un'IMMAGINE
# no, e il logo di FINAL FANTASY e' il controesempio perfetto:
#   cielo ciano (lum 175) + lettera blu (lum 70) + ombreggiatura rosa (lum 130)
# In luminanza il rosa dista 45 dal cielo e 60 dal blu, quindi finisce NEL
# CIELO -- e le lettere escono bucate, con i tratti mangiati riga per riga.
# In RGB il rosa (201,91,186) e' vicinissimo al blu (84,85,237) e lontano dal
# ciano (66,235,245): rientra nella lettera, che e' cio' che l'occhio si
# aspetta. Misurato: il logo passa da "sbrindellato" a pieno.
function Convert-RowToTms([int[]]$px) {
    $hist = @{}
    foreach ($c in $px) { if ($hist.ContainsKey($c)) { $hist[$c]++ } else { $hist[$c] = 1 } }
    $ranked = @($hist.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, @{Expression={$TMSLUM[[int]$_.Key]}; Descending=$true})
    $fg = [int]$ranked[0].Key
    if ($ranked.Count -gt 1) { $bg = [int]$ranked[1].Key } else { $bg = 1 }
    if ($fg -eq $bg) { $bg = 1 }
    $bits = 0
    for ($x = 0; $x -lt 8; $x++) {
        $c = $px[$x]
        if ($c -eq $fg)     { $isFg = $true }
        elseif ($c -eq $bg) { $isFg = $false }
        else {
            $isFg = ((Color-Dist $c $fg) -le (Color-Dist $c $bg))
        }
        if ($isFg) { $bits = $bits -bor (1 -shl (7 - $x)) }
    }
    return @([byte]$bits, [byte](($fg -shl 4) -bor $bg))
}

# =====================================================================
#  1. la schermata NES -> una griglia 256x240 di indici TMS
# =====================================================================
$img = New-Object 'int[]' (256*240)
$nt  = $b0B[$NT_OFF..($NT_OFF+0x3FF)]
# Le celle del RIQUADRO (tile >= 128, cioe' font e cornice che qui non ci
# sono): si segnano e si riempiono dopo, copiando dalla cella SOPRA. Riempirle
# con lo "sfondo della loro sotto-palette" era la prima stesura ed e' uscito un
# rettangolo NERO in mezzo al cielo -- le voci 0/4/8/12 della palette di questa
# schermata sono tutte $0F, cioe' nero, e il cielo e' la voce 1.
$isBox = New-Object 'bool[]' (32*30)

for ($ty = 0; $ty -lt 30; $ty++) {
    for ($tx = 0; $tx -lt 32; $tx++) {
        $tile = [int]$nt[$ty*32 + $tx]
        # attributo: 1 byte ogni 4x4 tile, 2 bit per quadrante 2x2
        $a = [int]$nt[960 + [Math]::Floor($ty/4)*8 + [Math]::Floor($tx/4)]
        $shift = ([Math]::Floor(($ty % 4)/2))*4 + ([Math]::Floor(($tx % 4)/2))*2
        $sub = ($a -shr $shift) -band 3
        if ($tile -ge 128) { $isBox[$ty*32 + $tx] = $true; continue }
        $base = $CHR_OFF + $tile*16
        for ($r = 0; $r -lt 8; $r++) {
            $p0 = [int]$b0B[$base+$r]
            $p1 = [int]$b0B[$base+$r+8]
            for ($c = 0; $c -lt 8; $c++) {
                $bit = 7 - $c
                $v = (($p0 -shr $bit) -band 1) -bor ((($p1 -shr $bit) -band 1) -shl 1)
                $nescol = $PAL[$sub*4 + $v]
                if (-not $NES2TMS.ContainsKey($nescol)) {
                    throw ("tinta NES 0x{0:X2} non mappata (tile {1}, sub {2})" -f $nescol, $tile, $sub)
                }
                $img[($ty*8+$r)*256 + $tx*8+$c] = [int]$NES2TMS[$nescol]
            }
        }
    }
}

# Le celle del riquadro, riempite DALL'ALTO IN BASSO copiando dalla cella
# sopra: la prima riga del riquadro copia il cielo vero, la seconda copia la
# prima, e cosi' via. Un ciclo solo e nessuna tinta da indovinare.
for ($ty = 0; $ty -lt 30; $ty++) {
    for ($tx = 0; $tx -lt 32; $tx++) {
        if (-not $isBox[$ty*32 + $tx]) { continue }
        if ($ty -eq 0) { throw "cella di riquadro sulla riga 0: non c'e' niente da cui copiare" }
        for ($r = 0; $r -lt 8; $r++) {
            for ($c = 0; $c -lt 8; $c++) {
                $img[($ty*8+$r)*256 + $tx*8+$c] = $img[(($ty-1)*8+7)*256 + $tx*8+$c]
            }
        }
    }
}

# =====================================================================
#  2. i crediti, tolti riempiendo col colore che hanno sopra
# =====================================================================
# Le due zone sono state misurate sull'immagine renderizzata, non indovinate:
# righe 26-27 tutte e due, x 2-9 (Nintendo, su prato) e x 23-28 (Square, su
# rupe). Il colore si prende dalla riga SUBITO SOPRA (la 25), che in tutte e
# due le colonne e' tinta unita -- prato a sinistra, rupe a destra. Prenderlo
# due righe piu' su era la prima stesura e pescava dalla riga 24, che e' la
# linea degli alberi: uscivano strisce verticali verdi e blu al posto del
# prato, cioe' un difetto che somiglia a una conversione di colore sbagliata.
function Clear-Credit([int]$x0, [int]$x1, [int]$y0, [int]$y1) {
    for ($cy = $y0; $cy -le $y1; $cy++) {
        for ($cx = $x0; $cx -le $x1; $cx++) {
            $srcY = ($y0 - 1)*8 + 4      # meta' della cella subito sopra
            for ($r = 0; $r -lt 8; $r++) {
                for ($c = 0; $c -lt 8; $c++) {
                    $img[($cy*8+$r)*256 + $cx*8+$c] = $img[$srcY*256 + $cx*8+$c]
                }
            }
        }
    }
}
if ($DropNintendo) { Clear-Credit 2 9 26 27;  Write-Host "credito NINTENDO rimosso (celle x2-9, righe 26-27)" }
if ($DropSquare)   { Clear-Credit 23 28 26 27; Write-Host "credito SQUARE rimosso (celle x23-28, righe 26-27)" }

# =====================================================================
#  3. ritaglio e conversione in tile TMS
# =====================================================================
if ($TopRow -lt 0 -or $TopRow + $ROWS -gt 30) { throw "-TopRow $TopRow fuori scala (0..6)" }

$pattern = New-Object 'byte[]' ($COLS*$ROWS*8)
$color   = New-Object 'byte[]' ($COLS*$ROWS*8)

for ($cy = 0; $cy -lt $ROWS; $cy++) {
    for ($cx = 0; $cx -lt $COLS; $cx++) {
        $cell = $cy*$COLS + $cx
        for ($r = 0; $r -lt 8; $r++) {
            $srcY = ($TopRow + $cy)*8 + $r
            $row = New-Object 'int[]' 8
            for ($c = 0; $c -lt 8; $c++) { $row[$c] = $img[$srcY*256 + $cx*8 + $c] }
            $pc = Convert-RowToTms $row
            $pattern[$cell*8 + $r] = $pc[0]
            $color[$cell*8 + $r]   = $pc[1]
        }
    }
}

# =====================================================================
#  4. anteprima PNG -- si GUARDA prima di compilare
# =====================================================================
$W = 256; $H = 192
$bmp  = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$stride = $data.Stride
$buf = New-Object 'byte[]' ($stride * $H)
for ($cy = 0; $cy -lt $ROWS; $cy++) {
    for ($cx = 0; $cx -lt $COLS; $cx++) {
        $cell = $cy*$COLS + $cx
        for ($r = 0; $r -lt 8; $r++) {
            $bits = [int]$pattern[$cell*8 + $r]
            $col  = [int]$color[$cell*8 + $r]
            $fg = ($col -shr 4) -band 0x0F
            $bg = $col -band 0x0F
            for ($c = 0; $c -lt 8; $c++) {
                $idx = if ((($bits -shr (7-$c)) -band 1) -eq 1) { $fg } else { $bg }
                $rgb = $TMSRGB[$idx]
                $o = ($cy*8+$r)*$stride + ($cx*8+$c)*3
                $buf[$o]   = [byte]$rgb[2]   # BGR
                $buf[$o+1] = [byte]$rgb[1]
                $buf[$o+2] = [byte]$rgb[0]
            }
        }
    }
}
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $buf.Length)
$bmp.UnlockBits($data)
$pngPath = Join-Path $Root $OutPng
$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "anteprima -> $pngPath"

# =====================================================================
#  5. header
# =====================================================================
function Format-ByteArray($arr) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $arr.Length; $i += 16) {
        $n = [Math]::Min(16, $arr.Length - $i)
        $row = @()
        for ($k = 0; $k -lt $n; $k++) { $row += ('0x{0:X2}' -f $arr[$i+$k]) }
        [void]$sb.AppendLine('    ' + ($row -join ',') + ',')
    }
    return $sb.ToString().TrimEnd()
}

$L = New-Object System.Collections.Generic.List[string]
function W($s) { [void]$L.Add($s) }
W '// AUTO-GENERATO da tools/extract_bridge_scene.ps1 -- non modificare a mano.'
W '//'
W '// La title card di FF1 (la schermata della scena del ponte) per TMS9918'
W '// Mode 2, come IMMAGINE: ogni cella dello schermo ha una tile tutta sua.'
W '// Funziona perche'' un terzo di schermo e'' 8x32 = 256 celle e la tabella'
W '// dei pattern ne tiene 256 per terzo -- il "modo bitmap" del TMS.'
W '//'
W ("// Ritaglio: righe NES {0}-{1} delle 30." -f $TopRow, ($TopRow+$ROWS-1))
W ("// Credito Nintendo: {0}. Credito Square: {1}." -f `
    $(if ($DropNintendo) {'RIMOSSO'} else {'tenuto'}), $(if ($DropSquare) {'RIMOSSO'} else {'tenuto'}))
W '//'
W '// Le due tabelle vanno in VRAM COSI'' COME SONO:'
W '//   pattern -> $0000 (6144 byte, tutti e tre i terzi)'
W '//   color   -> $2000 (6144 byte)'
W '// e la name table e'' NT[i] = i & 0xFF, che si genera con un ciclo.'
W '//'
W '// Header GATED: i dati escono solo con FF1_BRIDGE_DEFINE_DATA definito.'
W ''
W '#ifndef FF1_BRIDGE_SCENE_H'
W '#define FF1_BRIDGE_SCENE_H'
W ''
W ("#define FF1_BRIDGE_COLS   {0}" -f $COLS)
W ("#define FF1_BRIDGE_ROWS   {0}" -f $ROWS)
W ("#define FF1_BRIDGE_BYTES  {0}" -f ($COLS*$ROWS*8))
W ''
W '#ifdef FF1_BRIDGE_DEFINE_DATA'
W ''
W 'static const unsigned char ff1_bridge_pattern[FF1_BRIDGE_BYTES] = {'
W (Format-ByteArray $pattern)
W '};'
W ''
W 'static const unsigned char ff1_bridge_color[FF1_BRIDGE_BYTES] = {'
W (Format-ByteArray $color)
W '};'
W ''
W '#endif // FF1_BRIDGE_DEFINE_DATA'
W '#endif // FF1_BRIDGE_SCENE_H'

$outPath = Join-Path $Root $OutHdr
[System.IO.File]::WriteAllLines($outPath, $L)
Write-Host ("scritto {0} ({1} byte di pattern + {1} di colore)" -f $outPath, $pattern.Length)
