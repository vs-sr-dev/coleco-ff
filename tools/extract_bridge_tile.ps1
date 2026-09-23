# extract_bridge_tile.ps1 -- il PONTE dell'overworld, cotto sopra l'oceano.
#
# PERCHE' COTTO E NON UNO SPRITE (slice78)
#   Sul NES il ponte e' uno sprite 2x2 disegnato sopra la mappa
#   (DrawOWObj_BridgeCanal, bank_0F.asm:8598). Da noi NO, ed e' la stessa
#   decisione degli abitanti di slice76: il mapman occupa gia' QUATTRO sprite
#   sovrapposti e il TMS9918 ne mostra quattro per scanline. Il ponte da
#   sprite sarebbe il quinto e sparirebbe -- esattamente mentre ci si cammina
#   sopra, che e' l'unico momento in cui lo si guarda.
#
#   Cotto nel fondo invece non ha limiti, e il prezzo tipico della cottura
#   (l'oggetto non puo' muoversi) qui non si paga: il ponte sta fermo per
#   definizione, in una casella sola, OW (152,152).
#
# SORGENTI
#   bank_02.dat  offset 0       CHR NES dei tile di fondo
#   bank_02.dat  $9C00 + n*16   CHR degli oggetti OW; il ponte e' n = 4,6,5,7
#                               (lut_OWObjectSprTbl offset $08, additivo $10,
#                               ordine UL,DL,UR,DR di Draw2x2Sprite)
#   bank_00.dat  +$100..+$2FF   i 4 quadranti di ogni macrotile
#   bank_00.dat  +$300          palette del macrotile
#   bank_00.dat  +$380          le sotto-palette: BG a +$00, SPRITE a +$10
#
# IL FONDO E' IL MACROTILE VERO su cui il ponte poggia, non un azzurro
# inventato: si legge il macrotile $27 (l'oceano di quella casella) con la sua
# palette, e i pixel TRASPARENTI dello sprite lo lasciano vedere. Se il ponte
# fosse cotto su un fondo sbagliato, la giuntura con l'acqua intorno si
# vedrebbe -- ed e' lo stesso motivo per cui gli abitanti di slice76 sono
# cotti sul loro terreno e non su uno generico.

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$Out    = "$PSScriptRoot\..\src\ff1_bridge_tile.h",
    # Il macrotile su cui il ponte poggia. Non e' una scelta: e' quello che sta
    # a (152,152), letto dalla mappa.
    [int]$BaseMacro = 0x27,
    # Prima tile TMS libera del tileset OW. extract_ow_colors.ps1 ne usa 236,
    # e si ferma con un errore se ne servissero piu' di 256: qui si controlla
    # che le quattro ci stiano ancora.
    [int]$TileBase  = 236
)

$ErrorActionPreference = 'Stop'

$b00 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_00.dat'))
$b02 = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_02.dat'))

$tsa     = @($b00[0x100..0x17F], $b00[0x180..0x1FF], $b00[0x200..0x27F], $b00[0x280..0x2FF])
$tsaAttr = $b00[0x300..0x37F]
$mapPal  = $b00[0x380..0x3AF]

$OBJ_CHR = 0x9C00 - 0x8000
# lut_OWObjectSprTbl offset $08: UL, DL, UR, DR.
$BRIDGE_UL = 4; $BRIDGE_DL = 6; $BRIDGE_UR = 5; $BRIDGE_DR = 7
$SPR_SUBPAL = 3

$NES2TMS = @{
    0x0F = 1;   0x0D = 1;
    0x00 = 14;  0x10 = 14; 0x20 = 14;
    0x30 = 15;
    0x01 = 4;   0x11 = 4;  0x12 = 4;
    0x21 = 5;   0x22 = 5;
    0x31 = 7;
    0x15 = 6;   0x16 = 8;  0x26 = 9; 0x36 = 9;
    0x18 = 10;  0x27 = 10;
    0x28 = 11;  0x37 = 11;
    0x19 = 12;
    0x1A = 2;
    0x29 = 3;   0x2A = 3;
}
$TMSLUM = @{ 0 = 0; 1 = 0; 2 = 110; 3 = 160; 4 = 70; 5 = 120; 6 = 90;
             7 = 175; 8 = 110; 9 = 145; 10 = 150; 11 = 200; 12 = 95;
             13 = 130; 14 = 190; 15 = 255 }

function Get-TmsColor([int]$nes) {
    $key = $nes -band 0x3F
    if ($NES2TMS.ContainsKey($key)) { return [int]$NES2TMS[$key] }
    throw ("colore NES 0x{0:X2} non mappato" -f $key)
}

# =====================================================================
#  1. il fondo: il macrotile dell'oceano, 16x16 pixel in colori TMS
# =====================================================================
$bgPal = [int]$tsaAttr[$BaseMacro] -band 3
$bgTms = New-Object int[] 4
for ($c = 0; $c -lt 4; $c++) { $bgTms[$c] = Get-TmsColor ([int]$mapPal[$bgPal*4 + $c]) }

# I quattro quadranti nell'ordine di tsa: UL, UR, DL, DR.
$quadPos = @(@(0,0), @(8,0), @(0,8), @(8,8))
$img = New-Object int[] (16*16)
for ($q = 0; $q -lt 4; $q++) {
    $tid = [int]$tsa[$q][$BaseMacro]
    $ox = $quadPos[$q][0]; $oy = $quadPos[$q][1]
    for ($r = 0; $r -lt 8; $r++) {
        $p0 = [int]$b02[$tid*16 + $r]
        $p1 = [int]$b02[$tid*16 + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $v = ((($p0 -shr $bit) -band 1)) -bor ((($p1 -shr $bit) -band 1) -shl 1)
            $img[($oy+$r)*16 + $ox+$c] = $bgTms[$v]
        }
    }
}

# =====================================================================
#  2. il ponte sopra, dove non e' trasparente
# =====================================================================
# La maschera serve alla riduzione di colore: fg si calcola sui pixel DEL
# PONTE e bg su quelli DELL'ACQUA, senza mescolarli. E' la lezione degli
# abitanti di slice76 -- la dominante generica assorbirebbe il contorno del
# ponte nell'acqua e la giuntura si vedrebbe.
$sprTms = New-Object int[] 4
for ($c = 0; $c -lt 4; $c++) { $sprTms[$c] = Get-TmsColor ([int]$mapPal[0x10 + $SPR_SUBPAL*4 + $c]) }

$isBridge = New-Object bool[] (16*16)
# ordine dello sprite: UL, DL, UR, DR (Draw2x2Sprite), posizioni corrispondenti
$sprTiles = @($BRIDGE_UL, $BRIDGE_DL, $BRIDGE_UR, $BRIDGE_DR)
$sprPos   = @(@(0,0), @(0,8), @(8,0), @(8,8))
for ($k = 0; $k -lt 4; $k++) {
    $base = $OBJ_CHR + $sprTiles[$k]*16
    $ox = $sprPos[$k][0]; $oy = $sprPos[$k][1]
    for ($r = 0; $r -lt 8; $r++) {
        $p0 = [int]$b02[$base + $r]
        $p1 = [int]$b02[$base + 8 + $r]
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $v = ((($p0 -shr $bit) -band 1)) -bor ((($p1 -shr $bit) -band 1) -shl 1)
            if ($v -eq 0) { continue }        # trasparente: resta l'acqua
            $img[($oy+$r)*16 + $ox+$c] = $sprTms[$v]
            $isBridge[($oy+$r)*16 + $ox+$c] = $true
        }
    }
}

# =====================================================================
#  3. riduzione a Mode 2, DUE STRATI SEPARATI
# =====================================================================
function Get-Dominant([int[]]$vals) {
    if ($vals.Count -eq 0) { return -1 }
    $hist = @{}
    foreach ($c in $vals) { if ($hist.ContainsKey($c)) { $hist[$c]++ } else { $hist[$c] = 1 } }
    $ranked = @($hist.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, @{Expression={$TMSLUM[[int]$_.Key]}; Descending=$true})
    return [int]$ranked[0].Key
}

# I quattro tile TMS escono nell'ordine dei QUADRANTI della mappa (UL,UR,DL,DR),
# non in quello dello sprite: e' l'ordine in cui il disegno della overworld li
# chiede, e tenerne uno solo toglie di mezzo una conversione.
$pattern = New-Object byte[] 32
$color   = New-Object byte[] 32
for ($q = 0; $q -lt 4; $q++) {
    $ox = $quadPos[$q][0]; $oy = $quadPos[$q][1]
    for ($r = 0; $r -lt 8; $r++) {
        $fgPx = New-Object System.Collections.ArrayList
        $bgPx = New-Object System.Collections.ArrayList
        for ($c = 0; $c -lt 8; $c++) {
            $idx = ($oy+$r)*16 + $ox+$c
            if ($isBridge[$idx]) { [void]$fgPx.Add($img[$idx]) } else { [void]$bgPx.Add($img[$idx]) }
        }
        $bits = 0
        if ($bgPx.Count -eq 0) {
            # RIGA TUTTA PONTE: qui non c'e' acqua da tenere separata, quindi
            # i due colori si possono spendere sui colori VERI dello sprite --
            # bianco del tavolato e nero delle assi. E' cio' che fa la
            # differenza fra un ponte e una MACCHIA BIANCA: le righe di mezzo
            # (quelle che non toccano l'acqua) sono la maggioranza, e senza
            # questo ramo il disegno del ROM si perdeva tutto li'.
            $fg = Get-Dominant $fgPx.ToArray()
            $bg = -1
            for ($c = 0; $c -lt 8; $c++) {
                $v = $img[($oy+$r)*16 + $ox+$c]
                if ($v -ne $fg) { $bg = $v }
            }
            if ($bg -lt 0) { $bg = 1 }
            for ($c = 0; $c -lt 8; $c++) {
                if ($img[($oy+$r)*16 + $ox+$c] -eq $fg) { $bits = $bits -bor (1 -shl (7-$c)) }
            }
        } else {
            # RIGA MISTA: i due strati non si mescolano MAI -- fg dai pixel del
            # ponte, bg da quelli dell'acqua. E' la lezione degli abitanti di
            # slice76: la dominante generica assorbirebbe il bordo del ponte
            # nell'acqua e la giuntura si vedrebbe.
            $fg = Get-Dominant $fgPx.ToArray()
            $bg = Get-Dominant $bgPx.ToArray()
            if ($fg -lt 0) { $fg = 1 }
            if ($fg -eq $bg) { if ($bg -eq 1) { $fg = 15 } else { $bg = 1 } }
            for ($c = 0; $c -lt 8; $c++) {
                if ($isBridge[($oy+$r)*16 + $ox+$c]) { $bits = $bits -bor (1 -shl (7-$c)) }
            }
        }
        $pattern[$q*8 + $r] = [byte]$bits
        $color[$q*8 + $r]   = [byte](($fg -shl 4) -bor $bg)
    }
}

# =====================================================================
#  4. header
# =====================================================================
if ($TileBase + 4 -gt 256) { throw "le 4 tile del ponte non ci stanno: TileBase $TileBase" }

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
W '// AUTO-GENERATO da tools/extract_bridge_tile.ps1 -- non modificare a mano.'
W '//'
W '// Il ponte dell''overworld, COTTO sopra il macrotile dell''oceano su cui'
W '// poggia. Quattro tile TMS nell''ordine dei quadranti della mappa:'
W '//   +0 = alto-sinistra   +1 = alto-destra   +2 = basso-sinistra   +3 = basso-destra'
W '//'
W '// Perche'' cotto e non uno sprite: il mapman occupa gia'' i quattro sprite'
W '// che il TMS9918 mostra per scanline, e il ponte sarebbe il quinto --'
W '// sparirebbe proprio mentre ci si cammina sopra. Stessa scelta degli'
W '// abitanti di slice76.'
W '//'
W ("// Macrotile di fondo: 0x{0:X2}. Prima tile TMS: {1}." -f $BaseMacro, $TileBase)
W '//'
W '// Header GATED: i dati escono solo con FF1_BRIDGE_TILE_DEFINE_DATA definito'
W '// (lo fa src/owgfx_bank.c, che possiede il banco della grafica OW).'
W ''
W '#ifndef FF1_BRIDGE_TILE_H'
W '#define FF1_BRIDGE_TILE_H'
W ''
W ("#define FF1_BRIDGE_TILE_BASE  {0}" -f $TileBase)
W ("#define FF1_BRIDGE_MACRO      0x{0:X2}" -f $BaseMacro)
W ''
W '#ifdef FF1_BRIDGE_TILE_DEFINE_DATA'
W ''
W 'static const unsigned char ff1_bridge_tile_pattern[32] = {'
W (Format-ByteArray $pattern)
W '};'
W ''
W 'static const unsigned char ff1_bridge_tile_color[32] = {'
W (Format-ByteArray $color)
W '};'
W ''
W '#endif // FF1_BRIDGE_TILE_DEFINE_DATA'
W '#endif // FF1_BRIDGE_TILE_H'

[System.IO.File]::WriteAllLines($Out, $L)
Write-Host ("scritto {0} (4 tile a partire da {1})" -f $Out, $TileBase)

# --- anteprima ASCII, per vedere subito se il ponte e' venuto -----------------
Write-Host ''
Write-Host 'anteprima (# = ponte, . = acqua):'
for ($r = 0; $r -lt 16; $r++) {
    $line = '  '
    for ($c = 0; $c -lt 16; $c++) { $line += $(if ($isBridge[$r*16+$c]) { '#' } else { '.' }) }
    Write-Host $line
}
