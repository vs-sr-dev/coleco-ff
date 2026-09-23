# build_all.ps1 -- build completa di una slice ColecoFF MegaCart
#
# UNICA FONTE DI VERITA' della mappa dei banchi. Se aggiungi un banco, lo
# aggiungi QUI e basta: la compilazione, i simboli e il packaging seguono.
#
# PERCHE' ESISTE (slice50)
#   La catena a mano era: compila 4 banchi dati -> genera 4 header di simboli
#   -> compila la slice -> genera i simboli svc_ -> compila gli overlay ->
#   impacchetta. Sei passi con un ordine OBBLIGATORIO, facilissimo da sbagliare
#   in silenzio: un header di simboli vecchio non da' errore di compilazione,
#   da' spazzatura a schermo tre ore dopo.
#
# L'ORDINE E' UN VINCOLO, NON UNA PREFERENZA
#   1. banchi DATI   -> devono esistere prima della slice, che ne include gli header
#   2. slice main    -> produce la .map da cui escono gli indirizzi delle svc_
#   3. overlay       -> compilati DOPO il main, perche' ne usano gli indirizzi
#   4. packaging
#   Gli overlay entrano a indirizzo COSTANTE ($C000), quindi il main non ha mai
#   bisogno della loro .map: nessuna dipendenza circolare. Ma il contrario si':
#   **ogni ricompilazione del main invalida gli overlay**, e per questo qui si
#   ricostruisce sempre tutto in sequenza.
#
# USO
#   .\build_all.ps1 -Slice slice49
#   .\build_all.ps1 -Slice slice49 -Run            # lancia CoolCV alla fine
#   .\build_all.ps1 -Slice slice49 -Snap           # MAME headless + screenshot
#   .\build_all.ps1 -Slice slice46 -Overlays ovl_demo:20
#   .\build_all.ps1                                # la slice corrente, overlay compresi
#
# Prima della prima build servono gli asset: tools\import_assets.ps1 (BYOA).

param(
    # Default = la slice corrente e i suoi overlay. Chi apre il repo deve poter
    # compilare il gioco senza sapere quale slice e' l'ultima.
    [string]$Slice = 'slice78',
    [int]$RomKB = 512,
    # Overlay da includere, come 'nomefile:banco' (senza estensione .c).
    # Es: -Overlays 'ovl_battle:20','ovl_shop:21'
    [string[]]$Overlays = @('ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23',
                            'ovl_menu:24','ovl_magic:25','ovl_talk:26','ovl_bridge:27'),
    # Sorgenti extra da linkare nella slice principale.
    # joy.asm da slice52: sostituisce joystick(3) della libreria, la cui tabella
    # di decodifica del tastierino finisce in rodata oltre $C000 e quindi si
    # legge come spazzatura mentre e' mappato un overlay.
    [string[]]$Extra = @('ay.asm', 'joy.asm'),
    # Definizioni extra per la sola slice principale, es. -Defines 'SPAWN_WORLD_MX=80'.
    # Servono alle build di PROVA: il binario che si gioca non le usa mai, e chi
    # legge un risultato deve sapere quale dei due sta guardando. Il nome della
    # ROM prodotta cambia (suffisso _t) proprio per non confonderli.
    [string[]]$Defines = @(),
    [switch]$Run,                  # apre CoolCV con la ROM prodotta
    [switch]$Snap,                 # MAME headless: guida gli input e salva PNG
    [switch]$RegenMaps,            # rigenera i blob dei quadranti OW
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$SRC   = Join-Path $Root 'src'
$BUILD = Join-Path $Root 'build'
$TOOLS = Join-Path $Root 'tools'
$CRT   = Join-Path $Root 'crt'

$env:PATH   = (Join-Path $Root 'z88dk\z88dk\bin') + ";$env:PATH"
$env:ZCCCFG = (Join-Path $Root 'z88dk\z88dk\lib\config\')

# =====================================================================
#  MAPPA DEI BANCHI -- modifica QUI per aggiungerne
# =====================================================================
# Kind:
#   'data'    = .c compilato con sgm_bank_crt0 (rombase $C000), solo dati;
#               i simboli col prefisso indicato finiscono in <name>_symbols.h
#   'blob'    = 16KB grezzi gia' pronti su disco (es. quadranti mappa OW)
#   'overlay' = .c di CODICE compilato con overlay_crt0, ingresso fisso $C000
#               (dichiarati via -Overlays, non qui)
#
# Banco 0  = meta' alta dell'immagine linkata (rodata della slice) -- implicito
# Banco 31 = banco fisso col codice (a 512KB) -- implicito
$BankMap = @(
    @{ N = 1; Name = 'intro_bank';    Kind = 'data'; Src = 'intro_bank.c';  Prefix = 'intro_'  },
    @{ N = 2; Name = 'gfx_bank';      Kind = 'data'; Src = 'gfx_bank.c';    Prefix = 'gfx_'    },
    @{ N = 3; Name = 'owmap_nw_bank'; Kind = 'blob'; File = 'owmap_nw_bank.bin' },
    @{ N = 4; Name = 'owmap_ne_bank'; Kind = 'blob'; File = 'owmap_ne_bank.bin' },
    @{ N = 5; Name = 'owmap_sw_bank'; Kind = 'blob'; File = 'owmap_sw_bank.bin' },
    @{ N = 6; Name = 'owmap_se_bank'; Kind = 'blob'; File = 'owmap_se_bank.bin' },
    @{ N = 8; Name = 'owgfx_bank';    Kind = 'data'; Src = 'owgfx_bank.c';  Prefix = 'owgfx_'  },
    @{ N = 9; Name = 'mapman_bank';   Kind = 'data'; Src = 'mapman_bank.c'; Prefix = 'mapman_' },
    @{ N =10; Name = 'song_bank';     Kind = 'data'; Src = 'song_bank.c';   Prefix = 'song_'   },
    @{ N =11; Name = 'btldata_bank';  Kind = 'data'; Src = 'btldata_bank.c';Prefix = 'btl_'    },
    @{ N =12; Name = 'mongfx_bank';   Kind = 'data'; Src = 'mongfx_bank.c'; Prefix = 'mongfx_' },
    # Nemici grandi, tagliati per pagina CHR e non per tipo di dato: una
    # formazione dichiara UNA pagina, quindi una battaglia mappa un banco solo.
    @{ N =13; Name = 'monlg_lo_bank'; Kind = 'data'; Src = 'monlg_lo_bank.c'; Prefix = 'monlglo_' },
    @{ N =14; Name = 'monlg_hi_bank'; Kind = 'data'; Src = 'monlg_hi_bank.c'; Prefix = 'monlghi_' },
    # Coneria a colori veri (slice63): pattern + color + TSA rimappata + la
    # MAPPA. Stanno insieme perche' durante il disegno si mappa un banco solo.
    @{ N =15; Name = 'towngfx_bank';  Kind = 'data'; Src = 'towngfx_bank.c'; Prefix = 'towngfx_' },
    # Oggetti e negozi (slice64): armi, armature, prezzi, liste dei negozi,
    # i 240 nomi veri e le 12 icone di tipo. Insieme perche' una riga di
    # listino li legge tutti -- vedi l'intestazione di itemdata_bank.c.
    @{ N =16; Name = 'itemdata_bank'; Kind = 'data'; Src = 'itemdata_bank.c'; Prefix = 'itemdata_' },
    # Le altre mappe standard (slice77): una mappa = un banco, stessa forma
    # del 15. I due piani del castello restano separati apposta: unire i
    # tileset costerebbe un calcolo in piu' per risparmiare 16KB su 512.
    @{ N =17; Name = 'castle1gfx_bank'; Kind = 'data'; Src = 'castle1gfx_bank.c'; Prefix = 'castle1gfx_' },
    @{ N =18; Name = 'castle2gfx_bank'; Kind = 'data'; Src = 'castle2gfx_bank.c'; Prefix = 'castle2gfx_' },
    @{ N =19; Name = 'tofgfx_bank';     Kind = 'data'; Src = 'tofgfx_bank.c';     Prefix = 'tofgfx_' }
)

# =====================================================================

function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }

function Invoke-Zcc([string[]]$zccArgs, [string]$what) {
    Push-Location $BUILD
    try {
        & zcc @zccArgs
        if ($LASTEXITCODE -ne 0) { throw "compilazione fallita: $what (zcc exit $LASTEXITCODE)" }
    } finally { Pop-Location }
}

$slicePath = Join-Path $SRC "$Slice.c"
if (-not (Test-Path $slicePath)) { throw "slice non trovata: $slicePath" }

# BYOA: i dati del gioco non stanno nel repository, li genera import_assets.ps1
# dal ROM di chi compila. Senza, zcc fallirebbe su un #include mancante venti
# righe di log piu' in basso; meglio dirlo qui, con la cura.
if (-not (Test-Path (Join-Path $BUILD 'assets.stamp'))) {
    throw ("asset di gioco assenti: prima esegui  .\tools\import_assets.ps1 -Rom <Final Fantasy (USA).nes>" +
           "  (vedi README, sezione Building)")
}

# ---------------------------------------------------------------------
# 1. Blob dei quadranti OW (opzionale)
# ---------------------------------------------------------------------
if ($RegenMaps) {
    Step "rigenerazione blob mappa OW"
    & (Join-Path $TOOLS 'split_ow_map.ps1') | Out-Null
}

# ---------------------------------------------------------------------
# 2. Banchi DATI -> .rom + header dei simboli
#    Vanno prima della slice: la slice include i loro _symbols.h.
# ---------------------------------------------------------------------
Step "banchi dati"
foreach ($b in $BankMap) {
    if ($b.Kind -ne 'data') { continue }
    # NB: la variabile NON puo' chiamarsi $src -- PowerShell non distingue
    # maiuscole e minuscole, quindi sovrascriverebbe $SRC (la cartella dei
    # sorgenti). Stessa famiglia di trappole di [[powershell-typed-param-shadow]].
    $srcFile = Join-Path $SRC $b.Src
    if (-not (Test-Path $srcFile)) { throw "sorgente del banco $($b.N) non trovato: $srcFile" }

    Invoke-Zcc @('+coleco', "-crt0=$CRT\sgm_bank_crt0", '-create-app', '-m',
                 '-o', $b.Name, $srcFile) "banco $($b.N) ($($b.Name))"

    # 6>$null: gen_bank_symbols usa Write-Host, che va sul flusso Information
    # e quindi ignora sia | Out-Null sia i filtri. Senza questo l'output della
    # build annega in decine di righe di simboli.
    $hdr = Join-Path $SRC "$($b.Name)_symbols.h"
    & (Join-Path $TOOLS 'gen_bank_symbols.ps1') `
        -Map (Join-Path $BUILD "$($b.Name).map") -Out $hdr -Prefix $b.Prefix 6>$null
    Write-Host ("  banco {0,2}  {1,-14} -> {2}" -f $b.N, $b.Name, (Split-Path $hdr -Leaf))
}

# I blob devono esistere: se mancano, meglio fermarsi ora che impacchettare
# una ROM con un quadrante di $FF (mappa vuota, sintomo identico al bug #1 di
# slice44 -- ore perse a cercarlo altrove).
foreach ($b in $BankMap) {
    if ($b.Kind -ne 'blob') { continue }
    $f = Join-Path $BUILD $b.File
    if (-not (Test-Path $f)) { throw "blob del banco $($b.N) mancante: $f  (usa -RegenMaps)" }
    $len = (Get-Item $f).Length
    if ($len -ne 16384) { throw "blob del banco $($b.N) ha $len byte, attesi 16384" }
    Write-Host ("  banco {0,2}  {1,-14} -> blob 16KB ok" -f $b.N, $b.Name)
}

# ---------------------------------------------------------------------
# 3. Slice principale
# ---------------------------------------------------------------------
Step "slice principale ($Slice)"
$mainArgs = @('+coleco', "-crt0=$CRT\sgm_megacart_crt0", '-create-app', '-m', '-o', $Slice, $slicePath)
foreach ($d in $Defines) {
    $mainArgs += "-D$d"
    Write-Host "  BUILD DI PROVA: -D$d" -ForegroundColor Yellow
}
foreach ($e in $Extra) { $mainArgs += (Join-Path $SRC $e) }
Invoke-Zcc $mainArgs "slice $Slice"

# Budget: CODE e RODATA condividono i 32KB dell'immagine linkata. CODE parte a
# $8000 e RODATA gli sta dietro sconfinando in $C000+ (banco 0). Il margine
# utile e' quanto manca a RODATA per toccare $FFC0 (zona trigger bank switch).
$map = Get-Content (Join-Path $BUILD "$Slice.map")
function MapSymIn($mapLines, $name) {
    # Le regex vanno in stringhe SINGLE-quoted: fra doppi apici PowerShell
    # interpreta "$(" come sotto-espressione e il parse fallisce.
    $rx = '^' + [regex]::Escape($name) + '\s+=\s+\$([0-9A-Fa-f]+)'
    foreach ($l in $mapLines) {
        $m = [regex]::Match($l, $rx)
        if ($m.Success) { return [Convert]::ToInt32($m.Groups[1].Value, 16) }
    }
    return $null
}
function MapSym($name) { return (MapSymIn $map $name) }
$codeHead = MapSym '__CODE_head'
$codeEnd  = MapSym '__CODE_END_tail'
$rodEnd   = MapSym '__RODATA_END_tail'
if ($codeHead -and $rodEnd) {
    $fixedFree = 0xC000 - $codeEnd      # spazio residuo nella finestra FISSA
    $free      = 0xFFC0 - $rodEnd       # spazio residuo prima della zona trigger
    Write-Host ("  CODE   {0:X4}-{1:X4}  ({2} byte)" -f $codeHead, $codeEnd, ($codeEnd - $codeHead))
    Write-Host ("  RODATA {0:X4}-{1:X4}" -f $codeEnd, $rodEnd)
    if ($fixedFree -ge 0) {
        Write-Host ("  margine finestra fissa: {0} byte" -f $fixedFree)
    } else {
        Write-Host ("  CODE sfora la finestra fissa di {0} byte -- serve un overlay" -f (-$fixedFree)) -ForegroundColor Red
    }
    # Indirizzi delle variabili che le sonde Lua leggono in RAM. Vengono dalla
    # .map, che cambia a OGNI ricompilazione: cablarli nello script Lua
    # significava leggere RAM di un'altra slice e credere ai numeri usciti.
    # E' successo con slice53 (audio_enabled letto all'indirizzo di slice52:
    # riportava audio spento mentre la musica suonava).
    # world_player_mx/my da slice58: la collisione in overworld si verifica
    # leggendo la POSIZIONE, non guardando lo schermo. Uno scroll che non si
    # muove e una mappa disegnata male si somigliano troppo a occhio.
    # town_cam_x/y da slice63: dicono se siamo DENTRO la citta' e dove guarda la
    # telecamera. Senza, la citta' e la overworld si confondono a occhio -- una
    # citta' disegnata male e una overworld in cui non si e' mai entrati in
    # citta' sono due schermate verdi.
    # town_mx/my, town_shop_id, town_shop_hits, town_warp_out da slice64: le
    # collisioni in citta' sono INVISIBILI a occhio. Un muro che ferma e un
    # comando ignorato danno la stessa schermata ferma, e un negozio calpestato
    # non ha ancora un'interfaccia da mostrare. Sono i tre casi tipici della
    # regola "se non si vede, mettilo in RAM e leggilo dalla sonda".
    $probeNames = @('audio_enabled', 'audio_bank', 'main_bank',
                    'sq1_st', 'sq2_st', 'tri_st',
                    'world_player_mx', 'world_player_my',
                    'town_cam_x', 'town_cam_y', 'town_total_shifts',
                    'town_mx', 'town_my',
                    'town_shop_id', 'town_shop_hits', 'town_warp_out',
                    # party_chr_size da slice65: il PASSO fra un personaggio e
                    # l'altro nel blocco del gruppo. Era cablato negli script
                    # Lua (44, poi 79) ed e' letteralmente la trappola numero 1
                    # del catalogo. Ora lo pubblica il gioco.
                    'party_chr_size',
                    # slice76: un dialogo e' fatto di pixel e di niente altro
                    # -- non muove il gruppo, non tocca l'oro, non cambia una
                    # statistica. Senza questi tre byte una corsa non saprebbe
                    # distinguere "ha parlato all'abitante giusto" da "non e'
                    # successo niente". Stesso caso di town_shop_id.
                    'town_talk_hits', 'town_talk_obj', 'town_talk_dlg',
                    'town_facing',
                    # slice77: in QUALE mappa si sta (0=Coneria 1=castello1F
                    # 2=castello2F 3=tempio) e quali effetti ha chiesto
                    # l'ultimo dialogo. Due mappe di castello sono due
                    # schermate che a occhio si somigliano: "sono salito al
                    # secondo piano" si asserisce da qui, non dai pixel.
                    'cur_map_slot', 'town_talk_fx',
                    # slice78: lo stato della scena del ponte (0 = mai vista,
                    # 1 = calpestato, 2 = fatta). E' l'unico modo di provare
                    # che la scena parte UNA VOLTA SOLA: la seconda volta che
                    # si passa sul ponte non succede niente, e "non succede
                    # niente" a schermo non si distingue da "non ci sono
                    # passato".
                    'bridgescene')
    $probeLines = @('-- AUTO-GENERATO da tools/build_all.ps1 -- non modificare a mano',
                    "-- slice: $Slice",
                    'return {')
    # Un simbolo MANCANTE va detto ad alta voce. Se la variabile e' locale a
    # main() non compare nella .map, la voce sparisce da probe_addrs.lua, e lo
    # script Lua legge `nil` -- che MAME converte in indirizzo 0 e restituisce
    # un byte del BIOS. Il risultato e' una sonda che riporta sempre lo stesso
    # valore, indistinguibile da un gioco fermo: in slice63 e' costato un giro
    # a credere che il personaggio non camminasse.
    $probeMissing = @()
    foreach ($pn in $probeNames) {
        $addr = MapSym "_$pn"
        if ($null -ne $addr) { $probeLines += ("  {0} = 0x{1:X4}," -f $pn, $addr) }
        else { $probeMissing += $pn }
    }
    $probeLines += '}'
    if ($probeMissing.Count -gt 0) {
        Write-Host ("  ATTENZIONE: sonde SENZA simbolo: {0}" -f ($probeMissing -join ', ')) -ForegroundColor Yellow
        Write-Host "    (variabile locale o rinominata? gli script Lua che la usano leggeranno spazzatura)" -ForegroundColor Yellow
    }
    [System.IO.File]::WriteAllLines((Join-Path $BUILD 'probe_addrs.lua'), $probeLines)
    Write-Host "  build/probe_addrs.lua rigenerato (sonde Lua)"

    if ($free -lt 0) {
        throw "RODATA arriva a $('{0:X4}' -f $rodEnd), oltre la zona trigger `$FFC0: sposta dati in un banco"
    } elseif ($free -lt 512) {
        Write-Host ("  ATTENZIONE: solo $free byte liberi prima di `$FFC0 -- sposta dati in un banco") -ForegroundColor Yellow
    } else {
        Write-Host ("  margine totale immagine: $free byte")
    }
}

# ---------------------------------------------------------------------
# 4. Overlay -- DOPO il main, perche' ne usano gli indirizzi
# ---------------------------------------------------------------------
$overlaySpecs = @()
foreach ($o in $Overlays) {
    if ($o -notmatch '^(.+):(\d+)$') { throw "-Overlays vuole 'nome:banco' (ricevuto '$o')" }
    $overlaySpecs += @{ Name = $Matches[1]; N = [int]$Matches[2] }
}

if ($overlaySpecs.Count -gt 0) {
    Step "simboli di servizio per gli overlay"
    # Le funzioni del banco fisso esportate agli overlay hanno prefisso svc_ e
    # NON sono static (devono comparire nella .map).
    & (Join-Path $TOOLS 'gen_bank_symbols.ps1') `
        -Map (Join-Path $BUILD "$Slice.map") `
        -Out (Join-Path $SRC 'main_symbols.h') -Prefix 'svc_' -Guard 'MAIN_SYMBOLS_H' 6>$null
    Write-Host "  src/main_symbols.h rigenerato da $Slice.map"

    Step "overlay di codice"
    foreach ($o in $overlaySpecs) {
        $srcFile = Join-Path $SRC "$($o.Name).c"   # mai $src: vedi sopra
        if (-not (Test-Path $srcFile)) { throw "overlay non trovato: $srcFile" }
        # I -Defines vanno ANCHE agli overlay (slice78). Prima no, e per
        # questo i semi delle build di prova erano dovuti nascere nella
        # finestra fissa: era l'unico posto che sapeva di essere una build di
        # prova. Adesso stanno in ovl_intro.c e non costano piu' niente alla
        # risorsa piu' scarsa del progetto.
        $ovlArgs = @('+coleco', "-crt0=$CRT\overlay_crt0", '-create-app', '-m',
                     '-o', $o.Name, $srcFile)
        foreach ($d in $Defines) { $ovlArgs += "-D$d" }
        Invoke-Zcc $ovlArgs "overlay $($o.Name)"

        # L'ingresso deve essere un JP a $C000 (file offset 0x4000), o il main
        # salterebbe dentro dati a caso.
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $BUILD "$($o.Name).rom"))
        if ($bytes[0x4000] -ne 0xC3) {
            throw "overlay $($o.Name): il primo byte a `$C000 e' 0x$($bytes[0x4000].ToString('X2')), atteso 0xC3 (JP)"
        }

        # La sezione DATA di un overlay NON viene mai inizializzata: non c'e'
        # crt0_init qui, il contenuto in ROM non viene copiato in RAM. Ogni
        # `static const` aggregato che il compilatore ci piazza dentro si legge
        # come spazzatura. La libreria ne mette ~20 byte suoi (ovl_audio,
        # validato, ne ha 21 e funziona); molto di piu' vuol dire che una
        # tabella dell'overlay e' finita li'. Vedi regola 4 in
        # [[code-overlay-architecture]].
        $omap  = Get-Content (Join-Path $BUILD "$($o.Name).map")
        $dHead = MapSymIn $omap '__DATA_head'
        $dEnd  = MapSymIn $omap '__DATA_END_tail'
        $rHead = MapSymIn $omap '__RODATA_head'
        $rEnd  = MapSymIn $omap '__RODATA_END_tail'
        $cEnd  = MapSymIn $omap '__CODE_END_tail'
        $dataLen = if ($null -ne $dHead -and $null -ne $dEnd) { $dEnd - $dHead } else { 0 }
        $ovlEnd  = if ($null -ne $rEnd) { $rEnd } else { $cEnd }
        Write-Host ("  banco {0,2}  {1,-14} -> ingresso `$C000 ok, CODE+RODATA {2} byte, {3} liberi nel banco" `
                    -f $o.N, $o.Name, ($ovlEnd - 0xC000), (0x10000 - $ovlEnd))
        if ($dataLen -gt 64) {
            Write-Host ("  ATTENZIONE: overlay $($o.Name) ha $dataLen byte di DATA non inizializzata -- " +
                        "una tabella static const e' finita li' e a runtime sara' spazzatura") -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------
# 5. Packaging MegaCart
# ---------------------------------------------------------------------
Step "packaging MegaCart ($RomKB KB)"
$bankArgs = @()
foreach ($b in $BankMap) {
    $file = if ($b.Kind -eq 'blob') { $b.File } else { "$($b.Name).rom" }
    $bankArgs += ("{0}={1}" -f $b.N, (Join-Path $BUILD $file))
}
foreach ($o in $overlaySpecs) {
    $bankArgs += ("{0}={1}" -f $o.N, (Join-Path $BUILD "$($o.Name).rom"))
}

# Suffisso _t sulle build di prova: un binario con lo spawn spostato non deve
# poter essere scambiato per quello che si gioca.
$romSuffix = if ($Defines.Count -gt 0) { '_t' } else { '' }
$outRom = Join-Path $BUILD "${Slice}_mc${RomKB}${romSuffix}.rom"
# 6>&1 porta il Write-Host di build_megacart nel flusso success, cosi' si puo'
# filtrare: interessano solo warning ed esito, non le 8 righe di splice.
& (Join-Path $TOOLS 'build_megacart.ps1') `
    -In (Join-Path $BUILD "$Slice.rom") -Out $outRom -RomKB $RomKB -Banks $bankArgs 6>&1 |
    Select-String -Pattern 'WARN|boot header|Wrote' | ForEach-Object { Write-Host ("  " + $_.Line) }

Write-Host ""
Write-Host "BUILD OK -> $outRom" -ForegroundColor Green

# ---------------------------------------------------------------------
# 6. Verifica opzionale
# ---------------------------------------------------------------------
if ($Snap) {
    Step "MAME headless + screenshot"
    . (Join-Path $TOOLS 'mame_path.ps1')
    $mame = Resolve-Mame
    $lua  = Join-Path $TOOLS 'mame_drive.lua'
    $dir  = Join-Path $BUILD "snap_$Slice"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    & $mame coleco -exp sgm -cart $outRom -rompath (Join-Path $Root 'mame_roms') `
        -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 60 `
        -autoboot_script $lua -snapshot_directory $dir | Out-Null
    Get-ChildItem -Recurse $dir -Filter *.png | ForEach-Object { Write-Host ("  " + $_.FullName) }
}

if ($Run) {
    Step "CoolCV"
    Get-Process CoolCV -ErrorAction SilentlyContinue | Stop-Process -Force
    $p = Start-Process -FilePath (Join-Path $Root 'CoolCV\CoolCV.exe') -ArgumentList $outRom -PassThru
    Write-Host ("  avviato (PID {0})" -f $p.Id)
}
