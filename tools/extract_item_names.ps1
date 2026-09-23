# extract_item_names.ps1 -- i 240 nomi degli oggetti, dalla tabella del ROM.
#
# PERCHE' ESISTE (slice63)
#   I nomi che c'erano nei commenti di src/data/shop_data.h e src/data/
#   weapon_data.h erano SBAGLIATI, e in modo coerente: entrambi i file
#   numeravano le armi da $00. Nel ROM le armi partono da $1C.
#
#   L'errore era sopravvissuto perche' la meta' ALTA dello spazio degli id era
#   giusta ($B0-$EF incantesimi): chi ha controllato a campione ha controllato
#   li'. La meta' bassa era spostata di $1C, e il sintomo sarebbe stato un
#   negozio di Coneria che vende bastoni magici -- credibile a schermo, e
#   scoperto solo confrontando i prezzi con quelli veri.
#
#   La prova che chiude la questione non e' un elenco su un sito: e' il ROM.
#   EquipShop_GiveItemToChar (bank_0E.asm:4534) converte l'id-oggetto in
#   valore di slot con  SBC #$1C-1  per le armi e  SBC #$44-1  per le
#   armature. Da li' escono le due costanti in fondo a questo file.
#
# LA TABELLA
#   lut_ItemNamePtrTbl = $B700 nel banco $0A (Constants.inc:452): 240 word LE
#   che puntano dentro lo stesso banco. Ogni nome e' 7 byte + terminatore.
#
# IL SETTIMO BYTE NON E' UNA LETTERA
#   E' l'icona del tipo di oggetto ($D4-$E1: spada, mazza, pugnale, armatura,
#   scudo...). Sul TMS9918 quelle tile non esistono, quindi qui diventa uno
#   spazio: "Wooden" + icona-nunchaku e "Wooden" + icona-armatura si leggono
#   entrambi "Wooden". E' una perdita REALE e va sanata quando il negozio avra'
#   tile proprie -- e' annotata in docs/Coleco_improvements.md.

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Bank = 'FF1Disassembly-master\Final Fantasy Disassembly\bank_0A.dat',
    [string]$Out  = 'src\data\item_names.h'
)

$ErrorActionPreference = 'Stop'

$bankPath = Join-Path $Root $Bank
$bytes    = [System.IO.File]::ReadAllBytes($bankPath)
if ($bytes.Length -ne 16384) { throw "bank_0A.dat ha $($bytes.Length) byte, attesi 16384" }

# $B700 nel banco mappato a $8000 = offset $3700 nel file.
$PTR_TBL  = 0x3700
$N_ITEMS  = 240
$NAME_LEN = 7          # caratteri visibili; +1 di terminatore nell'header

# Charset FF1: stesso di tools/extract_monsters.ps1 (righe 60-61), piu' le
# cifre. Tutto il resto -- icone comprese -- diventa spazio.
function Convert-FF1Char([byte]$c) {
    if ($c -ge 0x8A -and $c -le 0xA3) { return [char]([byte][char]'A' + $c - 0x8A) }
    if ($c -ge 0xA4 -and $c -le 0xBD) { return [char]([byte][char]'a' + $c - 0xA4) }
    if ($c -ge 0x80 -and $c -le 0x89) { return [char]([byte][char]'0' + $c - 0x80) }
    return ' '
}

$names = New-Object string[] $N_ITEMS
# L'ICONA VA CONSERVATA, NON SOLO IGNORATA. Fino a slice63 il 7o byte diventava
# uno spazio e finiva li': il nome restava leggibile e l'informazione spariva.
# Ma e' proprio quel byte a distinguere "Wooden"-nunchaku da "Wooden"-bastone e
# le cinque armature "Opal" fra loro, quindi senza di esso il negozio non ha
# modo di disegnare l'icona nemmeno avendone le tile. Esce come array
# parallelo: 0 = questo oggetto non ha icona.
$icons = New-Object byte[] $N_ITEMS
for ($id = 0; $id -lt $N_ITEMS; $id++) {
    $ptr = $bytes[$PTR_TBL + $id * 2] + $bytes[$PTR_TBL + $id * 2 + 1] * 256
    $off = $ptr - 0x8000
    if ($off -lt 0 -or $off -ge 16384) { throw ("item {0}: puntatore fuori banco (0x{1:X4})" -f $id, $ptr) }
    $s = ''
    for ($k = 0; $k -lt $NAME_LEN; $k++) {
        $c = $bytes[$off + $k]
        if ($c -eq 0) { break }
        $s += (Convert-FF1Char $c)
    }
    $names[$id] = $s.TrimEnd()
    $ic = [int]$bytes[$off + 6]
    if ($ic -ge 0xD4 -and $ic -le 0xDF) { $icons[$id] = [byte]$ic } else { $icons[$id] = 0 }
}

# Controllo di sanita': se questi tre non tornano, la tabella e' disallineata e
# tutto il resto e' spazzatura plausibile. Meglio fermarsi qui che generare.
$checks = @{ 0x1C = 'Wooden'; 0x1F = 'Rapier'; 0x44 = 'Cloth' }
foreach ($id in $checks.Keys) {
    if ($names[$id] -ne $checks[$id]) {
        throw ("controllo fallito: item `${0:X2} e' '{1}', atteso '{2}'" -f $id, $names[$id], $checks[$id])
    }
}

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "// AUTO-GENERATO da tools/extract_item_names.ps1 -- non modificare a mano."
W "// Fonte: lut_ItemNamePtrTbl (`$B700, banco `$0A del ROM FF1)."
W "//"
W "// I NOMI VENGONO DAL ROM, non dai commenti degli altri estrattori: quelli di"
W "// shop_data.h e weapon_data.h numerano le armi da `$00 e SBAGLIANO. Nel ROM le"
W "// armi partono da `$1C. Vedi l'intestazione dell'estrattore."
W ""
W "#ifndef FF1_ITEM_NAMES_H"
W "#define FF1_ITEM_NAMES_H"
W ""
W "#define FF1_ITEM_COUNT     $N_ITEMS"
W "#define FF1_ITEM_NAME_LEN  $($NAME_LEN + 1)   /* 7 caratteri + terminatore */"
W ""
W "// ---- lo spazio degli id, come lo usa il ROM -------------------------"
W "// La conversione non e' inventata: EquipShop_GiveItemToChar la fa con"
W "//   SBC #`$1C-1  (armi)  e  SBC #`$44-1  (armature),  bank_0E.asm:4534/4554."
W "// Il valore di slot e' 1-based e 0 vuol dire casella vuota; ReadjustEquipStats"
W "// gli toglie 1 prima di indicizzare lut_Weapons / lut_Armor."
W "#define FF1_ITEM_KEY_BASE     0x00   /* `$00-`$1B oggetti chiave e consumabili */"
W "#define FF1_ITEM_WEAPON_BASE  0x1C   /* `$1C-`$43  40 armi     */"
W "#define FF1_ITEM_ARMOR_BASE   0x44   /* `$44-`$6B  40 armature */"
W "#define FF1_ITEM_GOLD_BASE    0x6C   /* `$6C-`$AF  importi in oro: i prezzi di"
W "                                        locanda/clinica/carovana, NON oggetti */"
W "#define FF1_ITEM_SPELL_BASE   0xB0   /* `$B0-`$EF  64 incantesimi */"
W ""
W "#define FF1_ITEM_IS_WEAPON(id) ((id) >= 0x1C && (id) < 0x44)"
W "#define FF1_ITEM_IS_ARMOR(id)  ((id) >= 0x44 && (id) < 0x6C)"
W "#define FF1_ITEM_IS_SPELL(id)  ((id) >= 0xB0 && (id) < 0xF0)"
W "// id-oggetto -> valore da scrivere nella casella di equipaggiamento"
W "#define FF1_ITEM_TO_WEAPON_SLOT(id) ((unsigned char)((id) - 0x1B))"
W "#define FF1_ITEM_TO_ARMOR_SLOT(id)  ((unsigned char)((id) - 0x43))"
W "// e il ritorno, per stampare il nome di cio' che si ha addosso"
W "#define FF1_WEAPON_SLOT_TO_ITEM(v)  ((unsigned char)((v) + 0x1B))"
W "#define FF1_ARMOR_SLOT_TO_ITEM(v)   ((unsigned char)((v) + 0x43))"
W ""
W "#ifdef FF1_ITEM_NAMES_DEFINE_DATA"
W "// PIATTO di proposito: il nome di `id` sta a &ff1_item_names[id * 8]."
W "// Un array a due dimensioni finirebbe nella DATA (sccz80), che nei banchi e"
W "// negli overlay non viene mai inizializzata. Vedi [[slice62-intro-overlay]]."
W "static const char ff1_item_names[FF1_ITEM_COUNT * FF1_ITEM_NAME_LEN] = {"

for ($id = 0; $id -lt $N_ITEMS; $id++) {
    $n = $names[$id]
    $cells = @()
    for ($k = 0; $k -lt $NAME_LEN; $k++) {
        if ($k -lt $n.Length) { $cells += ("'" + $n[$k] + "'") } else { $cells += "' '" }
    }
    $cells += '0'
    $label = if ($n -eq '') { '(vuoto)' } else { $n }
    # La virgola in fondo NON e' facoltativa, e la sua assenza e' sopravvissuta
    # a slice63 intera: questo header non era incluso da nessuno, quindi non
    # era mai passato da un compilatore. Un file generato che nessuno compila
    # non e' "pronto", e' solo "scritto".
    W ("    " + ($cells -join ',') + ",  // `$" + $id.ToString('X2') + " " + $label)
}

W "};"
W ""
W "// L'icona di TIPO di ogni oggetto: il 7o byte del nome nel ROM, che qui"
W "// sopra e' diventato uno spazio. 0 = nessuna icona. Le tile stanno in"
W "// ff1_item_icons.h; l'indice nel pattern e' FF1_ICON_INDEX(valore)."
W "static const unsigned char ff1_item_icon[FF1_ITEM_COUNT] = {"
for ($row = 0; $row -lt $N_ITEMS; $row += 16) {
    $end = [Math]::Min($row + 16, $N_ITEMS) - 1
    $line = ($icons[$row..$end] | ForEach-Object { '0x' + $_.ToString('X2') }) -join ','
    W ("    $line,")
}
W "};"
W "#endif // FF1_ITEM_NAMES_DEFINE_DATA"
W ""
W "#endif // FF1_ITEM_NAMES_H"

$outPath = Join-Path $Root $Out
[System.IO.File]::WriteAllText($outPath, $sb.ToString())

Write-Host "scritto $outPath  ($N_ITEMS nomi, $($N_ITEMS * ($NAME_LEN + 1)) byte)"
Write-Host ("  controllo: `$1C='{0}'  `$1F='{1}'  `$44='{2}'  `$B0='{3}'" -f $names[0x1C], $names[0x1F], $names[0x44], $names[0xB0])
