# dump_shop.ps1 -- il listino di un negozio, composto come lo comporra' il gioco.
#
# PERCHE' PRIMA DELL'INTERFACCIA. Una riga di listino si mette insieme da
# quattro pezzi che stanno in quattro tabelle diverse: l'id nella lista del
# negozio, il nome, l'icona di tipo, il prezzo. Se uno dei quattro e' letto
# con l'indice sbagliato, a schermo esce un negozio PLAUSIBILE -- ed e'
# esattamente cosi' che lo scarto di $1C nello spazio degli id e' sopravvissuto
# fino a slice63. Comporlo qui, dove si vede accanto il byte grezzo, e' l'unico
# modo di sapere che l'interfaccia mostrera' il vero.
#
# COME SI LEGGONO I DATI (fonte: bank_0E.asm, lut_ShopData)
#   lut_ShopData sta a $8300 nel banco $0E ed e' fatto di due pezzi attaccati:
#     - 71 puntatori word LE (142 byte), uno per shop_id
#     - le liste in linea, che SI SOVRAPPONGONO: la stessa sequenza di byte
#       serve inventari diversi a puntatori diversi ("sliding window"). Per
#       questo non si possono contare 5 byte per negozio e dividere.
#   Quindi: offset nella tabella = puntatore - $8300, e da li' si leggono al
#   massimo 5 id. Un id $00 e' una casella VUOTA e chiude la lista.
#
#   I prezzi: lut_ItemPrices[id] e' una word LE (il gioco fa ASL/ROL su A per
#   costruire l'indice a 16 bit, bank_0F:10573).
#
# CLINICA E LOCANDA NON HANNO UN LISTINO, e il modo in cui NON ce l'hanno e'
# la trappola di questo file. I primi DUE byte della loro lista sono il prezzo
# a 16 bit little-endian, non oggetti: LoadShopInventory (bank_0E.asm:4871)
# copia i 5 byte in `item_box`, e per questi due tipi InnClinic_CanAfford
# (bank_0E.asm:4576) confronta `item_box`/`item_box+1` direttamente con l'oro.
#
# La prima versione di questo strumento leggeva il primo byte come un id e ne
# cercava il prezzo in lut_ItemPrices. Usciva una locanda da 5 GP e una clinica
# da 1500: numeri, formattati bene, e sbagliati. La lettura giusta da'
# $001E = 30 GP e $0028 = 40 GP -- la locanda e la clinica di Coneria.
# Che i quattro listini veri uscissero perfetti nella stessa passata rende la
# cosa peggiore, non migliore: e' cosi' che un errore si nasconde.

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    # I sette di Coneria. -Shops 0 per stamparli tutti e 71.
    [int[]]$Shops = @(0x01, 0x0B, 0x15, 0x1F, 0x29, 0x33, 0x3D)
)

$ErrorActionPreference = 'Stop'

function Read-Array([string]$file, [string]$name) {
    $lines = Get-Content (Join-Path $Root $file)
    $inArr = $false
    $out = New-Object System.Collections.ArrayList
    foreach ($l in $lines) {
        if (-not $inArr) {
            if ($l -match [regex]::Escape($name) + '\s*\[') { $inArr = $true }
            continue
        }
        if ($l -match '^\};') { break }
        # I COMMENTI VANNO TAGLIATI PRIMA. Contengono `$1C`, `0x83` e altri
        # esadecimali: pescarli insieme ai dati fa leggere 384 valori dove ce
        # ne sono 256, e le tabelle escono spostate senza un errore.
        $code = ($l -split '//')[0]
        foreach ($m in [regex]::Matches($code, '0x([0-9A-Fa-f]{2})')) {
            [void]$out.Add([Convert]::ToInt32($m.Groups[1].Value, 16))
        }
    }
    if ($out.Count -eq 0) { throw "array non trovato o vuoto: $name in $file" }
    return $out
}

$prices    = Read-Array 'src\data\shop_data.h'  'lut_ItemPrices'
$shopData  = Read-Array 'src\data\shop_data.h'  'lut_ShopData'
$shopTypes = Read-Array 'src\data\shop_data.h'  'lut_ShopTypes'
Write-Host ("prezzi {0} byte, lut_ShopData {1} byte, tipi {2}" -f `
    $prices.Count, $shopData.Count, $shopTypes.Count)

# I nomi: caratteri fra apici nell'array piatto da 8.
$nameLines = Get-Content (Join-Path $Root 'src\data\item_names.h')
$names = @{}
$id = 0
$inArr = $false
foreach ($l in $nameLines) {
    if (-not $inArr) { if ($l -match 'ff1_item_names\s*\[') { $inArr = $true }; continue }
    if ($l -match '^\};') { break }
    $code = ($l -split '//')[0]
    $cells = [regex]::Matches($code, "'(.)'")
    if ($cells.Count -eq 0) { continue }
    $s = ''
    foreach ($c in $cells) { $s += $c.Groups[1].Value }
    $names[$id] = $s.TrimEnd()
    $id++
}
Write-Host ("nomi letti: {0}" -f $names.Count)

$TYPE = @('Weapon', 'Armor', 'W-Magic', 'B-Magic', 'Clinic', 'Inn', 'Item', 'Caravan')
# Le 12 icone di tipo, $D4-$DF. I nomi qui sono descrittivi e vengono
# dall'anteprima ASCII di extract_item_icons.ps1, non dal ROM.
$ICON = @{ 0xD4 = 'spada'; 0xD5 = 'martello'; 0xD6 = 'pugnale'; 0xD7 = 'nunchaku';
           0xD8 = 'catena'; 0xD9 = 'arco'; 0xDA = 'elmo'; 0xDB = 'scudo';
           0xDC = 'guanto'; 0xDD = 'bacchetta'; 0xDE = 'anello'; 0xDF = 'corazza' }

$list = if ($Shops.Count -eq 1 -and $Shops[0] -eq 0) { 1..70 } else { $Shops }

foreach ($sid in $list) {
    if ($sid -ge $shopTypes.Count) { Write-Host ("shop `${0}: fuori tabella" -f $sid.ToString('X2')); continue }
    $t = [int]$shopTypes[$sid]
    $ptr = [int]$shopData[$sid*2] -bor ([int]$shopData[$sid*2 + 1] -shl 8)
    $off = $ptr - 0x8300
    Write-Host ''
    Write-Host ("negozio `${0} ({1})  ptr `${2} -> offset {3}" -f `
        $sid.ToString('X2'), $TYPE[$t], $ptr.ToString('X4'), $off) -ForegroundColor Cyan

    if ($t -eq 4 -or $t -eq 5) {
        # Clinica e locanda: i due byte SONO il prezzo, word LE. Vedi sopra.
        $p = [int]$shopData[$off] -bor ([int]$shopData[$off + 1] -shl 8)
        Write-Host ("  servizio, non listino: {0} GP  (byte `${1} `${2} = word LE)" -f `
            $p, $shopData[$off].ToString('X2'), $shopData[$off+1].ToString('X2'))
        continue
    }

    # SI FERMA AL PRIMO ZERO, non lo salta: ShopSelectBuyItem (bank_0E.asm:5024)
    # fa `BEQ @Done`. Conta, perche' le liste si SOVRAPPONGONO -- il negozio
    # d'armature di Coneria legge [44 45 46 00 B0] e i byte dopo lo zero
    # appartengono gia' alla lista del negozio successivo. Scorrendo tutti e
    # cinque uscirebbe un'armeria che vende CURE: credibile e falsa.
    for ($k = 0; $k -lt 5; $k++) {
        $iid = [int]$shopData[$off + $k]
        if ($iid -eq 0) { break }
        $nm = if ($names.ContainsKey($iid)) { $names[$iid] } else { '???' }
        $p = [int]$prices[$iid*2] -bor ([int]$prices[$iid*2 + 1] -shl 8)
        # L'icona: il 7o carattere del nome nel ROM. Qui il nome e' gia' ripulito,
        # quindi la si rilegge dall'header delle icone solo come intervallo.
        $kind = if ($iid -ge 0x1C -and $iid -lt 0x44) { 'arma' }
                elseif ($iid -ge 0x44 -and $iid -lt 0x6C) { 'armatura' }
                elseif ($iid -ge 0xB0) { 'magia' }
                else { 'oggetto' }
        Write-Host ("  `${0}  {1,-8}  {2,6} GP   ({3})" -f $iid.ToString('X2'), $nm, $p, $kind)
    }
}
