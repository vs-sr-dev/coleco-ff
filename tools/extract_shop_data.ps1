# extract_shop_data.ps1
#
# Estrae:
#   1) Item prices table (240 entries x 2 byte LE = 480 byte) da bank_0D.bin
#      @$BC00 NES = file ofs $3C00.
#   2) Shop pointer + inventory lists (71 shops, ptr+5 byte list ciascuno)
#      da bin/0E_8300_shopdata.bin (384 byte: 142 byte ptr + 242 byte inline).
#   3) Shop types (Weapon/Armor/W-Magic/B-Magic/Clinic/Inn/Item/Caravan)
#      da lut_ShopTypes (bank_0F.asm:10376, 71 byte hardcoded).
#
# Indici ITEM nelle inventory list:
#   $00..$27  weapons (40)        -- nomi da lut_WeaponData (extract_equip)
#   $28..$4F  armors  (40)        -- nomi da lut_ArmorData
#   $50..$5F  items   (16, mostly HEAL/PURE/TENT/CABIN/HOUSE/SOFT/HERB/...)
#   $A0..$AF  clinic/inn services (variable)
#   $B0..$EF  spells  (64)        -- nomi da lut_MagicData
#
# Note: il LoadShopInventory NES legge sempre 5 byte fissi dal ptr; le liste
#       inline si sovrappongono per share + slot $00 marca slot vuoto.
#
# Note: il LoadPrice NES usa ROL trick per indicizzare il price table.
#       Indici 0..$EF mappano direttamente, table size = 240 entries.

param(
    [string]$ShopBin   = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0E_8300_shopdata.bin",
    [string]$Bank0DBin = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_0D.bin",
    [string]$OutDir    = "$PSScriptRoot\..\build\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# Shop bin layout
$NSHOPS         = 71
$PTR_TABLE_SIZE = $NSHOPS * 2          # 142 byte
$SHOP_NES_BASE  = 0x8300                # bank_0E mapped to $8000-$BFFF; this bin @ $8300
$SHOP_LIST_LEN  = 5                     # fixed 5-byte inventory per shop

# Item prices in bank_0D at NES $BC00 -> file offset $3C00
$PRICES_FILE_OFS = 0x3C00
$NPRICES         = 240                  # 0..$EF
$PRICES_SIZE     = $NPRICES * 2

$shopBytes   = [System.IO.File]::ReadAllBytes($ShopBin)
$bank0DBytes = [System.IO.File]::ReadAllBytes($Bank0DBin)

if ($shopBytes.Length -ne 384) {
    throw "shop bin size unexpected: $($shopBytes.Length) (expected 384)"
}

# ---------------------------------------------------------------------------
# Shop type table (lut_ShopTypes from bank_0F.asm:10376, hardcoded).
# Note: shop_id 0 unused (off-by-1 in NES code). 71 entries total.
# Type ID:  0=Weapon  1=Armor  2=W-Magic  3=B-Magic  4=Clinic  5=Inn  6=Item  7=Caravan
# ---------------------------------------------------------------------------
$shopTypes = @(
    0,0,0,0,0,0,0,0,0,0,                   # 0..9   Weapon (1st unused)
    1,1,1,1,1,1,1,1,1,1,1,                 # 10..20 Armor (extra to fix off-by-1)
    2,2,2,2,2,2,2,2,2,2,                   # 21..30 W-Magic
    3,3,3,3,3,3,3,3,3,3,                   # 31..40 B-Magic
    4,4,4,4,4,4,4,4,4,4,                   # 41..50 Clinic
    5,5,5,5,5,5,5,5,5,5,                   # 51..60 Inn
    6,6,6,6,6,6,6,6,6,7                    # 61..70 Item (9) + Caravan (1)
)
$typeNames = @('Weapon','Armor','W-Magic','B-Magic','Clinic','Inn','Item','Caravan')

# ---------------------------------------------------------------------------
# Item name resolver (best-effort, for annotation only).
# ---------------------------------------------------------------------------
$wepNames = @(
    'WoodNuncha','SmallKnife','WoodStaff','Rapier','IronHammer','ShortSwd','HandAxe','Scimitar',
    'IronNuncha','LargeKnife','IronStaff','Sabre','LongSword','GreatAxe','Falchion','SilverKnife',
    'SilverSwd','SilvHammer','SilverAxe','FlameSwd','IceSwd','DragonSwd','GiantSwd','SunSwd',
    'CoralSwd','WereSwd','RuneSwd','PowerStaff','LightAxe','HealStaff','MageStaff','Defense',
    'WizardStaff','Vorpal','CatClaw','ThorHammer','BaneSwd','Katana','Xcalbur','Masamune'
)
$armNames = @(
    'Cloth','WoodArm','ChainArm','IronArm','SteelArm','SilverArm','FlameArm','IceArm',
    'OpalArm','DragonArm','CuBrac','AgBrac','AuBrac','OpalBrac','DiaBrac','ZeusBrac',
    'PowerBrac','ProCape','WoodShld','IronShld','SilvShld','FlameShld','IceShld','OpalShld',
    'AegisShld','BuckleShld','Cap','WoodHelm','IronHelm','SilvHelm','OpalHelm','HealHelm',
    'Ribbon','Gloves','CuGaunt','FeGaunt','AgGaunt','ZeusGaunt','PwrGaunt','DiaGaunt'
)
$itemNames = @(
    'HEAL','PURE','SOFT','TENT','CABIN','HOUSE','BOTTLE','OXYALE',                 # $50..$57
    'CROWN','TNT','HERB','MYSTKEY','TNT?','ADAMANT','SLAB','RUBY',                  # $58..$5F
    'ROD','FLOATER','CHIME','CUBE','BOTTLE2','CANOE','LUTE','CRYSTAL',              # $60..$67
    'ITM68','ITM69','ITM6A','ITM6B','ITM6C','ITM6D','ITM6E','ITM6F'                 # $68..$6F unknown
)
$spellNames = @(
    'CURE','HARM','FOG','RUSE','FIRE','SLEP','LOCK','LIT',
    'LAMP','MUTE','ALIT','INVS','ICE','DARK','TMPR','SLOW',
    'CUR2','HRM2','AFIR','HEAL','FIR2','HOLD','LIT2','LOK2',
    'PURE','FEAR','AICE','AMUT','SLP2','FAST','CONF','ICE2',
    'CUR3','LIFE','HRM3','HEL2','FIR3','BANE','WARP','SLO2',
    'SOFT','EXIT','FOG2','INV2','LIT3','RUB','QAKE','STUN',
    'CUR4','HRM4','ARUB','HEL3','ICE3','BRAK','SABR','BLND',
    'LIF2','FADE','WALL','XFER','NUKE','STOP','ZAP','XXXX'
)

function ItemIdToName([int]$id) {
    if ($id -eq 0)                  { return '(empty)' }
    if ($id -ge 1 -and $id -le 0x27)   { return $wepNames[$id] }
    if ($id -ge 0x28 -and $id -le 0x4F){ return $armNames[$id - 0x28] }
    if ($id -ge 0x50 -and $id -le 0x6F){ return $itemNames[$id - 0x50] }
    if ($id -ge 0xA0 -and $id -le 0xAF){ return ('SVC$' + ('{0:X2}' -f $id)) }
    if ($id -ge 0xB0 -and $id -le 0xEF){ return $spellNames[$id - 0xB0] }
    return ('?$' + ('{0:X2}' -f $id))
}

# ---------------------------------------------------------------------------
# Parse item prices
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "FF1 Item Prices (240 items x 2 byte LE):"
Write-Host "  ID  Name           Price | ID  Name           Price"
Write-Host "  --- -------------- ----- | --- -------------- -----"

$prices = New-Object int[] $NPRICES
for ($i = 0; $i -lt $NPRICES; $i++) {
    $lo = [int]$bank0DBytes[$PRICES_FILE_OFS + $i * 2]
    $hi = [int]$bank0DBytes[$PRICES_FILE_OFS + $i * 2 + 1]
    $prices[$i] = $hi * 256 + $lo
}

# Pretty-print only nonzero prices, two columns
$nonZero = @()
for ($i = 0; $i -lt $NPRICES; $i++) {
    if ($prices[$i] -gt 0) {
        $nonZero += @{ Id = $i; Name = (ItemIdToName $i); Price = $prices[$i] }
    }
}
for ($i = 0; $i -lt $nonZero.Count; $i += 2) {
    $a = $nonZero[$i]
    $bLine = ''
    if ($i + 1 -lt $nonZero.Count) {
        $bb = $nonZero[$i + 1]
        $bLine = (" | {0,3:X2} {1,-14} {2,5}" -f $bb.Id, $bb.Name, $bb.Price)
    }
    Write-Host (("  {0,3:X2} {1,-14} {2,5}" -f $a.Id, $a.Name, $a.Price) + $bLine)
}

# ---------------------------------------------------------------------------
# Parse shops
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "FF1 Shops (71 entries, type + 5-byte inventory):"
Write-Host "  ID  Type     Ptr   | Items (id->name : price)"
Write-Host "  --- -------- ----- | -----------------------------------------------"

$shopList = @()
for ($s = 0; $s -lt $NSHOPS; $s++) {
    $pLo = [int]$shopBytes[$s * 2]
    $pHi = [int]$shopBytes[$s * 2 + 1]
    $nesAddr = $pHi * 256 + $pLo
    $fileOfs = $nesAddr - $SHOP_NES_BASE
    $inv = @()
    if ($fileOfs -ge 0 -and ($fileOfs + 5) -le $shopBytes.Length) {
        for ($k = 0; $k -lt 5; $k++) {
            $inv += [int]$shopBytes[$fileOfs + $k]
        }
    }
    $shopList += @{ Id = $s; NesAddr = $nesAddr; FileOfs = $fileOfs; Type = $shopTypes[$s]; Inv = $inv }
}

for ($s = 0; $s -lt $NSHOPS; $s++) {
    $sh = $shopList[$s]
    $invStr = @()
    foreach ($it in $sh.Inv) {
        $nm = ItemIdToName $it
        $pr = if ($it -lt $NPRICES) { $prices[$it] } else { 0 }
        $invStr += ("{0,3:X2}={1}({2})" -f $it, $nm, $pr)
    }
    Write-Host ("  {0,3:X2} {1,-8} `${2:X4} | {3}" -f $sh.Id, $typeNames[$sh.Type], $sh.NesAddr, ($invStr -join ' '))
}

# ---------------------------------------------------------------------------
# Emit shop_data_7800.asm
# ---------------------------------------------------------------------------
$out = "$OutDir\shop_data_7800.asm"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; FF1 Item Prices + Shop Data  (auto-generated by tools/extract_shop_data.ps1)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Source: bank_0D.bin[$3C00..$3DDF]    -> 480 byte item prices (240 x word LE)')
[void]$sb.AppendLine(';         bin/0E_8300_shopdata.bin     -> 142 byte ptr + 242 byte inline')
[void]$sb.AppendLine(';         lut_ShopTypes (bank_0F:10376) -> 71 byte type-per-shop')
[void]$sb.AppendLine(';')
# ColecoFF (slice63): questo blocco era stato corretto A MANO nell'header
# generato; la correzione vive ora qui. I nomi per-riga qui sotto restano
# quelli inferiti (sbagliati): il resolver non e' stato riscritto, il
# commento lo dichiara.
[void]$sb.AppendLine('; !! ATTENZIONE: I NOMI NEI COMMENTI QUI SOTTO SONO SBAGLIATI (slice63) !!')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Ogni riga di lut_ItemPrices e ogni inventario di negozio porta un nome')
[void]$sb.AppendLine('; inferito numerando le armi da $00. Nel ROM le armi partono da $1C, quindi')
[void]$sb.AppendLine("; OGNI nome in questo file e' spostato di `$1C. I BYTE sono giusti -- e' solo")
[void]$sb.AppendLine('; il commento a mentire. Per i nomi veri: src/data/item_names.h, generato')
[void]$sb.AppendLine('; dalla tabella del ROM (lut_ItemNamePtrTbl) e non da inferenza.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Item ID space VERO (fonte: EquipShop_GiveItemToChar, bank_0E.asm:4534):')
[void]$sb.AppendLine(';   $00-$1B key item e consumabili (LUTE, CROWN, ..., HEAL, PURE, TENT)')
[void]$sb.AppendLine(';   $1C-$43 armi     (40)   indice in lut_Weapons = id - $1C')
[void]$sb.AppendLine(';   $44-$6B armature (40)   indice in lut_Armor   = id - $44')
[void]$sb.AppendLine(';   $6C-$AF importi in oro ("10 G" ... "65000 G"): i prezzi di locanda,')
[void]$sb.AppendLine(';           clinica e carovana. NON sono oggetti.')
[void]$sb.AppendLine(';   $B0-$EF spells  (white L1=$B0..$B3, black L1=$B4..$B7, ...)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Shop types (0=W 1=A 2=Wmagic 3=Bmagic 4=Clinic 5=Inn 6=Item 7=Caravan)')
[void]$sb.AppendLine('; Shop_id 0 unused (NES off-by-1 quirk).')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('; Item prices table  (240 entries x 2 byte LE, item_id -> price)')
[void]$sb.AppendLine('; LoadPrice idiom (bank_0F:10573):')
[void]$sb.AppendLine(';   ASL A : carry-aware ROL into high byte -> 16-bit index into table')
[void]$sb.AppendLine('; Price = 0 -> not buyable (e.g. starting equipment, legendary, key items)')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('lut_ItemPrices:')
for ($i = 0; $i -lt $NPRICES; $i++) {
    $lo = [int]$bank0DBytes[$PRICES_FILE_OFS + $i * 2]
    $hi = [int]$bank0DBytes[$PRICES_FILE_OFS + $i * 2 + 1]
    $nm = ItemIdToName $i
    [void]$sb.AppendLine(("    .byte `${0:X2}, `${1:X2}    ; `${2:X2} {3,-14} = {4}" `
        -f $lo, $hi, $i, $nm, $prices[$i]))
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('; lut_ShopTypes  (71 byte, indexed by shop_id; idx 0 unused)')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('SHOPTYPE_WEAPON  = 0')
[void]$sb.AppendLine('SHOPTYPE_ARMOR   = 1')
[void]$sb.AppendLine('SHOPTYPE_WMAGIC  = 2')
[void]$sb.AppendLine('SHOPTYPE_BMAGIC  = 3')
[void]$sb.AppendLine('SHOPTYPE_CLINIC  = 4')
[void]$sb.AppendLine('SHOPTYPE_INN     = 5')
[void]$sb.AppendLine('SHOPTYPE_ITEM    = 6')
[void]$sb.AppendLine('SHOPTYPE_CARAVAN = 7')
[void]$sb.AppendLine()
[void]$sb.AppendLine('lut_ShopTypes:')
for ($s = 0; $s -lt $NSHOPS; $s++) {
    $tn = $typeNames[$shopTypes[$s]]
    [void]$sb.AppendLine(("    .byte `${0:X2}    ; shop `${1:X2} = {2}" -f $shopTypes[$s], $s, $tn))
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('; lut_ShopData  (142 byte ptr table + 242 byte inline lists)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; NOTA NES: ptrs sono indirizzi assoluti dentro bank_0E ($8300..$847F).')
[void]$sb.AppendLine(';           Le liste inline si SOVRAPPONGONO (sliding window) -- una stessa')
[void]$sb.AppendLine(';           sequenza di byte fornisce 5-byte inventory diversi a ptrs diversi.')
[void]$sb.AppendLine(';           Item $00 in lista = slot vuoto.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; PER 7800: andranno rebase-ati ai nuovi NES-equivalent indirizzi della cart.')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('lut_ShopData:')
[void]$sb.AppendLine('  ; --- pointer table (71 word LE) ---')
for ($s = 0; $s -lt $NSHOPS; $s++) {
    $sh = $shopList[$s]
    $invStr = @()
    foreach ($it in $sh.Inv) {
        $invStr += ('{0:X2}' -f $it)
    }
    $invNames = @()
    foreach ($it in $sh.Inv) {
        if ($it -eq 0) { $invNames += '-' } else { $invNames += (ItemIdToName $it) }
    }
    $pLo = [int]$shopBytes[$s * 2]
    $pHi = [int]$shopBytes[$s * 2 + 1]
    [void]$sb.AppendLine(("    .byte `${0:X2}, `${1:X2}    ; shop `${2:X2} {3,-8} -> `${4:X4} [{5}] = {6}" `
        -f $pLo, $pHi, $s, $typeNames[$sh.Type], $sh.NesAddr, ($invStr -join ' '), ($invNames -join ',')))
}
[void]$sb.AppendLine()
[void]$sb.AppendLine('  ; --- inline shop inventory blob (242 byte, sliding-window @ NES $838E..$847F) ---')
for ($p = $PTR_TABLE_SIZE; $p -lt $shopBytes.Length; $p += 16) {
    $end = [Math]::Min($p + 16, $shopBytes.Length)
    $hexes = @()
    for ($q = $p; $q -lt $end; $q++) {
        $hexes += ('${0:X2}' -f $shopBytes[$q])
    }
    [void]$sb.AppendLine(("    .byte " + ($hexes -join ', ') + "  ; @`$" + ('{0:X4}' -f ($SHOP_NES_BASE + $p))))
}

Set-Content -Path $out -Value $sb.ToString() -Encoding ASCII
Write-Host ""
Write-Host "Wrote $out  ($PRICES_SIZE byte prices + 71 byte types + $($shopBytes.Length) byte shop data = $($PRICES_SIZE + 71 + $shopBytes.Length) byte, annotated)."
Write-Host ""
