# extract_dialogue.ps1 -- i dialoghi di FF1, decompressi da DTE ad ASCII.
#
# PERCHE' ESISTE (slice76)
#   Gli abitanti delle mappe standard dicono qualcosa, e quel qualcosa sta nel
#   ROM in forma compressa: lut_DialoguePtrTbl ($8000 del banco $0A) e' una
#   tabella di 256 puntatori a stringhe in cui i byte $1A-$79 non sono lettere
#   ma COPPIE di lettere (DTE, tabella a $F050 del banco $0F). Un byte su due
#   di un dialogo di FF1 vale due caratteri.
#
#   Qui la compressione si SCIOGLIE, e non e' una scelta di comodo: il TMS9918
#   non ha piu' un byte per tile del NES, ha una name table di 768 celle e un
#   font caricato a mano. Portarsi dietro il DTE vorrebbe dire pagare il
#   decompressore in un banco di codice per risparmiare qualche centinaio di
#   byte in un banco di dati che ne ha 16384.
#
# COSA PRODUCE
#   src/data/dialogue.h    testo di TUTTI i dialoghi referenziati dalle mappe
#                          richieste, indicizzato per ID ORIGINALE. La tabella
#                          degli offset ha 256 voci: un id non incluso punta
#                          alla stringa vuota, che a schermo e' il "non c'e'
#                          niente" del NES.
#   src/data/mapobj_talk.h i 4 byte di dati di dialogo per oggetto
#                          (lut_MapObjTalkData) piu' il NUMERO della routine
#                          che decide quale dei tre esce (dalla jump table).
#
# PERCHE' L'ID ORIGINALE E NON UNA RINUMERAZIONE
#   Perche' gli id li scrivono i dati del ROM (i 4 byte per oggetto, il byte 1
#   delle proprieta' di un macrotile), e rinumerarli vorrebbe dire tradurre in
#   tre posti diversi. 512 byte di tabella contro tre traduzioni che possono
#   divergere: e' lo stesso conto di [[ff1-item-id-space]].
#
# FORMATO DEL TESTO
#   ASCII, terminatore 0, e UN SOLO codice di controllo: 0x01 = a capo. I
#   codici $01/$04-$19 del NES sono tutti "a capo" (bank_0F.asm:6669), $02 e'
#   il nome di un oggetto (solo per i forzieri) e $03 e' dichiarato BUGGED dal
#   disassembly e non usato: qui diventano il testo letterale <ITEM> e la fine
#   della stringa, come sul NES.

param(
    [string]$Root   = (Split-Path -Parent $PSScriptRoot),
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    # Le mappe di cui si vogliono i dialoghi. Ogni mappa tira dentro i testi
    # dei suoi 15 oggetti e quelli attaccati ai suoi macrotile.
    [int[]]$Maps    = @(0),
    [string]$OutDlg = 'src\data\dialogue.h',
    [string]$OutObj = 'src\data\mapobj_talk.h',
    [string]$OutFlg = 'src\data\init_flags.h',
    # Larghezza della colonna di testo del riquadro di dialogo. Se una riga la
    # supera e' un ERRORE, non un troncamento: a schermo una riga troppo lunga
    # non si taglia, sborda nella riga dopo (la name table e' un nastro di 768
    # byte, non una griglia -- e' il difetto #1 di slice73).
    [int]$MaxCols   = 24,
    # Righe di testo che il riquadro puo' mostrare in una volta.
    [int]$MaxRows   = 8
)

$ErrorActionPreference = 'Stop'

function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }
$b00 = ReadBank 'bank_00.dat'
$b0A = ReadBank 'bank_0A.dat'
$b0F = ReadBank 'bank_0F.bin'
$objdata = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0E_95D5_objectdata.bin'))

# bank_0F.bin e' l'ULTIMO banco, mappato a $C000: l'offset e' addr - $C000.
# Gli altri banchi stanno a $8000. Sbagliare la base qui non da' errore, da'
# una tabella DTE di codice macchina -- cioe' dialoghi di lettere a caso.
$DTE2 = 0xF050 - 0xC000
$DTE1 = $DTE2 + 80

$N_OBJ  = 0xD0
$N_DLG  = 0x100
$N_MAPS = 15   # oggetti per mappa

# --- charset FF1 -> ASCII ----------------------------------------------------
# Stessa famiglia di conversioni di extract_item_names.ps1 e extract_monsters,
# ma qui serve anche la punteggiatura: un dialogo senza virgole e punti non e'
# leggibile. La tabella e' quella del disassembly (table_standard.tbl), letta
# invece che ricopiata -- una copia a mano sarebbe una seconda fonte di verita'.
$chr = @{}
foreach ($line in Get-Content (Join-Path $Disasm 'table_standard.tbl')) {
    if ($line -match '^([0-9A-F]{2})=(.*)$') {
        $chr[[Convert]::ToInt32($Matches[1], 16)] = $Matches[2]
    }
}
# Tre correzioni alla tabella del disassembly, tutte verificate contro il testo
# che il gioco mostra davvero:
#   $BE  il .tbl dice `"`, ma nel font di FF1 quel disegno e' un APOSTROFO --
#        senza la correzione si legge  Lukahn"s  invece di  Lukahn's.
#   $C3  non e' nel .tbl: e' la tile dei puntini di sospensione, che FF1 usa
#        sempre in coppia. Diventa un punto, cosi' `$C3 $C3` fa `..`.
#   $FF  e' la tile VUOTA (il .tbl la lascia senza valore, che sarebbe una
#        stringa nulla e sposterebbe a sinistra tutto quel che segue).
$chr[0xBE] = "'"
$chr[0xC3] = '.'
$chr[0xFF] = ' '

function Convert-Char([int]$c) {
    if ($chr.ContainsKey($c)) { return $chr[$c] }
    Write-Host ("  ATTENZIONE: carattere FF1 0x{0:X2} non mappato" -f $c) -ForegroundColor Yellow
    return '?'
}

function Get-Dialogue([int]$id) {
    $p = $b0A[$id*2] + $b0A[$id*2+1]*256 - 0x8000
    if ($p -lt 0 -or $p -ge $b0A.Length) { throw ("dialogo {0:X2}: puntatore fuori dal banco" -f $id) }
    $out = ''
    $guard = 0
    while ($true) {
        if ($guard++ -gt 512) { throw ("dialogo {0:X2}: nessun terminatore in 512 byte" -f $id) }
        $c = [int]$b0A[$p]; $p++
        if ($c -eq 0) { break }
        if ($c -lt 0x1A) {
            if ($c -eq 2) { $out += '<ITEM>' }
            elseif ($c -eq 3) { break }   # BUGGED sul NES: stampa il nome e SMETTE
            else { $out += "`n" }
        } elseif ($c -lt 0x7A) {
            $k = $c - 0x1A
            $out += (Convert-Char $b0F[$DTE1 + $k]) + (Convert-Char $b0F[$DTE2 + $k])
        } else {
            $out += (Convert-Char $c)
        }
    }
    return $out
}

# --- jump table delle routine di dialogo ------------------------------------
# Si LEGGE dal disassembly invece di ricopiarla: 208 voci scritte a mano sono
# 208 occasioni di sbagliarne una, e sbagliarne una non da' nessun errore --
# da' un abitante che risponde con la battuta di un altro.
$asm = Get-Content (Join-Path $Disasm 'bank_0E.asm')
$startLine = ($asm | Select-String -Pattern '^lut_MapObjTalkJumpTbl:' | Select-Object -First 1).LineNumber
$routines = New-Object System.Collections.Generic.List[string]
for ($i = $startLine; $i -lt $startLine + 60 -and $routines.Count -lt $N_OBJ; $i++) {
    if ($asm[$i] -match '^\s*\.WORD\s+(.+?)(\s*;.*)?$') {
        foreach ($t in ($Matches[1] -split ',')) {
            $t = $t.Trim()
            if ($t -and $routines.Count -lt $N_OBJ) { [void]$routines.Add($t) }
        }
    }
}
if ($routines.Count -ne $N_OBJ) { throw "jump table letta a $($routines.Count) voci, attese $N_OBJ" }

# I numeri delle routine. L'ordine e' quello di src/ovl_talk.c e i due elenchi
# devono restare allineati: per questo il file generato li scrive tutti in
# testa come commento, cosi' una divergenza si vede leggendo l'header.
$KIND = [ordered]@{
    'Talk_None'         = 0
    'Talk_Unused'       = 0
    'Talk_norm'         = 1
    'Talk_ifvis'        = 2
    'Talk_ifitem'       = 3
    'Talk_ifevent'      = 4
    'Talk_4Orb'         = 5
    'Talk_GoBridge'     = 6
    'Talk_Invis'        = 7
    'Talk_KingConeria'  = 8
    'Talk_Princess1'    = 9
    'Talk_Princess2'    = 10
    'Talk_Garland'      = 11
    'Talk_BlackOrb'     = 12
    'Talk_Replace'      = 13
    'Talk_CoOGuy'       = 14
    'Talk_fight'        = 15
    'Talk_ifbridge'     = 16
}
$KIND_UNKNOWN = 1   # tutto il resto risponde con [1], come Talk_norm

# --- raccolta degli id di dialogo che servono -------------------------------
# Il dialogo $00 c'e' SEMPRE ed e' il primo: e' "Nothing here", cioe' la
# risposta del NES a chi parla a un muro (DLGID_NOTHING, Constants.inc:281).
# Sta all'offset 0 apposta, cosi' ogni id non incluso ci finisce sopra da solo
# e nessuna strada porta a una schermata vuota.
$need = @{ 0 = 1 }
$objUsed = @{}
foreach ($m in $Maps) {
    $base = 0x3400 + $m * 48
    for ($s = 0; $s -lt $N_MAPS; $s++) {
        $oid = [int]$b00[$base + $s*3]
        if ($oid -eq 0) { continue }
        $objUsed[$oid] = 1
        foreach ($k in 1, 2, 3) {
            $d = [int]$objdata[$oid*4 + $k]
            if ($d -ne 0) { $need[$d] = 1 }
        }
    }
    # Dialoghi attaccati ai MACROTILE: parlare a un tile senza abitante davanti
    # legge il byte 1 delle sue proprieta' come id di dialogo, purche' nessuno
    # dei bit TP_NOTEXT ($C2) sia acceso (TalkToSMTile, bank_0F.asm:2822).
    $tileset = [int]$b00[0x2CC0 + $m]
    $propBase = 0x0800 + $tileset * 256
    for ($t = 0; $t -lt 128; $t++) {
        $p0 = [int]$b00[$propBase + $t*2]
        $p1 = [int]$b00[$propBase + $t*2 + 1]
        if (($p0 -band 0xC2) -ne 0) { continue }
        if (($p0 -band 0x1E) -eq 0x08) { continue }   # forziere: non e' un dialogo
        if ($p1 -ne 0) { $need[$p1] = 1 }
    }
}

# --- decodifica, misura, emissione ------------------------------------------
$texts   = New-Object string[] $N_DLG
$offsets = New-Object int[] $N_DLG
$blob    = New-Object System.Collections.Generic.List[byte]

# Tutti gli offset partono da 0, che e' il dialogo $00 ("Nothing here"): un id
# non incluso risponde cosi', invece di aprire un riquadro vuoto.
for ($i = 0; $i -lt $N_DLG; $i++) { $offsets[$i] = 0 }

$maxCols = 0; $maxRows = 0; $worstCol = ''; $worstRow = 0
foreach ($id in ($need.Keys | Sort-Object)) {
    $t = Get-Dialogue $id
    $texts[$id] = $t
    $lines = $t -split "`n"
    if ($lines.Count -gt $maxRows) { $maxRows = $lines.Count; $worstRow = $id }
    foreach ($l in $lines) {
        if ($l.Length -gt $maxCols) { $maxCols = $l.Length; $worstCol = $l }
    }
    $offsets[$id] = $blob.Count
    foreach ($ch in $t.ToCharArray()) {
        if ($ch -eq "`n") { [void]$blob.Add(1) }
        else { [void]$blob.Add([byte][char]$ch) }
    }
    [void]$blob.Add(0)
}

Write-Host ("dialoghi inclusi: {0} su 256, {1} byte di testo" -f $need.Count, $blob.Count)
Write-Host ("riga piu' lunga: {0} caratteri  ->  <{1}>" -f $maxCols, $worstCol)
Write-Host ("testo piu' alto: {0} righe (dialogo {1:X2})" -f $maxRows, $worstRow)
if ($maxCols -gt $MaxCols) { throw "una riga e' di $maxCols caratteri, il riquadro ne mostra $MaxCols" }
if ($maxRows -gt $MaxRows) { throw "un testo e' di $maxRows righe, il riquadro ne mostra $MaxRows" }

function Format-ByteArray([byte[]]$arr, [int]$perLine = 16) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $arr.Length; $i += $perLine) {
        $end = [Math]::Min($i + $perLine, $arr.Length) - 1
        $line = ($arr[$i..$end] | ForEach-Object { '0x' + $_.ToString('X2') }) -join ','
        [void]$sb.AppendLine("    $line,")
    }
    return $sb.ToString().TrimEnd()
}

# ---- dialogue.h ------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "// AUTO-GENERATO da tools/extract_dialogue.ps1 -- non modificare a mano."
W "//"
W ("// Mappe incluse: {0}" -f ($Maps -join ', '))
W ("// Dialoghi: {0} su 256. Testo: {1} byte." -f $need.Count, $blob.Count)
W ("// Riga piu' lunga {0} caratteri, testo piu' alto {1} righe." -f $maxCols, $maxRows)
W "//"
W "// Testo ASCII, terminatore 0, 0x01 = a capo. Indicizzato per ID ORIGINALE"
W "// di FF1: un id non incluso punta all'offset 0, che e' la stringa vuota."
W "//"
W "// Header GATED: i dati escono solo con FF1_DIALOGUE_DEFINE_DATA definito."
W ""
W "#ifndef FF1_DIALOGUE_H"
W "#define FF1_DIALOGUE_H"
W ""
W "#define FF1_DLG_COUNT     $N_DLG"
W "#define FF1_DLG_TEXT_LEN  $($blob.Count)"
W "#define FF1_DLG_MAX_COLS  $maxCols"
W "#define FF1_DLG_MAX_ROWS  $maxRows"
W "#define FF1_DLG_NEWLINE   0x01"
W ""
W "#ifdef FF1_DIALOGUE_DEFINE_DATA"
W ""
W "// Offset dentro ff1_dlg_text, uno per id. 16 bit: il testo supera i 256"
W "// byte gia' con tre dialoghi."
W "static const unsigned int ff1_dlg_offset[FF1_DLG_COUNT] = {"
for ($i = 0; $i -lt $N_DLG; $i += 8) {
    $line = @()
    for ($k = 0; $k -lt 8; $k++) { $line += $offsets[$i+$k] }
    W ("    " + ($line -join ',') + ",   /* " + ('{0:X2}' -f $i) + " */")
}
W "};"
W ""
W "static const unsigned char ff1_dlg_text[FF1_DLG_TEXT_LEN] = {"
W (Format-ByteArray $blob.ToArray())
W "};"
W ""
W "#endif // FF1_DIALOGUE_DEFINE_DATA"
W "#endif // FF1_DIALOGUE_H"
[System.IO.File]::WriteAllText((Join-Path $Root $OutDlg), $sb.ToString())
Write-Host ("scritto {0}" -f (Join-Path $Root $OutDlg))

# ---- mapobj_talk.h ---------------------------------------------------------
$sb = New-Object System.Text.StringBuilder

$talk = New-Object byte[] ($N_OBJ * 4)
[Array]::Copy($objdata, 0, $talk, 0, $N_OBJ * 4)
$kinds = New-Object byte[] $N_OBJ
$unknown = @{}
for ($o = 0; $o -lt $N_OBJ; $o++) {
    $r = $routines[$o]
    if ($KIND.Contains($r)) { $kinds[$o] = [byte]$KIND[$r] }
    else {
        $kinds[$o] = [byte]$KIND_UNKNOWN
        if ($objUsed.ContainsKey($o)) { $unknown[$r] = 1 }
    }
}
if ($unknown.Count -gt 0) {
    Write-Host ("  ATTENZIONE: routine non implementate usate dalle mappe scelte: {0}" -f ($unknown.Keys -join ', ')) -ForegroundColor Yellow
}

W "// AUTO-GENERATO da tools/extract_dialogue.ps1 -- non modificare a mano."
W "//"
W "// Per ognuno dei 208 id di oggetto: i 4 byte di lut_MapObjTalkData e il"
W "// NUMERO della routine che decide quale delle tre battute esce."
W "//"
W "// I 4 byte non hanno un significato fisso: dipende dalla routine. Per le"
W "// generiche il byte 0 e' il PARAMETRO della condizione (un id di oggetto"
W "// per ifvis, un id di oggetto per ifitem, un indice di flag per ifevent) e"
W "// i byte 1-3 sono i tre dialoghi possibili. Vedi TalkRoutines in"
W "// bank_0E.asm:1025."
W "//"
W "// I numeri di routine, che devono restare allineati con src/ovl_talk.c:"
foreach ($k in $KIND.Keys) { W ("//   {0,2} = {1}" -f $KIND[$k], $k) }
W "// Ogni altra routine del NES vale $KIND_UNKNOWN (risponde sempre con [1]):"
W "// finche' non c'e' la mappa che la usa, implementarla sarebbe codice mai"
W "// eseguito -- e questo progetto ha una regola contro quelli."
W ""
W "#ifndef FF1_MAPOBJ_TALK_H"
W "#define FF1_MAPOBJ_TALK_H"
W ""
W "#define FF1_OBJ_COUNT  $N_OBJ"
W ""
W "#ifdef FF1_MAPOBJ_TALK_DEFINE_DATA"
W ""
W "// PIATTO, non [FF1_OBJ_COUNT][4]: un array a due dimensioni finisce in"
W "// sezione DATA, che dentro un banco non viene mai inizializzata"
W "// ([[slice44-real-root-causes]] #3, [[rodata-trap-small-arrays]])."
W "static const unsigned char ff1_obj_talk[FF1_OBJ_COUNT * 4] = {"
W (Format-ByteArray $talk)
W "};"
W ""
W "static const unsigned char ff1_obj_kind[FF1_OBJ_COUNT] = {"
W (Format-ByteArray $kinds)
W "};"
W ""
W "#endif // FF1_MAPOBJ_TALK_DEFINE_DATA"
W "#endif // FF1_MAPOBJ_TALK_H"
[System.IO.File]::WriteAllText((Join-Path $Root $OutObj), $sb.ToString())
Write-Host ("scritto {0}" -f (Join-Path $Root $OutObj))

# ---- init_flags.h ----------------------------------------------------------
# lut_InitGameFlags ($AF00 nel banco 0): lo stato di partenza dei 208 flag.
# Il NES ne copia una PAGINA INTERA all'accensione (bank_0F.asm:95); qui bastano
# i 208 byte veri, perche' gli id di oggetto arrivano a $CF e il resto della
# pagina non lo legge nessuno.
#
# NON SI PUO' INVENTARE "tutti visibili". La tabella dice che la principessa
# salvata ($12) comincia NASCOSTA, e mezza Coneria guarda proprio quel bit per
# decidere se rispondere "salvatela!" o "grazie". Con i flag azzerati a mano
# ogni abitante direbbe la battuta sbagliata, e sarebbe un errore credibile.
$initFlags = New-Object byte[] $N_OBJ
[Array]::Copy($b00, 0x2F00, $initFlags, 0, $N_OBJ)
$visible = 0
foreach ($f in $initFlags) { if ($f -band 1) { $visible++ } }

$sb = New-Object System.Text.StringBuilder
W "// AUTO-GENERATO da tools/extract_dialogue.ps1 -- non modificare a mano."
W "//"
W "// lut_InitGameFlags: lo stato di partenza dei flag di gioco, uno per id di"
W ("// oggetto. {0} dei {1} oggetti cominciano VISIBILI." -f $visible, $N_OBJ)
W "//"
W "// Lo legge src/ovl_intro.c a nuova partita, che e' il posto in cui il"
W "// gruppo nasce: 208 byte di rodata e un ciclo, in un banco che ne ha"
W "// migliaia liberi. Nella finestra fissa sarebbero stati 208 byte per"
W "// sempre dietro un ciclo che gira una volta ([[fixed-window-full]])."
W ""
W "#ifndef FF1_INIT_FLAGS_H"
W "#define FF1_INIT_FLAGS_H"
W ""
W "#ifdef FF1_INIT_FLAGS_DEFINE_DATA"
W "static const unsigned char ff1_init_flags[$N_OBJ] = {"
W (Format-ByteArray $initFlags)
W "};"
W "#endif // FF1_INIT_FLAGS_DEFINE_DATA"
W "#endif // FF1_INIT_FLAGS_H"
[System.IO.File]::WriteAllText((Join-Path $Root $OutFlg), $sb.ToString())
Write-Host ("scritto {0}  ({1} oggetti visibili su {2})" -f (Join-Path $Root $OutFlg), $visible, $N_OBJ)
