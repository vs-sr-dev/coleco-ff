# extract_equip_data.ps1
#
# Estrae weapon + armor data + per-class equip permissions dalla disasm FF1 NES
# e produce annotated .asm da `include` in slice futuri (equip menu, battle).
#
# Sources:
#   bin/0C_8000_weapondata.bin  = 40 weapons * 8 byte = 320 byte
#   bin/0C_8140_armordata.bin   = 40 armors  * 4 byte = 160 byte
#   bank_0E.bin[$3F50..$3F9F]   = lut_WeaponPermissions = 40 * word (LE)
#   bank_0E.bin[$3FA0..$3FEF]   = lut_ArmorPermissions  = 40 * word (LE)
#
# Layout WEAPON (8 byte/entry):
#   byte 0: hit% bonus
#   byte 1: damage bonus
#   byte 2: critical rate
#   byte 3: spell cast (item-cast magic ID; 0 = nessuno)
#   byte 4: elemental attack mask (ATKELE_xxx)
#   byte 5: category mask         (ATKAIL_xxx, anti-undead/giant/dragon/etc)
#   byte 6: graphic ID            (battle weapon sprite slot)
#   byte 7: palette ID
#
# Layout ARMOR (4 byte/entry):
#   byte 0: evade penalty (sottratto da char's evade)
#   byte 1: absorb boost
#   byte 2: elemental defense mask (DEFELE_xxx)
#   byte 3: spell cast (item-cast magic ID)
#
# Permissions WORD format:
#   bit set = class CANNOT equip. 12 class bits per word:
#     FT=$800 TH=$400 BB=$200 RM=$100 WM=$080 BM=$040
#     KN=$020 NJ=$010 MA=$008 RW=$004 WW=$002 BW=$001
#   Per check: weapon_id index -> word -> AND class_bit -> != 0 means cannot.
#
# Output:
#   build/data/weapon_data_7800.asm
#   build/data/armor_data_7800.asm

param(
    [string]$WepBin   = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_8000_weapondata.bin",
    [string]$ArmBin   = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0C_8140_armordata.bin",
    [string]$Bank0E   = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_0E.bin",
    [string]$OutDir   = "$PSScriptRoot\..\build\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$NWEAP = 40
$NARM  = 40
$WPN_PERM_OFS = 0x3F50    # in bank_0E.bin
$ARM_PERM_OFS = 0x3FA0    # in bank_0E.bin

$wepBytes  = [System.IO.File]::ReadAllBytes($WepBin)
$armBytes  = [System.IO.File]::ReadAllBytes($ArmBin)
$bank0EArr = [System.IO.File]::ReadAllBytes($Bank0E)   # NB: NON usare $bank0E -- collide con param [string]$Bank0E (forced coercion -> byte[] diventa stringa, BUG sottile)

if ($wepBytes.Length -ne ($NWEAP * 8)) {
    throw "weapon bin size unexpected: $($wepBytes.Length) (expected $($NWEAP * 8))"
}
if ($armBytes.Length -ne ($NARM * 4)) {
    throw "armor bin size unexpected: $($armBytes.Length) (expected $($NARM * 4))"
}

# Pretty names per ID (loose -- mostly from common FF1 ROM order, useful as comment).
# Le slot $00..$27 sono i weapon ID standard NES.
$wepNames = @(
    'WoodenNunchucks','SmallKnife','WoodenStaff','Rapier',          # 00..03
    'IronHammer','ShortSword','HandAxe','Scimitar',                 # 04..07
    'IronNunchucks','LargeKnife','IronStaff','Sabre',               # 08..0B
    'LongSword','GreatAxe','Falchion','SilverKnife',                # 0C..0F
    'SilverSword','SilverHammer','SilverAxe','FlameSword',          # 10..13
    'IceSword','DragonSword','GiantSword','SunSword',               # 14..17
    'CoralSword','WereSword','RuneSword','PowerStaff',              # 18..1B
    'LightAxe','HealStaff','MageStaff','Defense',                   # 1C..1F
    'WizardStaff','Vorpal','CatClaw','ThorHammer',                  # 20..23
    'BaneSword','Katana','Xcalbur','Masamune'                       # 24..27
)
$armNames = @(
    'Cloth','WoodenArmor','ChainArmor','IronArmor',                 # 00..03
    'SteelArmor','SilverArmor','FlameArmor','IceArmor',             # 04..07
    'OpalArmor','DragonArmor','Copper(Bracelet)','Silver(Bracelet)',# 08..0B
    'Gold(Bracelet)','Opal(Bracelet)','Diamond(Bracelet)','Zeus(Bracelet)',# 0C..0F
    'Power(Bracelet)','ProCape','WoodenShield','IronShield',        # 10..13
    'SilverShield','FlameShield','IceShield','OpalShield',          # 14..17
    'AegisShield','BuckleShield','Cap','WoodenHelm',                # 18..1B
    'IronHelm','SilverHelm','OpalHelm','Heal(Helm)',                # 1C..1F
    'Ribbon','Gloves','CopperGauntlet','IronGauntlet',              # 20..23
    'SilverGauntlet','ZeusGauntlet','PowerGauntlet','DiamondGauntlet'# 24..27
)

# ---------------------------------------------------------------------------
# Pretty-print to console
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "FF1 Weapon Data + Permissions (40 entries):"
Write-Host "  ID  Name              Hit Dmg Crt Spl Ele Cat Gfx Pal | Permissions (cannot-equip mask)"
Write-Host "  --- ----------------- --- --- --- --- --- --- --- --- | -------------------------------"
for ($i = 0; $i -lt $NWEAP; $i++) {
    $b = $i * 8
    $permLo = [int]$bank0EArr[$WPN_PERM_OFS + $i * 2]
    $permHi = [int]$bank0EArr[$WPN_PERM_OFS + $i * 2 + 1]
    $perm = $permHi * 256 + $permLo
    $classes = @()
    if (($perm -band 0x800) -eq 0) { $classes += 'FT' }
    if (($perm -band 0x400) -eq 0) { $classes += 'TH' }
    if (($perm -band 0x200) -eq 0) { $classes += 'BB' }
    if (($perm -band 0x100) -eq 0) { $classes += 'RM' }
    if (($perm -band 0x080) -eq 0) { $classes += 'WM' }
    if (($perm -band 0x040) -eq 0) { $classes += 'BM' }
    $canStr = if ($classes.Count -gt 0) { ($classes -join '/') } else { '(none)' }
    Write-Host ("  {0,3:X2} {1,-17} {2,3} {3,3} {4,3} {5,3} {6,3} {7,3} {8,3} {9,3} | base equip: {10}" `
        -f $i, $wepNames[$i], $wepBytes[$b+0], $wepBytes[$b+1], $wepBytes[$b+2], $wepBytes[$b+3], `
           $wepBytes[$b+4], $wepBytes[$b+5], $wepBytes[$b+6], $wepBytes[$b+7], $canStr)
}

Write-Host ""
Write-Host "FF1 Armor Data + Permissions (40 entries):"
Write-Host "  ID  Name              EvP Abs Ele Spl | Permissions"
Write-Host "  --- ----------------- --- --- --- --- | ------------"
for ($i = 0; $i -lt $NARM; $i++) {
    $b = $i * 4
    $permLo = [int]$bank0EArr[$ARM_PERM_OFS + $i * 2]
    $permHi = [int]$bank0EArr[$ARM_PERM_OFS + $i * 2 + 1]
    $perm = $permHi * 256 + $permLo
    $classes = @()
    if (($perm -band 0x800) -eq 0) { $classes += 'FT' }
    if (($perm -band 0x400) -eq 0) { $classes += 'TH' }
    if (($perm -band 0x200) -eq 0) { $classes += 'BB' }
    if (($perm -band 0x100) -eq 0) { $classes += 'RM' }
    if (($perm -band 0x080) -eq 0) { $classes += 'WM' }
    if (($perm -band 0x040) -eq 0) { $classes += 'BM' }
    $canStr = if ($classes.Count -gt 0) { ($classes -join '/') } else { '(none)' }
    Write-Host ("  {0,3:X2} {1,-17} {2,3} {3,3} {4,3} {5,3} | base equip: {6}" `
        -f $i, $armNames[$i], $armBytes[$b+0], $armBytes[$b+1], $armBytes[$b+2], $armBytes[$b+3], $canStr)
}

# ---------------------------------------------------------------------------
# Emit weapon_data_7800.asm
# ---------------------------------------------------------------------------
$out = "$OutDir\weapon_data_7800.asm"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; FF1 Weapon Data + Permissions  (auto-generated by tools/extract_equip_data.ps1)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Source: bin/0C_8000_weapondata.bin + bank_0E.bin[$3F50..$3F9F]')
[void]$sb.AppendLine('; 40 weapons total. 8 byte stats + 2 byte permissions = 10 byte/weapon.')
[void]$sb.AppendLine(';')
# Note e costanti che ColecoFF aveva aggiunto A MANO all'header generato
# (slice63): portate qui perche' la prima rigenerazione le avrebbe cancellate.
[void]$sb.AppendLine("; L'INDICE DI QUESTA TABELLA NON E' L'ID-OGGETTO (slice63). Qui l'indice e'")
[void]$sb.AppendLine("; 0-based (`$00 = WoodenNunchucks); l'id-oggetto della stessa arma e' `$1C.")
[void]$sb.AppendLine(';   indice = id_oggetto - $1C        (vedi src/data/item_names.h)')
[void]$sb.AppendLine(';   indice = valore_di_slot - 1      (ReadjustEquipStats, bank_0F.asm:10899)')
[void]$sb.AppendLine('; I nomi nei commenti qui sotto sono giusti.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Stat byte offsets (use these constants):')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('WPN_STAT_SIZE     = 8')
[void]$sb.AppendLine('WPN_STAT_HIT      = 0      ; hit% bonus')
[void]$sb.AppendLine('WPN_STAT_DMG      = 1      ; damage bonus')
[void]$sb.AppendLine('WPN_STAT_CRIT     = 2      ; critical rate')
[void]$sb.AppendLine('WPN_STAT_SPELL    = 3      ; item-cast magic id (0 = none)')
[void]$sb.AppendLine('WPN_STAT_ELEM     = 4      ; elemental attack mask  (ATKELE_xxx)')
[void]$sb.AppendLine('WPN_STAT_CATEGORY = 5      ; category mask  (ATKAIL_xxx anti-Undead/Dragon/etc)')
[void]$sb.AppendLine('WPN_STAT_GFX      = 6      ; battle sprite slot')
[void]$sb.AppendLine('WPN_STAT_PAL      = 7      ; battle sprite palette')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Class equip-bit mapping (from lut_ClassEquipBit, bank_0E.asm:9191):')
[void]$sb.AppendLine(';   FT=$800 TH=$400 BB=$200 RM=$100 WM=$080 BM=$040')
[void]$sb.AppendLine(';   KN=$020 NJ=$010 MA=$008 RW=$004 WW=$002 BW=$001')
[void]$sb.AppendLine('; Bit SET = class CANNOT equip this weapon.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('CLS_EQUIP_FT = $0800')
[void]$sb.AppendLine('CLS_EQUIP_TH = $0400')
[void]$sb.AppendLine('CLS_EQUIP_BB = $0200')
[void]$sb.AppendLine('CLS_EQUIP_RM = $0100')
[void]$sb.AppendLine('CLS_EQUIP_WM = $0080')
[void]$sb.AppendLine('CLS_EQUIP_BM = $0040')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('; NES BUG (FFOrigins canonical): "Elemental Swords"')
[void]$sb.AppendLine(';   ATKELE_xxx (byte 4) and ATKAIL_xxx (byte 5) bonus damage is')
[void]$sb.AppendLine(';   NEVER applied -- weapons coded with elemental/category bonus do')
[void]$sb.AppendLine(';   normal damage. Affected: FlameSwd, IceSwd, DragonSwd, GiantSwd,')
[void]$sb.AppendLine(';   SunSwd, WereSwd, RuneSwd, BaneSwd, Xcalbur, etc.')
[void]$sb.AppendLine(';   Fix policy: leave bytes as-is, fix in ported battle damage routine.')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('; Quante voci ha la tabella. Serve a chi indicizza da un byte di')
[void]$sb.AppendLine('; casella: un valore fuori scala leggerebbe i byte del vicino come statistiche.')
[void]$sb.AppendLine("FF1_N_WEAPONS = $NWEAP")
[void]$sb.AppendLine()
[void]$sb.AppendLine('lut_WeaponData:')

for ($i = 0; $i -lt $NWEAP; $i++) {
    $b = $i * 8
    $bytes = @()
    for ($j = 0; $j -lt 8; $j++) {
        $bytes += ('${0:X2}' -f $wepBytes[$b + $j])
    }
    $line = '    .byte ' + ($bytes -join ', ')
    $atkele = [int]$wepBytes[$b + 4]
    $atkail = [int]$wepBytes[$b + 5]
    $bugTag = ''
    if ($atkele -ne 0 -or $atkail -ne 0) {
        $bugTag = ('  ; [FFO] Elemental Swords: ELE=$' + ('{0:X2}' -f $atkele) + ' CAT=$' + ('{0:X2}' -f $atkail) + ' bonus NEVER applied')
    }
    [void]$sb.AppendLine(("$line ; `${0:X2} {1}{2}" -f $i, $wepNames[$i], $bugTag))
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; lut_WeaponPermissions: 40 word (LO/HI per byte ordering, little-endian)')
[void]$sb.AppendLine('; Idx by weapon_id * 2.')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('lut_WeaponPermissions:')

for ($i = 0; $i -lt $NWEAP; $i++) {
    $permLo = [int]$bank0EArr[$WPN_PERM_OFS + $i * 2]
    $permHi = [int]$bank0EArr[$WPN_PERM_OFS + $i * 2 + 1]
    $perm = $permHi * 256 + $permLo
    $classes = @()
    if (($perm -band 0x800) -eq 0) { $classes += 'FT' }
    if (($perm -band 0x400) -eq 0) { $classes += 'TH' }
    if (($perm -band 0x200) -eq 0) { $classes += 'BB' }
    if (($perm -band 0x100) -eq 0) { $classes += 'RM' }
    if (($perm -band 0x080) -eq 0) { $classes += 'WM' }
    if (($perm -band 0x040) -eq 0) { $classes += 'BM' }
    $canStr = if ($classes.Count -gt 0) { ($classes -join '/') } else { '(none base)' }
    [void]$sb.AppendLine(("    .byte `${0:X2}, `${1:X2}    ; `${2:X2} {3,-17} -> base equip: {4}" `
        -f $permLo, $permHi, $i, $wepNames[$i], $canStr))
}

Set-Content -Path $out -Value $sb.ToString() -Encoding ASCII
Write-Host ""
Write-Host "Wrote $out  ($($NWEAP * 10) byte data, annotated)."

# ---------------------------------------------------------------------------
# Emit armor_data_7800.asm
# ---------------------------------------------------------------------------
$out = "$OutDir\armor_data_7800.asm"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine('; FF1 Armor Data + Permissions  (auto-generated by tools/extract_equip_data.ps1)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Source: bin/0C_8140_armordata.bin + bank_0E.bin[$3FA0..$3FEF]')
[void]$sb.AppendLine('; 40 armor entries total. 4 byte stats + 2 byte permissions = 6 byte/armor.')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Stat byte offsets:')
[void]$sb.AppendLine('; ----------------------------------------------------------------------------')
[void]$sb.AppendLine('ARM_STAT_SIZE     = 4')
[void]$sb.AppendLine('ARM_STAT_EVDPEN   = 0      ; evade penalty (subtract from base evade)')
[void]$sb.AppendLine('ARM_STAT_ABSORB   = 1      ; absorb (defense) boost')
[void]$sb.AppendLine('ARM_STAT_ELEMDEF  = 2      ; elemental defense mask (DEFELE_xxx)')
[void]$sb.AppendLine('ARM_STAT_SPELL    = 3      ; item-cast magic id (0 = none)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Permissions: same encoding as weapons. Bit SET = cannot equip.')
[void]$sb.AppendLine('; ============================================================================')
[void]$sb.AppendLine()
[void]$sb.AppendLine("; L'INDICE DI QUESTA TABELLA NON E' L'ID-OGGETTO (slice63). Qui l'indice e'")
[void]$sb.AppendLine("; 0-based (`$00 = Cloth); l'id-oggetto della stessa armatura e' `$44.")
[void]$sb.AppendLine(';   indice = id_oggetto - $44        (vedi src/data/item_names.h)')
[void]$sb.AppendLine(';   indice = valore_di_slot - 1      (ReadjustEquipStats, bank_0F.asm:10937)')
[void]$sb.AppendLine(';')
[void]$sb.AppendLine('; Quante voci ha la tabella. Serve a chi indicizza da un byte di')
[void]$sb.AppendLine('; casella: un valore fuori scala leggerebbe i byte del vicino come statistiche.')
[void]$sb.AppendLine("FF1_N_ARMORS = $NARM")
[void]$sb.AppendLine()
[void]$sb.AppendLine('lut_ArmorData:')

for ($i = 0; $i -lt $NARM; $i++) {
    $b = $i * 4
    $bytes = @()
    for ($j = 0; $j -lt 4; $j++) {
        $bytes += ('${0:X2}' -f $armBytes[$b + $j])
    }
    $line = '    .byte ' + ($bytes -join ', ')
    [void]$sb.AppendLine(("$line                ; `${0:X2} {1}" -f $i, $armNames[$i]))
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('lut_ArmorPermissions:')

for ($i = 0; $i -lt $NARM; $i++) {
    $permLo = [int]$bank0EArr[$ARM_PERM_OFS + $i * 2]
    $permHi = [int]$bank0EArr[$ARM_PERM_OFS + $i * 2 + 1]
    $perm = $permHi * 256 + $permLo
    $classes = @()
    if (($perm -band 0x800) -eq 0) { $classes += 'FT' }
    if (($perm -band 0x400) -eq 0) { $classes += 'TH' }
    if (($perm -band 0x200) -eq 0) { $classes += 'BB' }
    if (($perm -band 0x100) -eq 0) { $classes += 'RM' }
    if (($perm -band 0x080) -eq 0) { $classes += 'WM' }
    if (($perm -band 0x040) -eq 0) { $classes += 'BM' }
    $canStr = if ($classes.Count -gt 0) { ($classes -join '/') } else { '(none base)' }
    [void]$sb.AppendLine(("    .byte `${0:X2}, `${1:X2}    ; `${2:X2} {3,-17} -> base equip: {4}" `
        -f $permLo, $permHi, $i, $armNames[$i], $canStr))
}

Set-Content -Path $out -Value $sb.ToString() -Encoding ASCII
Write-Host "Wrote $out  ($($NARM * 6) byte data, annotated)."
Write-Host ""

