# import_assets.ps1 -- BYOA: genera TUTTI i dati di gioco dal tuo Final Fantasy.
#
# Il repository non contiene nulla del gioco originale: grafica, mappe, musica,
# testi e tabelle escono da qui, a partire da due cose che porti tu:
#
#   1. il ROM NES di Final Fantasy (USA), file .nes (con o senza header iNES);
#   2. il disassembly commentato di Disch ("Final Fantasy Disassembly"),
#      scompattato in FF1Disassembly-master\Final Fantasy Disassembly\.
#      Serve per i .asm / .tbl che due estrattori leggono, e per i bin\*.
#
# COSA FA
#   a. controlla il ROM: 16 banchi PRG da 16KB, CRC32 del PRG = CEBD2A31;
#   b. controlla che i bank_XX.dat del disassembly siano gli stessi byte del ROM
#      (un disassembly di un'altra revisione darebbe dati sbagliati in silenzio);
#   c. scrive i bank_XX.bin che il disassembly non distribuisce (sono l'output
#      di ca65: qui si tagliano dal ROM, byte per byte identici);
#   d. lancia ogni estrattore con gli argomenti che il progetto usa -- questo
#      file E' l'elenco: se un generatore nuovo entra nella build, entra qui;
#   e. scrive build\assets.stamp, che build_all.ps1 controlla.
#
# USO
#   .\tools\import_assets.ps1 -Rom 'C:\roms\Final Fantasy (USA).nes'
#
# Scrive solo in: src\ff1_*.h, src\data\, src\songs\, data\, build\ e nei
# bank_XX.bin del disassembly. Sono tutti esclusi da git (.gitignore).

param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [string]$Root   = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
# Posizione FISSA: alcuni estrattori la assumono (e' una convenzione del repo).
$Disasm = Join-Path $Root 'FF1Disassembly-master\Final Fantasy Disassembly'
$TOOLS = Join-Path $Root 'tools'
$SRC   = Join-Path $Root 'src'
$BUILD = Join-Path $Root 'build'

# Come STRINGA: in PowerShell 5.1 un letterale 0xCEBD2A31 e' un Int32
# negativo, e il confronto con un CRC senza segno fallirebbe sempre.
$EXPECTED_PRG_CRC = 'CEBD2A31'
$BANK = 16384

function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }

# --- CRC32 (IEEE, lo stesso di zip / No-Intro) -------------------------------
# In C#: stesso problema dei letterali esadecimali, e 256KB di ciclo in
# PowerShell costerebbero secondi.
if (-not ('ColecoFF.Crc32' -as [type])) {
    Add-Type -TypeDefinition @'
namespace ColecoFF {
    public static class Crc32 {
        public static string Of(byte[] data, int offset, int count) {
            uint[] t = new uint[256];
            for (uint n = 0; n < 256; n++) {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                t[n] = c;
            }
            uint crc = 0xFFFFFFFFu;
            for (int i = offset; i < offset + count; i++) crc = t[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
            return (crc ^ 0xFFFFFFFFu).ToString("X8");
        }
    }
}
'@
}
function Get-Crc32([byte[]]$data, [int]$offset, [int]$count) { return [ColecoFF.Crc32]::Of($data, $offset, $count) }

# ---------------------------------------------------------------------
# a. il ROM
# ---------------------------------------------------------------------
Step "ROM"
if (-not (Test-Path -LiteralPath $Rom)) { throw "ROM non trovato: $Rom" }
$romBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Rom))
$prgOff = 0
if ($romBytes.Length -ge 16 -and $romBytes[0] -eq 0x4E -and $romBytes[1] -eq 0x45 -and
    $romBytes[2] -eq 0x53 -and $romBytes[3] -eq 0x1A) {
    $prgOff = 16
    if ($romBytes[6] -band 0x04) { $prgOff += 512 }   # trainer
    Write-Host ("  header iNES: {0} banchi PRG da 16KB, {1} CHR" -f $romBytes[4], $romBytes[5])
}
if ($romBytes.Length - $prgOff -lt 16 * $BANK) {
    throw ("il file ha {0} byte di PRG, ne servono {1}: non e' Final Fantasy (USA)" -f ($romBytes.Length - $prgOff), 16 * $BANK)
}
$crc = Get-Crc32 $romBytes $prgOff (16 * $BANK)
Write-Host ("  CRC32 del PRG: {0}" -f $crc)
if ($crc -ne $EXPECTED_PRG_CRC) {
    throw ("CRC32 del PRG {0}, atteso {1}: serve Final Fantasy (USA), non modificato" -f $crc, $EXPECTED_PRG_CRC)
}
Write-Host "  Final Fantasy (USA): ok" -ForegroundColor Green

function Get-RomBank([int]$n) {
    $b = New-Object byte[] $BANK
    [Array]::Copy($romBytes, $prgOff + $n * $BANK, $b, 0, $BANK)
    return ,$b
}

# ---------------------------------------------------------------------
# b + c. il disassembly
# ---------------------------------------------------------------------
Step "disassembly"
if (-not (Test-Path -LiteralPath (Join-Path $Disasm 'bank_0F.asm'))) {
    throw "disassembly non trovato in '$Disasm' (manca bank_0F.asm). Vedi README, sezione Building."
}
foreach ($f in 'table_standard.tbl', 'bank_0B.asm', 'bank_0E.asm', 'bin\0D_8000_scoredata.bin') {
    if (-not (Test-Path -LiteralPath (Join-Path $Disasm $f))) { throw "disassembly incompleto: manca $f" }
}
$written = 0
for ($n = 0; $n -lt 16; $n++) {
    $hex  = '{0:X2}' -f $n
    $romBank = Get-RomBank $n
    $dat  = Join-Path $Disasm "bank_$hex.dat"
    $bin  = Join-Path $Disasm "bank_$hex.bin"
    if (Test-Path -LiteralPath $dat) {
        $d = [System.IO.File]::ReadAllBytes($dat)
        if ($d.Length -ne $BANK -or (Get-Crc32 $d 0 $BANK) -ne (Get-Crc32 $romBank 0 $BANK)) {
            throw "bank_$hex.dat non coincide col ROM: il disassembly e' di un'altra revisione"
        }
    } else {
        # Senza .dat il banco e' sorgente (.asm): il suo .bin lo darebbe ca65,
        # qui lo si taglia dal ROM.
        [System.IO.File]::WriteAllBytes($bin, $romBank)
        $written++
    }
}
Write-Host ("  bank_XX.dat verificati, {0} bank_XX.bin scritti dal ROM" -f $written)

# ---------------------------------------------------------------------
# d. gli estrattori
# ---------------------------------------------------------------------
Step "estrattori"
foreach ($d in (Join-Path $SRC 'data'), (Join-Path $SRC 'songs'), (Join-Path $Root 'data'), $BUILD, (Join-Path $BUILD 'data')) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$failed = @()
function Run([string]$name, [scriptblock]$sb) {
    try {
        & $sb *>&1 | Out-Null
        Write-Host ("  ok    {0}" -f $name)
    } catch {
        Write-Host ("  ERR   {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        $script:failed += $name
    }
}
$T = $TOOLS
$D = $Disasm

# Overworld
Run 'overworld: tile e colori'      { & "$T\extract_ow_colors.ps1"     -Disasm $D -Out "$SRC\ff1_owgfx.h" }
Run 'overworld: tile del ponte'     { & "$T\extract_bridge_tile.ps1"   -Disasm $D -Out "$SRC\ff1_bridge_tile.h" }
Run 'overworld: mappa'              { & "$T\extract_ow_tilemap.ps1"    -Disasm $D -OutBin "$Root\data\ff1_ow_full.bin" -OutHdrDir $SRC }
Run 'overworld: quadranti 3-6'      { & "$T\split_ow_map.ps1"          -In "$Root\data\ff1_ow_full.bin" -OutDir $BUILD }
Run 'overworld: incontri'           { & "$T\extract_encounter_data.ps1" -Disasm $D -OutHdr "$SRC\ff1_encounter.h" }
Run 'overworld: mapman'             { & "$T\extract_mapman_v3.ps1"     -Disasm $D -Out "$SRC\ff1_mapman_flat.h" }
# Mappe standard: una mappa = un banco. MapId/TeleId sono quelli del NES.
Run 'mappa: Coneria'                { & "$T\extract_sm_colors.ps1" -Disasm $D -OutHdr "$SRC\ff1_towngfx.h"    -Tileset 0 -MapId 0  -Prefix TOWNGFX    -TeleId 1 }
Run 'mappa: castello 1F'            { & "$T\extract_sm_colors.ps1" -Disasm $D -OutHdr "$SRC\ff1_castle1gfx.h" -Tileset 1 -MapId 8  -Prefix CASTLE1GFX -TeleId 9 }
Run 'mappa: castello 2F'            { & "$T\extract_sm_colors.ps1" -Disasm $D -OutHdr "$SRC\ff1_castle2gfx.h" -Tileset 1 -MapId 24 -Prefix CASTLE2GFX -EntryX 12 -EntryY 18 }
Run 'mappa: Tempio dei Demoni'      { & "$T\extract_sm_colors.ps1" -Disasm $D -OutHdr "$SRC\ff1_tofgfx.h"      -Tileset 5 -MapId 12 -Prefix TOFGFX     -TeleId 13 }
# Battaglia
Run 'battaglia: sprite delle classi' { & "$T\extract_battle_sprites.ps1" -bankPath "$D\bank_09.bin" -outFile "$SRC\ff1_battle_sprites.h" }
Run 'battaglia: esultanza'          { & "$T\extract_cheer_sprites.ps1" -bankPath "$D\bank_09.bin" -outPath "$SRC\ff1_cheer_sprites.h" }
Run 'battaglia: mostri'             { & "$T\extract_monster_gfx.ps1"   -Disasm $D -OutHdr "$SRC\ff1_monster_gfx.h" }
Run 'battaglia: mostri grandi'      { & "$T\extract_monster_large.ps1" -Disasm $D -OutDir $SRC }
Run 'battaglia: IA nemica'          { & "$T\extract_enemy_ai.ps1" }
Run 'battaglia: livelli'            { & "$T\extract_levelup_data.ps1" -disasm $D -outPath "$SRC\data\levelup_data.h" }
# Oggetti, testi
Run 'oggetti: icone'                { & "$T\extract_item_icons.ps1" -Root $Root }
Run 'oggetti: nomi'                 { & "$T\extract_item_names.ps1" -Root $Root }
Run 'testi: dialoghi'               { & "$T\extract_dialogue.ps1" -Root $Root -Disasm $D -Maps 0,8,24,12 }
Run 'testi: pagine di storia'       { & "$T\extract_story.ps1" -Root $Root -Disasm $D }
Run 'testi: leggenda'               { & "$T\extract_intro_text.ps1" -Root $Root -Disasm $D }
Run 'teletrasporti'                 { & "$T\extract_teleports.ps1" -Rom "$D\bank_00.dat" -OutHdr "$SRC\data\teleport_data.h" }
Run 'scena del ponte'               { & "$T\extract_bridge_scene.ps1" -Root $Root -Disasm $D }
# Tabelle di gioco: prima in .asm (build\data), poi in header C.
Run 'tabelle: classi'               { & "$T\extract_class_data.ps1" -Bank00 "$D\bank_00.dat" -OutDir "$BUILD\data" }
Run 'tabelle: nemici'               { & "$T\extract_enemy_data.ps1" -EnemyBin "$D\bin\0C_8520_enemydata.bin" -NamesBin "$D\bin\0B_94E0_enemynames.bin" -TblStd "$D\table_standard.tbl" -OutDir "$BUILD\data" }
Run 'tabelle: magie'                { & "$T\extract_magic_data.ps1" -MagBin "$D\bin\0C_81E0_magicdata.bin" -Bank0E "$D\bank_0E.bin" -OutDir "$BUILD\data" }
Run 'tabelle: armi e armature'      { & "$T\extract_equip_data.ps1" -WepBin "$D\bin\0C_8000_weapondata.bin" -ArmBin "$D\bin\0C_8140_armordata.bin" -Bank0E "$D\bank_0E.bin" -OutDir "$BUILD\data" }
Run 'tabelle: negozi'               { & "$T\extract_shop_data.ps1" -ShopBin "$D\bin\0E_8300_shopdata.bin" -Bank0DBin "$D\bank_0D.bin" -OutDir "$BUILD\data" }
Run 'tabelle: header C'             { & "$T\import_ff1_data.ps1" -SrcDir "$BUILD\data" -OutDir "$SRC\data" }
# Musica: i brani che la build usa (song_bank.c). Gli altri si estraggono allo
# stesso modo quando entrano in tabella.
$SONGS = '41','42','44','47','48','4C','50','51','53','54'
foreach ($s in $SONGS) {
    Run "musica: sng$s" {
        & "$T\ff1_extract_song.ps1" -trackId ([Convert]::ToInt32($s, 16)) -outName "sng$s" `
            -dataPath "$D\bin\0D_8000_scoredata.bin" -bank0DPath "$D\bank_0D.bin" -outDir "$BUILD\data"
        Move-Item -Force (Join-Path "$BUILD\data" "sng${s}_song.c") (Join-Path "$SRC\songs" "sng$s.h")
    }
}

if ($failed.Count -gt 0) {
    throw ("{0} estrattori falliti: {1}" -f $failed.Count, ($failed -join ', '))
}

# ---------------------------------------------------------------------
# e. il timbro
# ---------------------------------------------------------------------
Set-Content -LiteralPath (Join-Path $BUILD 'assets.stamp') -Value ("PRG CRC32 " + $crc) -Encoding ASCII
Write-Host ""
Write-Host "ASSET OK -> ora: .\tools\build_all.ps1" -ForegroundColor Green
