-- mame_drive_battle.lua -- guida la ROM fino a un ENCOUNTER e fotografa la
-- schermata di battaglia, che da slice52 vive nell'overlay del banco 20.
--
-- Perche' non basta mame_drive.lua: quello si ferma in overworld. Qui serve
-- entrare in battaglia, e l'encounter e' probabilistico (rate 10/256 per
-- passo, e solo fuori dalla strada -- vedi [[ff1-ow-road-no-encounter]]).
-- Quindi si cammina verso est finche' la battaglia non parte davvero.
--
-- TRAPPOLA COSTATA UN GIRO A VUOTO: i campi input vanno cercati per PORTA e
-- nome, mai per solo nome. Nel driver coleco "P1 Button 1" esiste in
-- :STD_JOY1 ma anche in :DRIV_PEDAL1 (volante), e "P1 Down"/"P1 Right"
-- esistono sia in :STD_JOY1 sia in :SAC_JOY1 (Super Action Controller).
-- Iterare le porte con pairs() ha ordine imprevedibile, quindi meta' dei
-- comandi finiva su un controller che la ROM non legge: il personaggio non
-- si muoveva e sembrava un bug del gioco.
--
-- CORRISPONDENZA PULSANTI (verificata sul campo, non ovvia):
--   MAME ":STD_JOY1 :: P1 Button 1"    -> z88dk MOVE_FIRE2  (letto in modo joystick)
--   MAME ":STD_KEYPAD1 :: P1 Button 2" -> z88dk MOVE_FIRE1  (letto in modo tastierino)
--   cioe' sono INVERTITI rispetto ai nomi.
--
-- COME SI ACCORGE DI ESSERE IN BATTAGLIA
--   Non guardando lo schermo: leggendo la RAM. La slice scrive il magic
--   BATTLE_STATE_MAGIC ($B471) a $6000 (battle_state.h) prima di saltare
--   nell'overlay. E' lo stesso canale che l'overlay usa per lo stato, quindi
--   il test verifica anche quello.
--
-- Scatti prodotti:
--   1. overworld prima dell'encounter
--   2. schermata di battaglia (disegnata dal banco 20)
--   3. dopo DOWN DOWN: cursore comandi su DRINK
--   4. dopo il tasto 3 del tastierino: salto diretto al terzo personaggio
--   5. dopo FIRE1: messaggio del turno
--   6. dopo FIRE2: ritorno in overworld

-- BATTLE_HOLD=<frame>: invece della coreografia di input, resta in battaglia
-- per N frame senza toccare niente. Serve a registrare la musica di battaglia
-- (sng50 dura 2736 frame = ~45s) con -wavwrite, per farla ascoltare.
local HOLD = tonumber(os.getenv("BATTLE_HOLD")) or 0
-- Frame (dall'ingresso in battaglia) in cui confermare il riquadro di vittoria.
local VHOLD = tonumber(os.getenv("VICTORY_HOLD")) or 440
-- WALK_DIR=<campo MAME>: in che direzione cercare l'encounter. Non e' un
-- dettaglio, decide CHI si incontra: il dominio dipende dalle coordinate
-- (compute_domain), e da Coneria andare a est finisce in mare (dominio $42,
-- SAHAG e SHARK) mentre andare a nord resta su terra (dominio $24, IMP e
-- GrIMP -- cioe' la coppia che mostra lo swap di palette).
local WALK = os.getenv("WALK_DIR") or "P1 Right"
-- WALK_BACK/WALK_LEG: da slice58 l'overworld ha le COLLISIONI, e una sola
-- direzione fissa non basta piu'. Prima o poi si finisce contro il mare o una
-- montagna, e li' non ci si ferma soltanto: non si fa nemmeno il tiro
-- d'incontro, perche' il tiro e' legato al PASSO. Il driver restava a spingere
-- contro un ostacolo fino allo scadere del tempo e sembrava che gli incontri
-- fossero rotti.
-- Quindi si pattuglia: WALK_LEG passi in una direzione, altrettanti
-- nell'altra, all'infinito. Su un tratto percorribile di due caselle il
-- gruppo continua a fare passi -- ed e' il passo, non lo spostamento netto,
-- quello che conta.
local WALK_BACK = os.getenv("WALK_BACK") or "P1 Left"
-- La gamba dev'essere LUNGA, e questo e' il secondo modo di sbagliare: con
-- gambe corte il gruppo resta a pochi passi dallo spawn, cioe' SULLA STRADA,
-- dove il bit FIGHT e' spento per scelta del NES ([[ff1-ow-road-no-encounter]])
-- e quindi il tiro d'incontro non si fa nemmeno. Trenta passi bastano a
-- uscirne; l'inversione serve solo a non restare piantati contro il mare.
local WALK_LEG  = tonumber(os.getenv("WALK_LEG")) or 30
-- Gamba di RITORNO, di solito piu' corta: una pattuglia simmetrica non si
-- sposta, e per raggiungere un dominio diverso (cioe' nemici diversi) serve
-- deriva netta. Con 30 avanti e 6 indietro il gruppo avanza di 24 caselle per
-- ciclo e continua a fare passi anche quando sbatte contro qualcosa.
local WALK_LEG_BACK = tonumber(os.getenv("WALK_LEG_BACK")) or 6
-- SKIP_BATTLES=<n>: fuggi dai primi n incontri e fai la coreografia completa
-- solo sull'(n+1)-esimo. Serve a raggiungere formazioni diverse dalla prima.
--
-- Il PRIMO incontro di una partita e' DETERMINISTICO: get_battle_formation
-- incrementa battlecounter una volta per encounter, quindi a parita' di
-- dominio la prima estrazione da' sempre la stessa formazione. Da Coneria
-- verso nord esce sempre "IMP x3-5", che ha un tipo solo. Per esercitare il
-- caso a PIU' tipi -- due tacche di tile con due palette diverse, che e' il
-- meccanismo con cui FF1 distingue IMP da GrIMP -- bisogna arrivare almeno al
-- secondo incontro.
local SKIP = tonumber(os.getenv("SKIP_BATTLES")) or 0
local skipped = 0
-- BATTLES=<n>: quante battaglie combattere di seguito prima di uscire. Il
-- gruppo NON si cura fra una e l'altra -- gli HP vivono in party_state.h, che
-- sopravvive all'overlay -- quindi e' la via per vedere davvero la sconfitta.
local BATTLES = tonumber(os.getenv("BATTLES")) or 1
local battles_done = 0
local defeat_shot = false
local defeat_at = nil

-- Pulsazione di FIRE1 durante il combattimento (slice57). PULSE_EVERY va tenuto
-- sopra la durata di un messaggio a schermo (45 frame), se no una conferma
-- cadrebbe sempre dentro il ciclo bloccante e il round non avanzerebbe mai.
local PULSE_FROM  = tonumber(os.getenv("PULSE_FROM"))  or 160
local PULSE_EVERY = tonumber(os.getenv("PULSE_EVERY")) or 24
local PULSE_TO    = tonumber(os.getenv("PULSE_TO"))    or 1500

local frames = 0
local fields = {}
local phase  = "boot"
local t0     = 0
local shots  = 0

-- port = nome completo della porta (es. ":STD_JOY1"), name = nome del campo
local function find_field(port, name)
    local key = port .. "|" .. name
    if fields[key] ~= nil then return fields[key] end
    local p = manager.machine.ioport.ports[port]
    if p == nil then error("porta non trovata: " .. port) end
    local f = p.fields[name]
    if f == nil then error("campo non trovato: " .. port .. " :: " .. name) end
    fields[key] = f
    return f
end

local function hold(port, name, on)
    find_field(port, name):set_value(on and 1 or 0)
end

-- Nomi comodi -> (porta, campo)
local function joy(name, on)   hold(":STD_JOY1",    name, on) end
local function pad(name, on)   hold(":STD_KEYPAD1", name, on) end
local function fire1(on)       pad("P1 Button 2", on) end   -- si', invertiti
local function fire2(on)       joy("P1 Button 1", on) end

local function snap(tag)
    shots = shots + 1
    print(string.format("SNAP %d (%s) @frame %d", shots, tag, frames))
    manager.machine.video:snapshot()
end

local mem = manager.machine.devices[":maincpu"].spaces["program"]
local function u8(a)  return mem:read_u8(a) end
local function u16(a) return u8(a) + u8(a + 1) * 256 end

-- Indirizzi delle variabili del motore audio: NON cablati qui. Cambiano a ogni
-- ricompilazione, e leggerli all'indirizzo di una slice precedente da numeri
-- plausibili e falsi (con slice53 la sonda diceva "audio spento" mentre la
-- musica suonava). Li genera tools/build_all.ps1 dalla .map.
local PROBE = nil
do
    local ok, t = pcall(dofile, "build/probe_addrs.lua")
    if ok and type(t) == "table" then PROBE = t
    else print("ATTENZIONE: build/probe_addrs.lua non leggibile, sonda audio disattivata") end
end

-- Blocchi in RAM SGM: indirizzi FISSI per costruzione (battle_state.h,
-- party_state.h), questi si possono cablare.
-- battle_state_t slice53: magic(2) formation domain accent[6] turn cmd round(2) result
local BATTLE_MAGIC       = 0xB47E
local OFF_FORM, OFF_DOM  = 0x6002, 0x6003
local OFF_TURN, OFF_CMD  = 0x600A, 0x600B
local OFF_ROUND          = 0x600C
local OFF_RESULT         = 0x600E
local OFF_EXPTOT, OFF_GPTOT = 0x600F, 0x6011
local OFF_EXPAW, OFF_GPAW = 0x6013, 0x6015
local OFF_NEWLV          = 0x6017
-- slice55: formazione decodificata, in coda alla struct. I campi precedenti
-- non si sono spostati -- per questo gli offset di sopra sono ancora quelli.
local OFF_BTLTYPE   = 0x601B
local OFF_CHRPAGE   = 0x601C
local OFF_NORUN     = 0x601D
local OFF_NTYPES    = 0x601E
local OFF_TYPEGFX   = 0x601F   -- 4
local OFF_TYPEPAL   = 0x6023   -- 4
local OFF_TYPEENEMY = 0x6027   -- 4
-- slice56: type_tile_base si INSERISCE qui, e sposta in avanti di 4 tutto cio'
-- che segue. E' il motivo per cui il magic e' salito a $B476: senza, questo
-- script leggerebbe i nomi a partire da meta' di un altro campo e stamperebbe
-- spazzatura plausibile invece di dire che e' disallineato.
local OFF_TILEBASE  = 0x602B   -- 4
local OFF_TYPENAME  = 0x602F   -- 4 x 9
local OFF_NENEMIES  = 0x6053
local OFF_ENEMYTYPE = 0x6054   -- 9
local OFF_ENEMYHP   = 0x605D   -- 9 x 2
local OFF_FORMDATA  = 0x606F   -- 16
-- slice57
local OFF_PHASE     = 0x607F
local OFF_CURSORTGT = 0x6080
local OFF_CHRCMD    = 0x6081   -- 4
local OFF_CHRTGT    = 0x6085   -- 4
local OFF_CHRCHOSEN = 0x6089   -- 4
-- slice59: la coda dei turni. Di nuovo IN CODA, di nuovo perche' inserire in
-- mezzo sposterebbe tutti gli offset qui sopra.
local OFF_TURNORDER = 0x608D   -- 13
local OFF_CURTURN   = 0x609A
-- slice60: le posizioni dell'IA (9+9) e la sonda dei lanci.
local OFF_AIMAGPOS  = 0x609B   -- 9
local OFF_AIATKPOS  = 0x60A4   -- 9
local OFF_CASTCNT   = 0x60AD
local OFF_LASTSPELL = 0x60AE

-- party_state.h: magic(2) n(1) gp(3), poi 4 personaggi.
--
-- IL PASSO NON SI CABLA PIU' (slice65). Era 44, con l'equipaggiamento e' 79, e
-- cambiarlo nel gioco senza cambiarlo qui e' la trappola numero 1 del
-- catalogo -- gia' ricalpestata una volta col magic. Adesso il gioco lo
-- PUBBLICA in `party_chr_size` e questo script lo legge: un numero raccontato
-- dal programma non si puo' disallineare da quel programma.
-- Il ripiego a 79 serve solo se la sonda manca, e si fa sentire.
local PARTY_BASE   = 0x6100
local PARTY_MAGIC  = 0x9A1A
local CHR_SIZE     = 79
local CHR0         = PARTY_BASE + 6   -- magic(2) n(1) gp(3)

-- Il passo fra personaggi, letto dal gioco.
--
-- STA QUI, DOPO `local CHR_SIZE`, E NON PIU' IN ALTO. In Lua una funzione
-- definita PRIMA di un `local` non vede quel local: vede una globale con lo
-- stesso nome, che non esiste. Messa sopra, questa funzione confrontava il
-- valore letto con `nil`, e l'assegnamento finiva in una globale che nessuno
-- legge -- cioe' falliva in silenzio se non fosse stato per il format che ha
-- sollevato l'errore. Stessa famiglia dello scavalcamento dei parametri
-- tipizzati in PowerShell: il nome c'e', la variabile e' un'altra.
local function refresh_chr_size()
    if not (PROBE and PROBE.party_chr_size) then
        print("!! SONDA party_chr_size MANCANTE: uso il ripiego " .. CHR_SIZE ..
              " -- se il layout e' cambiato, i campi qui sotto non valgono")
        return
    end
    local v = mem:read_u8(PROBE.party_chr_size)
    -- Zero vuol dire che party_init non e' ancora girato: non e' un errore.
    if v ~= 0 and v ~= CHR_SIZE then
        print(string.format(
            "passo del personaggio: il gioco dice %d, lo script diceva %d -- uso quello del gioco",
            v, CHR_SIZE))
        CHR_SIZE = v
    end
end
local O_CLS, O_NAME   = 0, 2
local O_CURHP         = 12
local O_STR, O_AGL, O_INT, O_VIT, O_LUCK = 16, 17, 18, 19, 20
-- Sotto-statistiche EFFETTIVE (quelle che legge la battaglia) e, da slice65,
-- le BASE che stanno in coda: la differenza fra le due E' l'equipaggiamento,
-- quindi stamparle affiancate rende la formula verificabile a colpo d'occhio.
local O_DMG, O_HIT, O_ABSORB, O_EVADE, O_RESIST, O_MAGDEF = 21, 22, 23, 24, 25, 26
local O_MAXMP0        = 36
local O_DMG_B, O_HIT_B, O_EVADE_B = 44, 45, 46
local O_WEAPON, O_ARMOR = 47, 51
local O_EXP, O_LEVEL  = 9, 27

local function magic() return u16(0x6000) end

-- La formazione come il motore l'ha davvero generata. Si legge dalla RAM e non
-- dallo schermo: cosi' il test dice se la DECODIFICA e' giusta anche quando il
-- disegno non lo e', e i due difetti non si mascherano a vicenda.
local BTLTYPE_NAMES = {[0]="9small", [1]="4large", [2]="mix", [3]="fiend", [4]="chaos"}
local function dump_formation()
    local nty = u8(OFF_NTYPES)
    local nen = u8(OFF_NENEMIES)
    print(string.format("FORMAZIONE id=%02X dominio=%02X tipo=%s pagCHR=%d%s",
          u8(OFF_FORM), u8(OFF_DOM),
          BTLTYPE_NAMES[u8(OFF_BTLTYPE)] or ("?" .. u8(OFF_BTLTYPE)),
          u8(OFF_CHRPAGE), (u8(OFF_NORUN) ~= 0) and " NORUN" or ""))
    for t = 0, nty - 1 do
        local nm = ""
        for k = 0, 7 do
            local c = u8(OFF_TYPENAME + t * 9 + k)
            if c == 0 then break end
            nm = nm .. string.char(c)
        end
        local gfx = u8(OFF_TYPEGFX + t)
        -- conta quanti nemici in campo appartengono a questo tipo. Si scorrono
        -- tutti e 9 gli SLOT e non i primi `nen`: da slice56 il tipo "mix" mette
        -- i grandi negli slot 0-1 e i piccoli dal 2, quindi con un solo grande
        -- lo slot 1 resta vuoto e fermarsi a `nen` perderebbe l'ultimo piccolo.
        local n = 0
        for e = 0, 8 do if u8(OFF_ENEMYTYPE + e) == t then n = n + 1 end end
        local tb = u8(OFF_TILEBASE + t)
        print(string.format("  tipo %d  %-8s x%d  id=%3d  gfx=%d(%s)  pal=%d  tile $%02X x%d",
              t, nm, n, u8(OFF_TYPEENEMY + t), gfx,
              (gfx % 2 == 1) and "GRANDE" or "piccolo", u8(OFF_TYPEPAL + t),
              tb, (gfx % 2 == 1) and 36 or 16))
    end
    local hps = {}
    for e = 0, 8 do
        if u8(OFF_ENEMYTYPE + e) ~= 0xFF then
            hps[#hps + 1] = string.format("s%d:%d", e, u16(OFF_ENEMYHP + e * 2))
        end
    end
    print(string.format("  nemici in campo=%d  HP=[%s]", nen, table.concat(hps, " ")))
    print(string.format("  bottino: EXP=%d  GP=%d",
          u16(OFF_EXPTOT), u16(OFF_GPTOT)))
end

-- Quanti nemici sono ancora in piedi. Slot occupato E HP diversi da zero: e' la
-- stessa condizione di `enemy_alive` nell'overlay, e serve che resti tale --
-- se le due divergessero il test direbbe "vinto" mentre il gioco continua.
local function alive_count()
    local n = 0
    for e = 0, 8 do
        if u8(OFF_ENEMYTYPE + e) ~= 0xFF and u16(OFF_ENEMYHP + e * 2) ~= 0 then
            n = n + 1
        end
    end
    return n
end

-- Gli HP dei nemici nel tempo. E' la prova che il danno arriva davvero, letta
-- dalla RAM: se la formula sbagliasse ma il disegno fosse giusto (o viceversa)
-- guardando solo lo schermo i due difetti si maschererebbero a vicenda.
local function dump_enemy_hp(dt)
    local parts = {}
    for e = 0, 8 do
        if u8(OFF_ENEMYTYPE + e) ~= 0xFF then
            parts[#parts + 1] = string.format("s%d:%d", e, u16(OFF_ENEMYHP + e * 2))
        end
    end
    local php = {}
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        php[#php + 1] = string.format("c%d:%d", i, u16(CHR0 + i * CHR_SIZE + O_CURHP))
    end
    print(string.format("  dt=%4d  HP=[%s]  vivi=%d  round=%d  gruppo=[%s]",
          dt, table.concat(parts, " "), alive_count(), u16(OFF_ROUND),
          table.concat(php, " ")))
end

-- L'ordine di iniziativa (slice59). E' la sola cosa del round che a schermo
-- NON si vede: un ordine sbagliato somiglia in tutto a un ordine giusto. Va
-- quindi letto dalla RAM, e va controllato che sia una PERMUTAZIONE -- lo
-- scambio del NES lavora sul posto, e un indice fuori intervallo
-- duplicherebbe una voce facendo agire qualcuno due volte e qualcun altro mai.
local function dump_turn_order()
    local parts, seen, dup, nz = {}, {}, false, 0
    for k = 0, 12 do
        local v = u8(OFF_TURNORDER + k)
        if v >= 0x80 then parts[#parts + 1] = "C" .. (v - 0x80)
        else              parts[#parts + 1] = "e" .. v end
        if seen[v] then dup = true end
        seen[v] = true
        if v ~= 0 then nz = nz + 1 end
    end
    -- Tutti zeri = init_turn_order non e' ancora girata (il primo round si
    -- risolve solo quando tutti hanno scelto). Segnalarlo come duplicato
    -- sarebbe un falso allarme, e un test che grida al lupo si smette di
    -- leggerlo.
    if nz == 0 then
        print("  iniziativa=[non ancora mescolata]")
        return
    end
    print(string.format("  iniziativa=[%s]%s", table.concat(parts, " "),
          dup and "  *** VOCE DUPLICATA ***" or ""))
end

-- Stampa il gruppo come lo vede la RAM: e' la prova che
-- NewGame_LoadStartingStats e' stato replicato bene. Atteso per il gruppo di
-- default FT/TH/WM/BM: HP 35/30/28/25, e 2 MP solo a WM e BM.
local function dump_party()
    refresh_chr_size()
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d",
          u16(PARTY_BASE), PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE))
    local names = {"FT","TH","BB","RM","WM","BM"}
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        local b = CHR0 + i * CHR_SIZE
        local nm = ""
        for k = 0, 5 do
            local c = u8(b + O_NAME + k)
            if c == 0 then break end
            nm = nm .. string.char(c)
        end
        local cls = u8(b + O_CLS)
        print(string.format(
            "  CHR%d %-6s cls=%d(%s) HP=%3d STR=%2d AGL=%2d INT=%2d VIT=%2d LUCK=%2d MP1=%d",
            i + 1, nm, cls, names[cls + 1] or "??", u16(b + O_CURHP),
            u8(b + O_STR), u8(b + O_AGL), u8(b + O_INT), u8(b + O_VIT),
            u8(b + O_LUCK), u8(b + O_MAXMP0)) ..
              string.format("  L%d EXP=%d", u8(b + O_LEVEL),
                    u8(b + O_EXP) + u8(b + O_EXP + 1) * 256 + u8(b + O_EXP + 2) * 65536))
        -- Effettivo <- base + equipaggiamento. Stampati insieme perche' un
        -- danno "giusto" da solo non dice se il bonus e' stato applicato una
        -- volta o due: la base accanto lo dice.
        local w, a = {}, {}
        for k = 0, 3 do
            w[#w+1] = string.format("%02X", u8(b + O_WEAPON + k))
            a[#a+1] = string.format("%02X", u8(b + O_ARMOR + k))
        end
        print(string.format(
            "        dmg=%3d (base %3d)  hit=%3d (base %3d)  eva=%3d (base %3d)  abs=%3d res=%02X  armi[%s] armature[%s]",
            u8(b + O_DMG), u8(b + O_DMG_B), u8(b + O_HIT), u8(b + O_HIT_B),
            u8(b + O_EVADE), u8(b + O_EVADE_B), u8(b + O_ABSORB), u8(b + O_RESIST),
            table.concat(w, " "), table.concat(a, " ")))
    end
end

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1

    -- Legend + boot menu + class select: bastano fronti di FIRE1 ripetuti.
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
        return
    elseif frames == 2200 then
        fire1(false)
        phase = "walk"
        return
    end

    if phase == "walk" then
        if frames == 2300 then snap("overworld"); dump_party() end
        -- Fuori dalla strada, dove l'attributo FIGHT e' attivo.
        -- Un passo dura 10 frame (5 premuto, 5 rilasciato); una gamba della
        -- pattuglia e' WALK_LEG passi, cioe' WALK_LEG*10 frame.
        local cycle = (WALK_LEG + WALK_LEG_BACK) * 10
        local dir = ((frames % cycle) < WALK_LEG * 10) and WALK or WALK_BACK
        joy(WALK,      dir == WALK      and (frames % 10) < 5)
        joy(WALK_BACK, dir == WALK_BACK and (frames % 10) < 5)
        if magic() == BATTLE_MAGIC then
            joy(WALK, false); joy(WALK_BACK, false)
            phase = "battle"; t0 = frames
            defeat_shot = false; defeat_at = nil
            print(string.format("BATTLE ENTERED @frame %d  form=%02X dom=%02X",
                  frames, u8(OFF_FORM), u8(OFF_DOM)))
        elseif frames > 20000 then
            print("NESSUN ENCOUNTER ENTRO IL LIMITE")
            manager.machine:exit()
        end
        return
    end

    if phase == "battle" then
        local dt = frames - t0

        -- Incontro da saltare: si fugge subito con FIRE2 e si torna a
        -- camminare. Un dump comunque lo stampiamo: anche una formazione da
        -- cui si scappa dice se la decodifica ha funzionato.
        if skipped < SKIP then
            if dt == 60 then
                print(string.format("-- incontro saltato %d/%d --", skipped + 1, SKIP))
                dump_formation()
            elseif dt == 70 then fire2(true)
            elseif dt == 75 then fire2(false)
            elseif dt >= 140 and magic() ~= BATTLE_MAGIC then
                skipped = skipped + 1
                phase = "walk"
            end
            return
        end
        if dt % 30 == 0 and dt <= 330 then
            -- Prova che la musica di battaglia gira davvero dal banco 10
            -- mentre il primo piano e' il banco 20:
            --   bank=10, len=160 (SNG50_SQ1_LEN), idx che avanza, main=20.
            local pc = manager.machine.devices[":maincpu"].state["PC"].value
            if PROBE then
                -- ch_state_t: events(2) total(2) loop(2) idx(2) remaining(1)
                print(string.format(
                    "dt=%3d PC=%04X turn=%d cmd=%d | audio on=%d bank=%d main=%d  sq1: ev=%04X len=%d idx=%d",
                    dt, pc, u8(OFF_TURN), u8(OFF_CMD),
                    u8(PROBE.audio_enabled), u8(PROBE.audio_bank), u8(PROBE.main_bank),
                    u16(PROBE.sq1_st), u16(PROBE.sq1_st + 2), u16(PROBE.sq1_st + 6)))
            else
                print(string.format("dt=%3d PC=%04X turn=%d cmd=%d",
                      dt, pc, u8(OFF_TURN), u8(OFF_CMD)))
            end
        end

        if HOLD > 0 then
            if dt == 60 then snap("battaglia"); dump_formation() end
            if dt >= HOLD then
                print(string.format("HOLD finito a dt=%d (t=%.1fs dall'ingresso)", dt, dt / 59.92))
                manager.machine:exit()
            end
            return
        end

        -- La composizione si stampa a dt=60 e non all'ingresso: da slice55 la
        -- decodifica gira NELL'OVERLAY, quindi al momento in cui compare il
        -- magic non e' ancora avvenuta e si leggerebbero zeri.
        -- ---- coreografia del turno fisico (slice57) --------------------
        -- Il flusso non e' piu' "un FIRE1 e via": ogni personaggio conferma il
        -- COMANDO e poi il BERSAGLIO, e il round parte solo quando hanno scelto
        -- tutti e quattro. Scriverlo a tempi fissi vorrebbe dire indovinare
        -- quanto dura la risoluzione, che dipende da quanti nemici muoiono.
        --
        -- Quindi: una PULSAZIONE di FIRE1 a cadenza fissa. Durante la
        -- risoluzione l'overlay non legge il joystick (sono cicli bloccanti coi
        -- messaggi a schermo), quindi le pressioni che cadono li' si perdono
        -- invece di accumularsi -- ed e' esattamente il comportamento voluto:
        -- il driver non puo' correre piu' del gioco.
        -- La pulsazione si SOSPENDE appena il gruppo cade. Senza, la schermata
        -- di sconfitta veniva congedata dal primo FIRE1 che passava di li' --
        -- entro 24 frame -- e lo scatto riprendeva la overworld gia' tornata
        -- (uno schermo tutto verde, che sembrava un difetto di disegno e non
        -- era altro che l'erba).
        local pulsing = (dt >= PULSE_FROM and dt < PULSE_TO)
        if defeat_at and dt < defeat_at + 260 then pulsing = false end
        if pulsing then
            local k = (dt - PULSE_FROM) % PULSE_EVERY
            if     k == 0 then fire1(true)
            elseif k == 5 then fire1(false) end
        end
        -- Gli HP dei nemici a intervalli: e' la prova che il danno arriva, e si
        -- legge dalla RAM invece che dallo schermo, cosi' un difetto di disegno
        -- non maschera un difetto di formula.
        if dt > PULSE_FROM and dt % 150 == 0 then
            dump_enemy_hp(dt)
            dump_turn_order()
        end

        -- La schermata di sconfitta va fotografata sulla CONDIZIONE, non a un
        -- istante deciso a tavolino: dura quanto ci mette la pulsazione di
        -- FIRE1 a trovarla, e a tempo fisso si finiva per riprendere
        -- l'overworld gia' tornata.
        if not defeat_shot then
            local alive = 0
            for i = 0, u8(PARTY_BASE + 2) - 1 do
                if u16(CHR0 + i * CHR_SIZE + O_CURHP) ~= 0 then alive = alive + 1 end
            end
            if alive == 0 then
                defeat_shot = true
                print(string.format("  gruppo a zero a dt=%d", dt))
                snap("ultimo caduto")
                -- La schermata di fine arriva DOPO: nell'istante in cui gli HP
                -- toccano lo zero si sta ancora leggendo "<NOME> DIES". Il
                -- secondo scatto e' quello che vale.
                defeat_at = dt
            end
        end
        if defeat_at and dt == defeat_at + 180 then snap("THE PARTY PERISHED") end

        if dt == 60 then snap("battaglia"); dump_formation()
        elseif dt == 80  then fire1(true)          -- conferma FIGHT
        elseif dt == 85  then fire1(false)
        elseif dt == 105 then snap("selezione bersaglio")
        -- Bersaglio col tastierino: e' l'uso per cui design_input.md voleva il
        -- tastierino, e qui si vede che funziona sotto overlay (la tabella di
        -- decodifica passa da src/joy.asm).
        elseif dt == 115 then pad("2 (pad 1)", true)
        elseif dt == 120 then pad("2 (pad 1)", false)
        elseif dt == 140 then snap("bersaglio 2 scelto col tastierino")
        elseif dt == 420 then snap("round in corso")
        elseif dt == VHOLD then snap("dopo i primi round")
        elseif dt == PULSE_TO + 40 then
            snap("esito")
            print(string.format("RESULT=%d  round=%d  nemici vivi=%d",
                  u8(OFF_RESULT), u16(OFF_ROUND), alive_count()))
            print(string.format("REWARD: exp/testa=%d  gp=%d  livelli=%d/%d/%d/%d",
                  u16(OFF_EXPAW), u16(OFF_GPAW), u8(OFF_NEWLV), u8(OFF_NEWLV+1),
                  u8(OFF_NEWLV+2), u8(OFF_NEWLV+3)))
            print(string.format("MAGIA: lanci=%d  ultimo=$%02X",
                  u8(OFF_CASTCNT), u8(OFF_LASTSPELL)))
            dump_party()
        elseif dt == PULSE_TO + 60 then
            -- BATTLES>1: si torna a camminare e si combatte ancora, SENZA
            -- cure in mezzo. E' l'unico modo onesto di far arrivare il gruppo
            -- a zero: gli IMP fanno 4-8 danni a colpo contro 25-35 HP, quindi
            -- una battaglia sola non basta mai, e alzare il danno per il test
            -- proverebbe una formula che il gioco non usa.
            battles_done = battles_done + 1
            if u8(OFF_RESULT) == 3 then
                print(string.format("*** GRUPPO SCONFITTO alla battaglia %d ***",
                      battles_done))
            end
            -- La sconfitta non ferma piu' la corsa: il segnaposto di slice59
            -- rimette il gruppo in piedi, quindi si puo' continuare a
            -- esplorare. Serve a raggiungere un nemico DOTATO DI IA, che
            -- intorno allo spawn di prova non e' il primo che capita.
            if battles_done >= BATTLES then
                manager.machine:exit()
            else
                print(string.format("-- battaglia %d/%d conclusa, si riparte --",
                      battles_done, BATTLES))
                phase = "walk"
            end
        end
    end
end)
