# run_regressions.ps1 -- rilancia TUTTE le corse di validazione su una slice.
#
# PERCHE' ESISTE (slice76)
#   Le corse sono undici e ognuna vuole la ROM giusta: sette girano su una
#   build di PROVA con un -Defines diverso, e tutte quelle build escono con lo
#   stesso nome (`<slice>_mc512_t.rom`), quindi **si sovrascrivono a vicenda**.
#   Farle a mano vuol dire ricompilare subito prima di ogni corsa e non
#   sbagliare mai l'ordine: e' la trappola scritta in cima a docs/next_session.md,
#   ed e' gia' costata una corsa letta sul binario sbagliato.
#
#   Qui l'ordine e' il codice. Ogni voce dice quale -Defines vuole, e la
#   compilazione e' fatta subito prima della sua corsa.
#
# USO
#   .\tools\run_regressions.ps1 -Slice slice76
#   .\tools\run_regressions.ps1 -Slice slice76 -Only npc,town

param(
    [string]$Slice = 'slice78',
    [string]$Root  = (Split-Path -Parent $PSScriptRoot),
    # Vuoto = Resolve-Mame (env MAME, tools\local.ps1, PATH).
    [string]$Mame  = '',
    [int]$RomKB    = 512,
    # Solo alcune corse, per nome. Vuoto = tutte.
    [string[]]$Only = @(),
    # ovl_bridge:27 mancava fino a slice78: la corsa del ponte partiva su una
    # ROM senza il banco 27, e il suo controllo sulla scena non poteva
    # accorgersene (bridgescene=2 si scrive PRIMA di entrare nell'overlay).
    [string[]]$Overlays = @('ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23',
                            'ovl_menu:24','ovl_magic:25','ovl_talk:26','ovl_bridge:27')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mame_path.ps1')
$Mame = Resolve-Mame $Mame
Set-Location $Root

# Define = $null -> la ROM VERA, senza suffisso _t.
$RUNS = @(
    @{ Name = 'npc';        Script = 'mame_drive_npc.lua';        Define = $null;          Secs = 200 },
    @{ Name = 'town';       Script = 'mame_drive_town.lua';       Define = $null;          Secs = 260 },
    @{ Name = 'menu';       Script = 'mame_drive_menu.lua';       Define = 'FORCE_MENU';   Secs = 260 },
    @{ Name = 'equip';      Script = 'mame_drive_equip.lua';      Define = 'FORCE_EQMENU'; Secs = 260 },
    @{ Name = 'menumagic';  Script = 'mame_drive_menumagic.lua';  Define = 'FORCE_MAGMENU';Secs = 260 },
    @{ Name = 'itemshop';   Script = 'mame_drive_itemshop.lua';   Define = 'FORCE_ITEM';   Secs = 260 },
    @{ Name = 'magicshop';  Script = 'mame_drive_magicshop.lua';  Define = 'FORCE_SHOP';   Secs = 260 },
    @{ Name = 'shop';       Script = 'mame_drive_shop.lua';       Define = 'FORCE_SHOP';   Secs = 260 },
    @{ Name = 'ailments';   Script = 'mame_drive_ailments.lua';   Define = 'FORCE_AIL';    Secs = 300 },
    @{ Name = 'playermagic';Script = 'mame_drive_playermagic.lua';Define = 'FORCE_SPELLS'; Secs = 420 },
    @{ Name = 'buffs';      Script = 'mame_drive_buffs.lua';      Define = 'FORCE_BUFF';   Secs = 300 },
    # slice77: la prima quest intera -- Re, Garland, principessa, LUTE, ponte.
    # E' la corsa piu' lunga del set: 75 passi di overworld piu' quattro mappe.
    @{ Name = 'quest';      Script = 'mame_drive_quest.lua';      Define = 'FORCE_QUEST';  Secs = 500 },
    # slice78: il ponte. Semina WPROG_BRIDGE e sposta lo spawn sulla riva sud,
    # cosi' la prova del ponte non rifa' la quest -- che ha gia' la sua corsa.
    @{ Name = 'bridge';     Script = 'mame_drive_bridge.lua';
       Define = @('FORCE_BRIDGE','SPAWN_WORLD_MX=152','SPAWN_WORLD_MY=154'); Secs = 300 }
)

$results = @()
foreach ($r in $RUNS) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $r.Name)) { continue }

    Write-Host ""
    Write-Host ("===== {0} =====" -f $r.Name) -ForegroundColor Cyan
    # MAI chiamarla $args: e' una variabile automatica di PowerShell (gli
    # argomenti non legati dello script) e lo splatting `@args` non passa
    # quello che ci si e' messo dentro -- il primo parametro finisce nel posto
    # sbagliato e l'errore parla di RomKB. Stessa famiglia di
    # [[powershell-typed-param-shadow]].
    # SPLATTING CON UNA TABELLA HASH, non con un array. Con l'array PowerShell
    # APPIATTISCE il valore di -Overlays (che e' a sua volta un array): la
    # chiamata diventa `-Overlays ovl_battle:20 ovl_intro:21 ...` e dal secondo
    # in poi i banchi si legano POSIZIONALMENTE agli altri parametri di
    # build_all -- il primo che capita e' -RomKB, che vuole un intero. L'errore
    # parla di RomKB e sembra un problema di questo script.
    $buildArgs = @{ Slice = $Slice; Overlays = $Overlays }
    if ($r.Define) { $buildArgs['Defines'] = @($r.Define) }
    # La compilazione e' PARTE della corsa, non un preludio: e' l'unica forma
    # in cui il binario provato e' per forza quello giusto.
    # 6>&1: build_all scrive con Write-Host, che va sul flusso Information e
    # NON finisce nella variabile. Senza la fusione questo controllo non ha
    # mai visto niente -- la corsa quest di slice77 e' partita su una ROM con
    # la finestra fissa sforata e ha stampato 60 rossi tutti falsi.
    $buildLog = & (Join-Path $Root 'tools\build_all.ps1') @buildArgs 6>&1
    $bad = $buildLog | Select-String -Pattern 'sfora la finestra fissa'
    if ($bad) {
        Write-Host "  BUILD ROTTA: $bad" -ForegroundColor Red
        $results += [pscustomobject]@{ Corsa = $r.Name; Esito = 'BUILD ROTTA'; Ok = 0; Falliti = 0 }
        continue
    }

    $suffix = if ($r.Define) { '_t' } else { '' }
    $rom = Join-Path $Root ("build\{0}_mc{1}{2}.rom" -f $Slice, $RomKB, $suffix)
    $dir = Join-Path $Root ("build\snap_reg_{0}" -f $r.Name)
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $log = & $Mame coleco -exp sgm -cart $rom -rompath (Join-Path $Root 'mame_roms') `
        -window -nofilter -skip_gameinfo -sound none -nothrottle `
        -seconds_to_run $r.Secs -autoboot_script (Join-Path $Root ('tools\' + $r.Script)) `
        -snapshot_directory $dir

    $sum = $log | Select-String -Pattern 'RIEPILOGO' | Select-Object -Last 1
    $ok = 0; $ko = 0
    if ($sum -and $sum.Line -match '(\d+)\s+ok,\s+(\d+)\s+falliti') {
        $ok = [int]$Matches[1]; $ko = [int]$Matches[2]
    }
    foreach ($l in ($log | Select-String -Pattern 'FALLITO')) { Write-Host ("  " + $l.Line) -ForegroundColor Red }
    if ($sum) { Write-Host ("  " + $sum.Line) -ForegroundColor $(if ($ko -eq 0) { 'Green' } else { 'Red' }) }
    else      { Write-Host "  nessun RIEPILOGO: lo script non e' arrivato in fondo" -ForegroundColor Yellow }
    $results += [pscustomobject]@{ Corsa = $r.Name; Esito = $(if ($sum) { if ($ko -eq 0) { 'verde' } else { 'ROSSO' } } else { 'INCOMPLETA' }); Ok = $ok; Falliti = $ko }
}

Write-Host ""
Write-Host "===== RIEPILOGO GENERALE =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
