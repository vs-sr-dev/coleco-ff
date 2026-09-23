# extract_item_icons.ps1 -- le icone di TIPO degli oggetti, per il negozio.
#
# PERCHE' SERVONO, ed e' un prerequisito dell'interfaccia e non un ornamento.
# Il 7o byte di ogni nome non e' una lettera: e' l'icona del tipo. Senza, il
# negozio d'armi di Coneria mostra
#     Wooden / Small / Wooden / Rapier / Iron
# cioe' DUE VOCI IDENTICHE nella stessa lista ("Wooden" e' insieme lo
# WoodenStaff e i WoodenNunchucks). Fra le armature e' peggio: "Opal" cinque
# volte e "Silver" cinque volte. Costruire prima l'interfaccia e poi le icone
# vuol dire consegnare una lista in cui non si puo' scegliere.
#
# DOVE STANNO (fonte: il ROM, non un elenco)
#   LoadMenuCHR (bank_0F.asm:9856) mappa BANK_MENUCHR = $09 e copia 8 righe
#   (8 x 256 = 2048 byte) da $8800 alla PPU $0800. La PPU $0800 e' il tile $80
#   della pattern table 0, quindi:
#       tile $80+k  ->  bank_09.bin, offset $0800 + k*16
#   e le icone $D4-$E1 stanno a $0800 + ($D4-$80)*16 = $0D40.
#
# NON SI DA' PER BUONO CHE SIANO $D4-$E1: il commento di
# extract_item_names.ps1 lo dice, ma questo strumento lo MISURA sui 240 nomi
# veri prima di estrarre. Se il ROM usasse un altro intervallo, l'estrazione
# uscirebbe plausibile e sbagliata -- 14 tile di qualcos'altro, disegnate
# benissimo.

param(
    [string]$Root   = (Split-Path -Parent $PSScriptRoot),
    [string]$Disasm = 'FF1Disassembly-master\Final Fantasy Disassembly',
    [string]$Out    = 'src\ff1_item_icons.h',
    [switch]$Preview   # stampa le tile in ASCII: l'unico modo di sapere che
                       # sono spade e scudi e non 224 byte a caso
)

$ErrorActionPreference = 'Stop'

$dis   = Join-Path $Root $Disasm
$b09   = [System.IO.File]::ReadAllBytes((Join-Path $dis 'bank_09.bin'))
$b0A   = [System.IO.File]::ReadAllBytes((Join-Path $dis 'bank_0A.dat'))

# ---------------------------------------------------------------------------
#  1. MISURA: quali valori compaiono davvero come 7o byte dei nomi?
# ---------------------------------------------------------------------------
$PTR_TBL = 0x3700       # lut_ItemNamePtrTbl = $B700 nel banco $0A
$N_ITEMS = 240
$icons   = @{}
for ($i = 0; $i -lt $N_ITEMS; $i++) {
    $lo = [int]$b0A[$PTR_TBL + $i*2]
    $hi = [int]$b0A[$PTR_TBL + $i*2 + 1]
    $off = (($hi -shl 8) -bor $lo) - 0x8000
    if ($off -lt 0 -or $off + 6 -ge $b0A.Length) { continue }
    $c = [int]$b0A[$off + 6]        # il 7o carattere
    if ($icons.ContainsKey($c)) { $icons[$c]++ } else { $icons[$c] = 1 }
}
$iconKeys = @($icons.Keys | Sort-Object)
Write-Host "7o byte dei 240 nomi -- valori distinti e quante volte:"
foreach ($k in $iconKeys) {
    Write-Host ("  `${0}  x{1}" -f $k.ToString('X2'), $icons[$k])
}
$lo = [int]($iconKeys | Select-Object -First 1)
$hi = [int]($iconKeys | Select-Object -Last 1)
# Lo spazio ($FF nel charset FF1) non e' un'icona: e' "questo oggetto non ne ha".
$real = @($iconKeys | Where-Object { $_ -ge 0xD0 -and $_ -le 0xEF })
if ($real.Count -eq 0) { throw "nessun valore nell'intervallo delle icone: la fonte non e' quella che credo" }
$ICON_FIRST = [int]($real | Select-Object -First 1)
$ICON_LAST  = [int]($real | Select-Object -Last 1)
$ICON_COUNT = $ICON_LAST - $ICON_FIRST + 1
Write-Host ("icone vere: `${0}-`${1} ({2} tile)" -f `
    $ICON_FIRST.ToString('X2'), $ICON_LAST.ToString('X2'), $ICON_COUNT)

# ---------------------------------------------------------------------------
#  2. ESTRAZIONE: 2bpp NES -> 1bpp TMS
# ---------------------------------------------------------------------------
# Le icone sono glifi di testo: due colori bastano, come per il font del BIOS.
#
# QUI L'OR DEI DUE PIANI NON VA BENE, ed e' la trappola di questo estrattore.
# La strategia "acceso = non e' il colore 0", validata in [[asset_pipeline]]
# per gli sprite, accende TUTTO: nella pagina del font di FF1 il piano 1 e'
# $FF su 118 tile su 128, perche' il testo usa i colori 2 e 3 e non 0 e 1 --
# il fondo del riquadro e' il colore 2, l'inchiostro il 3. Il primo giro ha
# prodotto 12 quadrati pieni, che a occhio sono "grafica" e in ASCII no.
# L'inchiostro e' quindi il PIANO 0 da solo.
#
# Nelle due icone $DA e $DE il piano 1 ha qualche bit spento: sono i pixel di
# un terzo colore. In monocromia si perdono, ed e' una perdita accettabile su
# un glifo 8x8 -- ma va detta, non scoperta dopo.
$CHR_BASE = 0x0800 + ($ICON_FIRST - 0x80) * 16
$pattern  = New-Object byte[] ($ICON_COUNT * 8)
$shaded   = @()
for ($t = 0; $t -lt $ICON_COUNT; $t++) {
    $hasShade = $false
    for ($row = 0; $row -lt 8; $row++) {
        $p0 = [int]$b09[$CHR_BASE + $t*16 + $row]
        $p1 = [int]$b09[$CHR_BASE + $t*16 + 8 + $row]
        if ($p1 -ne 0xFF) { $hasShade = $true }
        $pattern[$t*8 + $row] = [byte]$p0
    }
    if ($hasShade) { $shaded += ('$' + ($ICON_FIRST + $t).ToString('X2')) }
}
if ($shaded.Count) {
    Write-Host ("  nota: {0} usano un terzo colore, perso in monocromia" -f ($shaded -join ', ')) -ForegroundColor Yellow
}

if ($Preview) {
    Write-Host ''
    Write-Host 'anteprima (## = pixel acceso):'
    for ($t = 0; $t -lt $ICON_COUNT; $t++) {
        Write-Host ("  tile `${0}" -f ($ICON_FIRST + $t).ToString('X2'))
        for ($row = 0; $row -lt 8; $row++) {
            $bits = [int]$pattern[$t*8 + $row]
            $s = '    '
            for ($x = 7; $x -ge 0; $x--) {
                if ($bits -band (1 -shl $x)) { $s += '##' } else { $s += '..' }
            }
            Write-Host $s
        }
    }
}

# ---------------------------------------------------------------------------
#  3. EMISSIONE
# ---------------------------------------------------------------------------
function Format-ByteArray([byte[]]$arr, [int]$perLine = 8) {
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

W "// AUTO-GENERATO da tools/extract_item_icons.ps1 -- non modificare a mano."
W "//"
W "// Le icone di TIPO degli oggetti: il 7o byte di ogni nome in item_names.h."
W "// Senza queste, due voci della stessa lista si leggono identiche -- il"
W "// negozio d'armi di Coneria mostrerebbe `"Wooden`" due volte."
W "//"
W "// Fonte: bank_09.bin (BANK_MENUCHR), offset `$0800 + (tile - `$80) * 16."
W "// LoadMenuCHR (bank_0F.asm:9856) copia quella zona alla PPU `$0800, cioe'"
W "// il tile `$80 della pattern table 0."
W "//"
W "// 2bpp NES -> 1bpp TMS con OR dei due piani: sono glifi di testo, due"
W "// colori bastano e vanno in tinta col font del BIOS."
W ""
W "#ifndef FF1_ITEM_ICONS_H"
W "#define FF1_ITEM_ICONS_H"
W ""
W ("#define FF1_ICON_FIRST   0x{0}   /* valore del 7o byte della prima icona */" -f $ICON_FIRST.ToString('X2'))
W ("#define FF1_ICON_LAST    0x{0}" -f $ICON_LAST.ToString('X2'))
W ("#define FF1_ICON_COUNT   {0}" -f $ICON_COUNT)
W "// Da byte del nome a indice di icona. Fuori intervallo = nessuna icona."
W "#define FF1_ICON_INDEX(c) ((unsigned char)((c) - FF1_ICON_FIRST))"
W "#define FF1_ICON_VALID(c) ((c) >= FF1_ICON_FIRST && (c) <= FF1_ICON_LAST)"
W ""
W "#ifdef FF1_ITEM_ICONS_DEFINE_DATA"
W "static const unsigned char ff1_item_icons[FF1_ICON_COUNT * 8] = {"
W (Format-ByteArray $pattern)
W "};"
W "#endif // FF1_ITEM_ICONS_DEFINE_DATA"
W "#endif // FF1_ITEM_ICONS_H"

$outPath = Join-Path $Root $Out
[System.IO.File]::WriteAllText($outPath, $sb.ToString())
Write-Host ''
Write-Host "scritto $outPath  ($($ICON_COUNT * 8) byte di pattern)"
