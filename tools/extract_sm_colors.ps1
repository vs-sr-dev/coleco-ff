# extract_sm_colors.ps1 -- grafica a COLORI VERI per una mappa standard.
#
# Gemello di extract_ow_colors.ps1 (slice47), stesso schema, sorgenti diverse.
# Prima di usarlo: .\analyze_sm_colors.ps1, che MISURA se le coppie
# (tile, palette) stanno nei 256 tile TMS. Per Coneria sono 93 e nessun tile
# CHR e' usato con piu' di una palette -- la citta' e' partizionata per
# palette anche meglio dell'overworld.
#
# SORGENTI (le stesse di extract_sm_coneria.ps1, piu' le palette)
#   bank_00.dat  $0400 + T*128   SMTilesetAttr   palette per macrotile
#                $1000 + T*512   SMTilesetTSA    4 blocchi CONTIGUI da 128,
#                                                NON interlacciati [[ff1-sm-tsa-layout]]
#                $2000 + T*$30   lut_SMPalettes  16 byte BG + 16 sprite + 16
#   bank_03.dat  T*$800          CHR 2bpp, 128 tile da 16 byte
#   bank_04..07  bitstream RLE delle mappe (puntatori a offset 0 di bank_04)
#
# PERCHE' LA MAPPA ESCE DA QUI E NON DA extract_sm_coneria.ps1
# Sono 4096 byte, e insieme a pattern+color+TSA (4608) devono stare nello
# STESSO banco: durante il disegno della citta' si mappa un banco solo. Averli
# in due header generati da due strumenti diversi vorrebbe dire poterli
# disallineare -- e un disallineamento fra mappa e TSA rimappata non da'
# errore, da' una citta' con la geometria giusta e i tile sbagliati (e' gia'
# successo in slice40, vedi [[ff1-sm-tsa-layout]]).

param(
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OutHdr  = "$PSScriptRoot\..\src\ff1_towngfx.h",
    [int]$Tileset = 0,
    [int]$MapId   = 0,
    # PREFISSO dei nomi generati, in due forme: MAIUSCOLA per le costanti e
    # minuscola per gli array. Da slice77 una mappa = un banco = un header, e
    # due mappe non possono chiamare le proprie tabelle allo stesso modo --
    # finirebbero nello stesso spazio di nomi appena una slice le include tutte
    # e due per prenderne le costanti.
    #   Coneria citta'   -> TOWNGFX   / towngfx    (banco 15, il nome storico)
    #   Coneria castello -> CASTLEGFX / castlegfx  (banco 17)
    [string]$Prefix = 'TOWNGFX',
    # L'INGRESSO. Di norma e' un teletrasporto d'ingresso (lut_EntrTele), che
    # NON e' indicizzato per numero di mappa ma per ID DI TELETRASPORTO: la
    # voce 1 e' Coneria citta', la 9 il castello, la 13 il Temple of Fiends.
    #   Coneria citta'    -> -TeleId 1   -> (16,23)
    #   Coneria castello  -> -TeleId 9   -> (12,35)
    #   Temple of Fiends  -> -TeleId 13  -> (20,30)
    # Un PIANO SUPERIORE non ha un teletrasporto d'ingresso: ci si arriva da un
    # teletrasporto NORMALE dentro un'altra mappa, e le coordinate stanno nella
    # sua tabella. Per quei casi si passano a mano.
    #   Coneria castello 2F -> -EntryX 12 -EntryY 18  (norm 0, da (12,18) di 1F)
    [int]$TeleId = 1,
    [int]$EntryX = -1,
    [int]$EntryY = -1
)

$ErrorActionPreference = 'Stop'

$PFX  = $Prefix.ToUpper()      # costanti:  FF1_<PFX>_*
$pfxl = $Prefix.ToLower()      # array:     ff1_<pfxl>_*


function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }
$b00 = ReadBank 'bank_00.dat'
$b03 = ReadBank 'bank_03.dat'
# bank_02 = BANK_MAPCHR: la CHR degli oggetti di mappa (lut_MapObjCHR = $A200,
# $100 byte = 16 tile per id grafico). Serve da slice76: gli NPC di una citta'
# non sono sprite ma TILE DI FONDO, cotte qui sopra il terreno su cui stanno.
$b02 = ReadBank 'bank_02.dat'

# I nomi sono lunghi APPOSTA. PowerShell non distingue maiuscole e minuscole,
# quindi una base chiamata $PAL verrebbe silenziosamente sovrascritta da un
# indice di palette chiamato $pal nel ciclo piu' sotto -- e le palette si
# leggerebbero dall'offset 0..3 del banco invece che dalla tabella. Il sintomo
# e' una pioggia di "colore NES non mappato": e' costato un giro. Stessa
# famiglia di [[powershell-typed-param-shadow]] e della nota su $src/$SRC in
# build_all.ps1.
# Il tileset NON si passa a mano: lo dice la mappa (lut_Tilesets a $2CC0). Se
# l'argomento -Tileset non concorda, e' un errore, non una scelta.
$tilesetFromMap = [int]$b00[0x2CC0 + $MapId]
if ($tilesetFromMap -ne $Tileset) {
    throw "la mappa $MapId usa il tileset $tilesetFromMap, non $Tileset"
}
# Ingresso: EntrTele ID 01 e' la porta di Coneria (X a $2C00, Y a $2C20,
# mappa di destinazione a $2C40).
if ($EntryX -ge 0 -and $EntryY -ge 0) {
    $entryX = $EntryX
    $entryY = $EntryY
} else {
    $entryX = [int]$b00[0x2C00 + $TeleId]
    $entryY = [int]$b00[0x2C20 + $TeleId]
    $entryMap = [int]$b00[0x2C40 + $TeleId]
    if ($entryMap -ne $MapId) {
        throw "il teletrasporto d'ingresso $TeleId porta alla mappa $entryMap, non alla $MapId"
    }
}
Write-Host ("ingresso: ({0},{1})" -f $entryX, $entryY)

$ATTR_BASE = 0x0400 + $Tileset * 128
$PROP_BASE = 0x0800 + $Tileset * 256
$TSA_BASE  = 0x1000 + $Tileset * 512
$PAL_BASE  = 0x2000 + $Tileset * 0x30
$CHR_BASE  = $Tileset * 0x800

# SMTilesetProp: 2 byte per macrotile, collisioni e porte. Esce da QUI e non
# da extract_sm_coneria.ps1 per la stessa ragione della mappa -- durante il
# gioco in citta' si mappa un banco solo, e queste tre cose (mappa, TSA,
# proprieta') si leggono insieme. Tenerle in header diversi vuol dire poterle
# disallineare, e un disallineamento fra mappa e proprieta' non da' errore:
# da' un muro dove si passa e un passaggio dentro una casa.
$prop = New-Object byte[] 256
[Array]::Copy($b00, $PROP_BASE, $prop, 0, 256)

# --- NES master color -> indice TMS9918 -------------------------------------
# Base condivisa con extract_ow_colors.ps1, cosi' la citta' e l'overworld non
# rendono lo stesso colore in due modi. Le tre voci in fondo sono NUOVE: sono
# i colori che il tileset 0 usa e la overworld no.
$NES2TMS = @{
    0x0F = 1;   0x0D = 1;             # nero
    0x00 = 14;  0x10 = 14; 0x20 = 14; # grigi
    0x30 = 15;                        # bianco
    0x01 = 4;   0x11 = 4;  0x12 = 4;  # blu scuro
    0x21 = 5;   0x22 = 5;             # blu chiaro
    0x31 = 7;                         # ciano pallido
    0x15 = 6;   0x16 = 8;  0x26 = 9; 0x36 = 9;
    0x18 = 10;  0x27 = 10;            # oliva / sabbia
    0x28 = 11;  0x37 = 11;            # crema / sabbia chiara
    0x19 = 12;                        # verde scuro
    0x1A = 2;                         # verde medio (erba)
    0x29 = 3;   0x2A = 3;             # verde chiaro
    0x2C = 7;                         # ciano chiaro (acqua della citta')
    # slice76: i colori che compaiono SOLO nelle sotto-palette SPRITE, cioe'
    # nei vestiti degli abitanti. Nessuno di questi e' mai usato da un tile di
    # fondo, ed e' per questo che fino a slice75 non servivano.
    0x25 = 9;                         # rosa carico -> rosso chiaro
    0x14 = 13;                        # viola       -> magenta
    0x1C = 4;                         # ciano scuro -> blu scuro TMS: il ciano
                                      #   del TMS e' troppo chiaro per fare
                                      #   l'ombra dell'acqua
}
$TMSLUM = @{ 0 = 0; 1 = 0; 2 = 110; 3 = 160; 4 = 70; 5 = 120; 6 = 90;
             7 = 175; 8 = 110; 9 = 145; 10 = 150; 11 = 200; 12 = 95;
             13 = 130; 14 = 190; 15 = 255 }

# Otto pixel TMS (indici 0-15) -> la coppia (bits, colore) di una riga in
# Mode 2. E' la "dominante per riga" di [[per-row-dominant-pattern]], estratta
# in una funzione da slice76 perche' adesso la usano DUE produttori: i tile del
# tileset e i tile degli NPC cotti sopra il terreno. Averla in due copie
# significherebbe poter rendere lo stesso pixel in due modi, e la giuntura fra
# un NPC e il terreno e' esattamente il posto in cui si vedrebbe.
function Convert-RowToTms([int[]]$px) {
    $hist = @{}
    foreach ($c in $px) { if ($hist.ContainsKey($c)) { $hist[$c]++ } else { $hist[$c] = 1 } }
    # fg = piu' frequente, bg = secondo. Parita' risolta dal piu' chiaro,
    # cosi' il risultato non dipende dall'ordine di enumerazione.
    $ranked = @($hist.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, @{Expression={$TMSLUM[[int]$_.Key]}; Descending=$true})
    $fg = [int]$ranked[0].Key
    if ($ranked.Count -gt 1) { $bg = [int]$ranked[1].Key } else { $bg = 1 }
    if ($fg -eq $bg) { $bg = 1 }

    $bits = 0
    for ($x = 0; $x -lt 8; $x++) {
        $c = $px[$x]
        if ($c -eq $fg)      { $isFg = $true }
        elseif ($c -eq $bg)  { $isFg = $false }
        else {
            $isFg = ([Math]::Abs($TMSLUM[$c] - $TMSLUM[$fg]) -le [Math]::Abs($TMSLUM[$c] - $TMSLUM[$bg]))
        }
        if ($isFg) { $bits = $bits -bor (1 -shl (7 - $x)) }
    }
    return @([byte]$bits, [byte](($fg -shl 4) -bor $bg))
}

# La dominante di una lista di pixel: piu' frequente, parita' al piu' chiaro.
function Get-Dominant([int[]]$px) {
    $hist = @{}
    foreach ($c in $px) { if ($hist.ContainsKey($c)) { $hist[$c]++ } else { $hist[$c] = 1 } }
    $ranked = @($hist.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, @{Expression={$TMSLUM[[int]$_.Key]}; Descending=$true})
    return [int]$ranked[0].Key
}

# =====================================================================
#  La riga di un NPC: la dominante si calcola SUI DUE STRATI SEPARATI
# =====================================================================
# PERCHE' NON BASTA Convert-RowToTms. Su una riga di abitante ci sono TRE
# colori almeno -- il terreno, il contorno nero e il corpo -- e in Mode 2 ne
# sopravvivono due. La dominante generica sceglie i due piu' frequenti e
# assegna il terzo per vicinanza di luminanza: su prato o su selciato chiaro il
# terzo e' quasi sempre il **contorno nero**, che finisce assorbito dal corpo.
# Il risultato e' una figura giusta di forma e ingrassata di un pixel per lato,
# con il contorno sparito -- cioe' esattamente "riconoscibile ma sbagliata".
#
# Qui invece i due strati non si mescolano MAI:
#   fg = dominante fra i pixel DELLO SPRITE   (quelli con valore 1-3)
#   bg = dominante fra i pixel DEL TERRENO    (quelli trasparenti)
# e il bit dice semplicemente "questo pixel e' dello sprite". La giuntura fra
# abitante e terreno diventa esatta -- niente bava, niente ingrassamento -- e
# il terreno sotto resta quello vero.
#
# COSA SI PERDE, ed e' inevitabile: il dettaglio DENTRO la figura. Ogni riga ha
# un colore solo per lo sprite. Ma non e' una silhouette piatta: la dominante e'
# PER RIGA, quindi le righe della testa escono col colore della testa e quelle
# del corpo con quello dei vestiti -- e' la stessa idea di
# [[per-row-dominant-pattern]] applicata allo strato invece che al tile.
# IL CONTORNO NON E' CORPO: E' SFONDO. Un abitante di FF1 e' fatto di tre
# valori -- 1 contorno nero, 2 vestito, 3 incarnato -- e il contorno non sta
# solo INTORNO alla figura: separa la testa dal busto, le braccia dal corpo, e
# disegna gli occhi. Metterlo insieme al vestito (che e' quello che succede
# prendendo "tutti i pixel dello sprite" come primo piano) riempie la figura di
# un colore solo e ogni riga diventa una BARRA ORIZZONTALE: la figura si legge
# come un blocco stirato, non come una persona.
#
# Qui il contorno prende il colore del TERRENO. E' la scelta che restituisce
# alla figura la sua struttura interna: gli occhi, lo stacco fra testa e busto e
# la divisione delle gambe ricompaiono come righe del colore di sfondo. Sui
# bordi esterni il contorno si confonde col prato, che e' esattamente cio' che
# il contorno fa gia' sul NES -- li' e' nero perche' il NES ha quattro colori,
# qui ne ha due e il nero e' il meno importante dei tre.
#
#   classe 0 = terreno            -> sfondo
#   classe 1 = contorno (valore 1) -> sfondo
#   classe 2 = vestito/incarnato   -> primo piano
#
# Righe di solo contorno (la cima del cappello) non avrebbero primo piano: li'
# il contorno TORNA a essere figura, o la testa uscirebbe tagliata.
#
# LO SFONDO SI CALCOLA SUL TERRENO INTERO, NON SUI PIXEL SCOPERTI. E' costato
# un giro: prendendo la dominante dei soli pixel di terreno RIMASTI VISIBILI, su
# certe righe restavano tre o quattro pixel del valore 0 del tile d'erba -- che
# nella palette di Coneria e' $0F, cioe' NERO -- e lo sfondo di quella riga
# usciva nero. A schermo: barre nere che sporgono a destra e a sinistra della
# figura, come se l'abitante avesse un'ombra sbagliata. Il tile d'erba accanto
# quel nero non lo mostra mai, perche' la sua dominante e' il verde.
# Calcolandola su tutti e otto i pixel del terreno si ottiene lo STESSO colore
# che il tile di citta' vicino mostra, e la giuntura sparisce.
function Convert-NpcRowToTms([int[]]$px, [int[]]$cls, [int[]]$gpx) {
    $body = @(); $edge = @()
    for ($x = 0; $x -lt 8; $x++) {
        if     ($cls[$x] -eq 2) { $body += $px[$x] }
        elseif ($cls[$x] -eq 1) { $edge += $px[$x] }
    }
    # Riga senza sprite: e' terreno e basta, e la regola generale va benissimo.
    if ($body.Count -eq 0 -and $edge.Count -eq 0) { return (Convert-RowToTms $px) }

    if ($body.Count -eq 0) { $fg = Get-Dominant $edge }
    else                   { $fg = Get-Dominant $body }

    $bg = Get-Dominant $gpx

    # Figura e fondo dello stesso colore: su quella riga sparirebbe.
    if ($fg -eq $bg) { if ($fg -eq 1) { $bg = 14 } else { $bg = 1 } }

    # Primo piano = TUTTI i pixel dell'abitante, contorno compreso. La figura e'
    # quindi una sagoma piena grande quanto quella del NES; il contorno nero ci
    # va SOPRA come sprite (vedi il blocco degli sprite di contorno piu' sotto).
    # E' la stessa divisione del lavoro di [[oam-accent-pattern]]: il fondo
    # porta la forma, lo sprite porta il colore che al fondo non entra.
    $bits = 0
    for ($x = 0; $x -lt 8; $x++) {
        if ($cls[$x] -ne 0) { $bits = $bits -bor (1 -shl (7 - $x)) }
    }
    return @([byte]$bits, [byte](($fg -shl 4) -bor $bg))
}

function Get-TmsColor([int]$nes) {
    $key = $nes -band 0x3F
    if ($NES2TMS.ContainsKey($key)) { return [int]$NES2TMS[$key] }
    Write-Host ("  ATTENZIONE: colore NES 0x{0} non mappato -> uso nero" -f $key.ToString('X2')) -ForegroundColor Yellow
    return 1
}

# --- mappa: decompressione RLE ----------------------------------------------
# DecompressMap, bank_0F.asm $D04F:
#   $00-$7F macrotile letterale
#   $80-$FE intestazione di corsa (tile = byte & $7F), byte dopo = lunghezza
#           (0 = 256)
#   $FF     fine mappa
$sm = New-Object byte[] (16384 * 4)
$i = 0
foreach ($n in 'bank_04.dat','bank_05.dat','bank_06.dat','bank_07.dat') {
    [Array]::Copy((ReadBank $n), 0, $sm, $i, 16384); $i += 16384
}
$lo = [int]$sm[$MapId*2]; $hi = [int]$sm[$MapId*2+1]
$src = (($hi -shr 6) -band 3) * 16384 + (((($hi -band 0x3F) -bor 0x80) -shl 8) -bor $lo) - 0x8000

$map = New-Object byte[] 4096
$n = 0
while ($n -lt 4096) {
    $v = $sm[$src]; $src++
    if ($v -eq 0xFF) { break }
    if ($v -lt 0x80) { $map[$n] = $v; $n++ }
    else {
        $t = [byte]($v -band 0x7F); $len = [int]$sm[$src]; $src++
        if ($len -eq 0) { $len = 256 }
        for ($k = 0; $k -lt $len -and $n -lt 4096; $k++) { $map[$n] = $t; $n++ }
    }
}
if ($n -ne 4096) { throw "mappa $MapId decompressa a $n macrotile, attesi 4096" }

# --- assegnazione degli ID: una coppia (tile, palette) = un tile TMS --------
# Solo i macrotile che la MAPPA usa davvero: il tileset ne definisce 128, ma
# pagare anche quelli mai disegnati sprecherebbe tile in un budget da 256.
$used = @{}
foreach ($m in $map) { $used[[int]$m] = 1 }

$comboId   = @{}
$comboList = New-Object System.Collections.ArrayList
# Ogni New-Object fra parentesi: senza, la virgola si lega come lista di
# argomenti di New-Object invece che come elementi dell'array.
$tsaNew = @((New-Object byte[] 128), (New-Object byte[] 128), (New-Object byte[] 128), (New-Object byte[] 128))

for ($m = 0; $m -lt 128; $m++) {
    if (-not $used.ContainsKey($m)) { continue }
    $pal = [int]$b00[$ATTR_BASE + $m] -band 3
    $q = 0
    foreach ($qoff in 0, 128, 256, 384) {
        $tid = [int]$b00[$TSA_BASE + $qoff + $m]
        $key = "$tid/$pal"
        if (-not $comboId.ContainsKey($key)) {
            $id = $comboList.Count
            if ($id -gt 255) { throw "sforato il limite di 256 tile TMS: rifare analyze_sm_colors.ps1" }
            $comboId[$key] = $id
            [void]$comboList.Add(@{ Tile = $tid; Pal = $pal })
        }
        $tsaNew[$q][$m] = [byte]$comboId[$key]
        $q++
    }
}
$nCombo = $comboList.Count
Write-Host ("coppie (tile,palette) -> tile TMS: {0} (max 256)" -f $nCombo)

# --- pattern + colore per ogni tile TMS -------------------------------------
$pattern = New-Object byte[] (256 * 8)
$color   = New-Object byte[] (256 * 8)

for ($id = 0; $id -lt $nCombo; $id++) {
    $tid = [int]$comboList[$id].Tile
    $pal = [int]$comboList[$id].Pal

    $palTms = New-Object int[] 4
    for ($c = 0; $c -lt 4; $c++) { $palTms[$c] = Get-TmsColor ([int]$b00[$PAL_BASE + $pal*4 + $c]) }

    for ($row = 0; $row -lt 8; $row++) {
        $p0 = [int]$b03[$CHR_BASE + $tid*16 + $row]
        $p1 = [int]$b03[$CHR_BASE + $tid*16 + 8 + $row]

        $px = New-Object int[] 8
        for ($x = 0; $x -lt 8; $x++) {
            $bit = 7 - $x
            $ci = ((($p0 -shr $bit) -band 1)) -bor ((($p1 -shr $bit) -band 1) -shl 1)
            $px[$x] = $palTms[$ci]
        }

        $rowOut = Convert-RowToTms $px
        $pattern[$id*8 + $row] = $rowOut[0]
        $color[$id*8 + $row]   = $rowOut[1]
    }
}
for ($id = $nCombo; $id -lt 256; $id++) {
    for ($row = 0; $row -lt 8; $row++) { $pattern[$id*8 + $row] = 0; $color[$id*8 + $row] = 0x11 }
}

# =====================================================================
#  NPC: tile di FONDO cotte sopra il terreno (slice76)
# =====================================================================
# PERCHE' NON SPRITE, che sarebbe la scelta ovvia. Il mapman del giocatore
# occupa QUATTRO sprite sovrapposti ([[mapman-4layer]]) e il TMS9918 ne mostra
# quattro per scanline: un NPC accanto al giocatore cadrebbe fuori proprio
# quando gli si sta parlando -- cioe' sempre, perche' per parlare bisogna
# essergli di fianco. Come tile di fondo invece non c'e' nessun limite, il
# colore e' quello vero, e la griglia coincide con il passo discreto del
# movimento (1 tocco = 1 macrotile, [[movement-discrete-tile]]).
#
# IL PREZZO: un NPC cosi' NON PUO' CAMMINARE. Le sue quattro tile contengono
# il terreno su cui sta -- spostarlo vorrebbe dire ricuocerle per ogni
# macrotile calpestabile. Sul NES gli abitanti vagano; qui stanno fermi.
# Deviazione dichiarata in docs/Coleco_improvements.md.
#
# LA POSA: `lut_2x2MapObj_Down` frame 0 (bank_0F.asm), cioe' i tile 0-3 del
# blocco da 16, con attributo 2 per la meta' alta e 3 per la bassa -- due
# SOTTO-PALETTE SPRITE diverse nella stessa figura, che e' il motivo per cui
# la conversione va fatta per quadrante e non per figura intera.
$NPC_MAX      = 15
$OBJ_BASE     = 0x3400 + $MapId * 48      # lut_MapObjects + map*$30
$OBJGFX_BASE  = 0x2E00                    # lut_MapObjGfx ($AE00 nel banco 0)
$OBJCHR_BASE  = 0x2200                    # lut_MapObjCHR ($A200 nel banco 2)
$NPC_TILE_BASE = 96                       # prima tile TMS riservata agli NPC

if ($nCombo -gt $NPC_TILE_BASE) {
    # ${} obbligatorie: un ':' subito dopo il nome di una variabile PowerShell
    # lo interpreta come prefisso di drive e il file non si parsa nemmeno.
    throw ("il tileset usa $nCombo tile TMS e gli NPC cominciano a ${NPC_TILE_BASE}: " +
           "si sovrappongono. Rivedere la mappa dei tile in slice76.")
}

$npcPattern = New-Object byte[] ($NPC_MAX * 4 * 8)
$npcColor   = New-Object byte[] ($NPC_MAX * 4 * 8)
# Lo sprite di CONTORNO: 32 byte per slot, cioe' uno sprite 16x16 del TMS.
# Nel generatore i quattro quadranti stanno in ordine TL, BL, TR, BR (per
# COLONNE, non per righe) -- e' il formato dell'hardware, lo stesso che usa
# extract_mapman_v3.ps1 per il mapman.
$npcSprite  = New-Object byte[] ($NPC_MAX * 32)
$npcSlots   = New-Object byte[] ($NPC_MAX * 3)
$npcUsed    = 0

# quadranti nell'ordine UL, UR, DL, DR: offset nella TSA, tile dell'oggetto,
# sotto-palette sprite. Il tile dell'oggetto NON e' q: la LUT del NES elenca
# UL, DL, UR, DR (tile 0, 2, 1, 3).
$qTsaOff  = @(0, 128, 256, 384)
$qObjTile = @(0, 1, 2, 3)
$qSprPal  = @(2, 2, 3, 3)

for ($s = 0; $s -lt $NPC_MAX; $s++) {
    $oid = [int]$b00[$OBJ_BASE + $s*3]
    if ($oid -eq 0) { continue }
    $ox = [int]$b00[$OBJ_BASE + $s*3 + 1] -band 0x3F
    $oy = [int]$b00[$OBJ_BASE + $s*3 + 2] -band 0x3F
    $macro = [int]$map[$oy * 64 + $ox]
    $gfx = [int]$b00[$OBJGFX_BASE + $oid]

    $bgPal = [int]$b00[$ATTR_BASE + $macro] -band 3
    $bgTms = New-Object int[] 4
    for ($c = 0; $c -lt 4; $c++) { $bgTms[$c] = Get-TmsColor ([int]$b00[$PAL_BASE + $bgPal*4 + $c]) }

    $npcSlots[$s*3]     = [byte]$oid
    $npcSlots[$s*3 + 1] = [byte]$ox
    $npcSlots[$s*3 + 2] = [byte]$oy
    $npcUsed++

    for ($q = 0; $q -lt 4; $q++) {
        $gTile = [int]$b00[$TSA_BASE + $qTsaOff[$q] + $macro]
        $oTile = $qObjTile[$q]
        # sotto-palette SPRITE: 16 byte BG poi 16 sprite, dentro lo stesso
        # blocco da $30 di lut_SMPalettes.
        $spTms = New-Object int[] 4
        for ($c = 0; $c -lt 4; $c++) { $spTms[$c] = Get-TmsColor ([int]$b00[$PAL_BASE + 16 + $qSprPal[$q]*4 + $c]) }

        for ($row = 0; $row -lt 8; $row++) {
            $g0 = [int]$b03[$CHR_BASE + $gTile*16 + $row]
            $g1 = [int]$b03[$CHR_BASE + $gTile*16 + 8 + $row]
            $o0 = [int]$b02[$OBJCHR_BASE + $gfx*256 + $oTile*16 + $row]
            $o1 = [int]$b02[$OBJCHR_BASE + $gfx*256 + $oTile*16 + 8 + $row]

            $px  = New-Object int[] 8
            $cls = New-Object int[] 8
            $gpx = New-Object int[] 8    # il terreno per INTERO, coperto o no
            for ($x = 0; $x -lt 8; $x++) {
                $bit = 7 - $x
                $gci = ((($g0 -shr $bit) -band 1)) -bor ((($g1 -shr $bit) -band 1) -shl 1)
                $gpx[$x] = $bgTms[$gci]
                $oci = ((($o0 -shr $bit) -band 1)) -bor ((($o1 -shr $bit) -band 1) -shl 1)
                if ($oci -ne 0) {
                    $px[$x]  = $spTms[$oci]
                    # Valore 1 = contorno, 2 e 3 = vestito e incarnato. La
                    # distinzione e' TUTTO in Convert-NpcRowToTms: e' cio' che
                    # rende la figura una persona invece di barre orizzontali.
                    if ($oci -eq 1) { $cls[$x] = 1 } else { $cls[$x] = 2 }
                } else {
                    $px[$x]  = $gpx[$x]
                    $cls[$x] = 0
                }
            }
            $rowOut = Convert-NpcRowToTms $px $cls $gpx
            $npcPattern[($s*4 + $q)*8 + $row] = $rowOut[0]
            $npcColor[($s*4 + $q)*8 + $row]   = $rowOut[1]

            # Il contorno, per lo sprite. I quadranti del generatore sprite
            # vanno per COLONNE (TL, BL, TR, BR) mentre qui $q va per righe
            # (UL, UR, DL, DR): la conversione e' questa riga, e sbagliarla
            # da' un contorno con le meta' scambiate -- che a schermo sembra
            # una figura "smontata", non un indice storto.
            $sq = @(0, 2, 1, 3)[$q]
            $obits = 0
            for ($x = 0; $x -lt 8; $x++) {
                if ($cls[$x] -eq 1) { $obits = $obits -bor (1 -shl (7 - $x)) }
            }
            $npcSprite[$s*32 + $sq*8 + $row] = [byte]$obits
        }
    }
}
Write-Host ("NPC della mappa {0}: {1} su {2} slot, tile TMS {3}-{4}" -f `
            $MapId, $npcUsed, $NPC_MAX, $NPC_TILE_BASE, ($NPC_TILE_BASE + $NPC_MAX*4 - 1))

# --- emissione ---------------------------------------------------------------
function Format-ByteArray([byte[]]$arr, [int]$perLine = 16) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $arr.Length; $i += $perLine) {
        $end = [Math]::Min($i + $perLine, $arr.Length) - 1
        $line = ($arr[$i..$end] | ForEach-Object { '0x' + $_.ToString('X2') }) -join ','
        [void]$sb.AppendLine("    $line,")
    }
    return $sb.ToString().TrimEnd()
}

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "// AUTO-GENERATO da tools/extract_sm_colors.ps1 -- non modificare a mano."
W "//"
W "// Mappa standard $MapId (tileset $Tileset) a COLORI VERI per TMS9918."
W "// Ogni tile TMS = una coppia (tile CHR NES, sotto-palette). Coppie usate:"
W "//   $nCombo su 256 disponibili."
W "// Colore: 8 byte per tile, (fg << 4) | bg per riga (per-row dominant)."
W "//"
W "// La MAPPA sta qui e non in ff1_town_coneria.h perche' deve vivere nello"
W "// stesso banco della grafica: durante il disegno se ne mappa uno solo."
W "//"
W "// Header GATED: i dati escono solo con FF1_${PFX}_DEFINE_DATA definito"
W "// (lo fa src/towngfx_bank.c, proprietario del banco). La slice include"
W "// questo file solo per le costanti."
W ""
W "#ifndef FF1_${PFX}_H"
W "#define FF1_${PFX}_H"
W ""
W "#define FF1_${PFX}_TILE_COUNT   256"
W "#define FF1_${PFX}_COMBO_USED   $nCombo"
W "#define FF1_${PFX}_MACRO_COUNT  128"
W "#define FF1_${PFX}_MAP_W        64"
W "#define FF1_${PFX}_MAP_H        64"
W "#define FF1_${PFX}_TILESET      $Tileset"
W "#define FF1_${PFX}_MAP_ID       $MapId"
W "// Ingresso del giocatore, in MACROtile (EntrTele ID 01)."
W "#define FF1_${PFX}_ENTRY_X      $entryX"
W "#define FF1_${PFX}_ENTRY_Y      $entryY"
W ""
W "// --- NPC (slice76) --------------------------------------------------------"
W "// Gli abitanti sono TILE DI FONDO, non sprite: il mapman ne occupa gia'"
W "// quattro e il TMS9918 ne mostra quattro per scanline, quindi un NPC di"
W "// fianco al giocatore -- l'unica posizione da cui gli si puo' parlare --"
W "// sparirebbe. Ogni slot ha QUATTRO tile sue, cotte sopra il terreno su cui"
W "// l'NPC sta: per questo non puo' camminare."
W "#define FF1_${PFX}_NPC_MAX       $NPC_MAX"
W "#define FF1_${PFX}_NPC_USED      $npcUsed"
W "#define FF1_${PFX}_NPC_TILE_BASE $NPC_TILE_BASE"
W ""
W "// --- proprieta' dei macrotile (SMTilesetProp) ------------------------------"
W "// Byte 0 = flag, byte 1 = parametro. Costanti da Constants.inc del disasm."
W "//"
W "// LA REGOLA DEL BLOCCO NON E' `byte0 & NOMOVE`. Sul NES (CanPlayerMoveSM,"
W "// bank_0F.asm:2448) e':"
W "//     (byte0 & (TP_SPEC_MASK | TP_NOMOVE)) == TP_NOMOVE"
W "// cioe' NOMOVE blocca SOLO se i bit di specialita' sono tutti spenti. E'"
W "// quello che fa passare le porte dei negozi, che hanno NOMOVE acceso"
W "// insieme a TP_SPEC_DOOR: prese col solo bit NOMOVE sarebbero muri, e"
W "// Coneria avrebbe sette negozi inaccessibili senza dare nessun errore."
W "#define TP_NOMOVE        0x01"
W "#define TP_SPEC_MASK     0x1E"
W "#define TP_SPEC_DOOR     0x02"
W "#define TP_SPEC_LOCKED   0x04"
W "#define TP_SPEC_CLOSEROOM 0x06"
W "#define TP_SPEC_TREASURE 0x08"
W "#define TP_SPEC_BATTLE   0x0A"
W "#define TP_SPEC_DAMAGE   0x0C"
W "#define TP_BATTLEMARKER  0x20"
W "#define TP_TELE_MASK     0xC0"
W "#define TP_TELE_WARP     0x40"
W "#define TP_TELE_NORM     0x80"
W "#define TP_TELE_EXIT     0xC0"
W "// Su una porta (TP_SPEC_DOOR) il byte 1 e' lo shop_id, se non e' zero."
W "// bank_0F.asm:3539. Su tutto il resto e' un id di teleport/dialogo/tesoro."
W ""
W "#ifdef FF1_${PFX}_DEFINE_DATA"
W ""
W "static const unsigned char ff1_${pfxl}_pattern[FF1_${PFX}_TILE_COUNT * 8] = {"
W (Format-ByteArray $pattern)
W "};"
W ""
W "static const unsigned char ff1_${pfxl}_color[FF1_${PFX}_TILE_COUNT * 8] = {"
W (Format-ByteArray $color)
W "};"
W ""
foreach ($q in 0,1,2,3) {
    $nm = @('ul','ur','dl','dr')[$q]
    W "static const unsigned char ff1_${pfxl}_tsa_$nm[FF1_${PFX}_MACRO_COUNT] = {"
    W (Format-ByteArray $tsaNew[$q])
    W "};"
    W ""
}
W "// Mappa decompressa, PIATTA (64*64): un array a due dimensioni finirebbe in"
W "// DATA, che in un banco non viene mai inizializzata."
W "static const unsigned char ff1_${pfxl}_map[FF1_${PFX}_MAP_W * FF1_${PFX}_MAP_H] = {"
W (Format-ByteArray $map)
W "};"
W ""
W "// SMTilesetProp del tileset $Tileset, PIATTA: 128 macrotile x 2 byte."
W "// Piatta e non [128][2] per la stessa ragione della mappa -- un array a due"
W "// dimensioni finisce in DATA, che in un banco non viene mai inizializzata"
W "// (bug #3 di slice44)."
W "static const unsigned char ff1_${pfxl}_prop[FF1_${PFX}_MACRO_COUNT * 2] = {"
W (Format-ByteArray $prop)
W "};"
W ""
W "// --- NPC: pattern, colore, e la tabella degli slot ------------------------"
W "// 15 slot x 4 tile (UL, UR, DL, DR) x 8 byte. Uno slot vuoto ha id 0 e le"
W "// sue quattro tile valgono zero: si caricano lo stesso, cosi' il numero di"
W "// tile in VRAM non dipende da quanti abitanti ha la mappa."
W "static const unsigned char ff1_${pfxl}_npc_pattern[FF1_${PFX}_NPC_MAX * 4 * 8] = {"
W (Format-ByteArray $npcPattern)
W "};"
W ""
W "static const unsigned char ff1_${pfxl}_npc_color[FF1_${PFX}_NPC_MAX * 4 * 8] = {"
W (Format-ByteArray $npcColor)
W "};"
W ""
W "// Il CONTORNO NERO, come sprite 16x16 del TMS: 32 byte per slot, quadranti"
W "// in ordine TL, BL, TR, BR. Va sopra la sagoma di fondo e le ridà tutto il"
W "// dettaglio interno -- occhi, stacco fra testa e busto, divisione delle"
W "// gambe -- che in Mode 2 non entrerebbe, perche' una riga di tile ha due"
W "// colori e ne servirebbero tre (terreno, corpo, contorno)."
W "//"
W "// SE LO SPRITE CADE non si perde l'abitante: resta la sagoma piena del"
W "// fondo. E cade in un caso solo, quello in cui il giocatore gli e' di"
W "// fianco -- il mapman occupa gia' quattro sprite e il TMS ne mostra quattro"
W "// per scanline."
W "static const unsigned char ff1_${pfxl}_npc_sprite[FF1_${PFX}_NPC_MAX * 32] = {"
W (Format-ByteArray $npcSprite)
W "};"
W ""
W "// Tre byte per slot: id oggetto, X e Y in MACROtile. id 0 = slot vuoto."
W "// L'id serve al banco 26 per sapere QUALE dialogo esce; le coordinate"
W "// servono alla slice per disegnarlo, per bloccarci il passo e per capire"
W "// chi si ha davanti."
W "static const unsigned char ff1_${pfxl}_npc_slots[FF1_${PFX}_NPC_MAX * 3] = {"
W (Format-ByteArray $npcSlots)
W "};"
W ""
W "#endif // FF1_${PFX}_DEFINE_DATA"
W "#endif // FF1_${PFX}_H"

[System.IO.File]::WriteAllText($OutHdr, $sb.ToString())
Write-Host "scritto $OutHdr"
Write-Host ("  pattern 2048 + color 2048 + TSA 512 + mappa 4096 + prop 256 = {0} byte" -f (2048+2048+512+4096+256))
