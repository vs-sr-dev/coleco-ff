-- mame_drive_town.lua -- Coneria: ci si entra, ci si sbatte contro i muri,
-- si calpesta un negozio, si esce.
--
-- PERCHE' UNO SCRIPT SUO. mame_drive.lua si ferma in overworld e
-- mame_drive_battle.lua cerca gli scontri: nessuno dei due entra mai in
-- citta'.
--
-- COME CI SI ENTRA (e come si e' trovata la strada)
-- L'ingresso di Coneria e' il macrotile **0x49**: unico in tutta la tabella
-- con il bit 7 di attr1 acceso e id di teletrasporto 1. Nel mondo ne esistono
-- 6 esemplari; il piu' vicino allo spawn (153,165) e' a **(154,162)**, cioe'
-- tre passi in su e uno a destra. Il cammino e' stato verificato sui dati
-- prima di scriverlo qui: tutte e quattro le caselle hanno il bit NOWALK
-- spento.
--
-- TRAPPOLA IN CUI SONO CADUTO CERCANDOLA: in attr1 il **bit 7 e' il
-- teletrasporto e il bit 6 la battaglia** (NES: `BIT tileprop+1` / `BMI
-- @Teleport` / `BVS @Battle`, bank_0F.asm:321). Leggendo il bit 6 come
-- teletrasporto vengono fuori 892 caselle "d'ingresso" tutte con NOWALK
-- acceso, e sembra che una slice precedente abbia rotto l'ingresso in citta'.
-- Non era rotto niente: era sbagliata la sonda.
--
-- ============================================================
-- DA slice64: SI GUIDA A CICLO CHIUSO, NON A TEMPO
-- ============================================================
-- Ogni passo tiene premuta la direzione FINCHE' town_mx/town_my non cambia,
-- poi rilascia. Non e' un vezzo: STEP_COOLDOWN_FRAMES vale 1, quindi una
-- pressione tenuta per 8 frame fa da 1 a 4 passi a seconda di quanti vblank
-- il redraw della citta' si mangia (768 celle, ~6.5ms contro 4.4ms di
-- vblank). A tempo fisso il cammino esce diverso a ogni corsa, e con le
-- collisioni di mezzo un passo in piu' finisce dentro un muro -- dove poi non
-- si distingue "muro giusto" da "script che ha contato male".
--
-- Il muro invece si prova A TEMPO, e deve essere cosi': un passo rifiutato
-- non cambia mai la posizione, quindi aspettarne il cambiamento non finirebbe
-- mai. Si preme per N frame e si verifica che la posizione sia RIMASTA.
--
-- LE TRE COSE CHE NON SI VEDONO A SCHERMO
--  1. il muro. Un passo rifiutato e un comando ignorato danno la stessa
--     schermata ferma. Si legge town_mx/town_my.
--  2. il negozio. Non ha ancora un'interfaccia: l'unica traccia e'
--     town_shop_id, che deve valere 51 sulla porta a (11,18).
--  3. l'uscita. Tornare in overworld si VEDE, ma non si vede se ci si e'
--     tornati alle coordinate giuste: si legge world_player_mx/my, che deve
--     essere ancora (154,162), la casella della citta'.

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")

local mem = manager.machine.devices[":maincpu"].spaces["program"]

-- Una sonda mancante deve FARSI SENTIRE, non falsare. `probe.x` assente vale
-- nil, MAME lo converte in indirizzo 0 e restituisce un byte del BIOS: la
-- sonda riporta sempre lo stesso valore e sembra un gioco fermo. E' successo
-- qui la prima volta: world_player_mx era locale a main() e non compariva
-- nella .map.
-- Manca -> si DICE, ad alta voce, e quel campo diventa "n/d". Non si alza un
-- errore: cosi' lo stesso script gira anche su una slice piu' VECCHIA, dove
-- alcune variabili erano ancora locali -- ed e' proprio il confronto fra due
-- versioni che serve quando si sospetta una regressione.
local missing = {}
local function has(name)
    if probe[name] then return true end
    if not missing[name] then
        missing[name] = true
        print("!! SONDA MANCANTE: " .. name .. " -- il campo sara' n/d")
    end
    return false
end
for _, n in ipairs({ "world_player_mx", "world_player_my", "main_bank",
                     "town_cam_x", "town_cam_y", "town_total_shifts",
                     "town_mx", "town_my", "town_shop_id", "town_shop_hits",
                     "town_warp_out" }) do has(n) end

local function u8(a) return mem:read_u8(a) end

local function find_port_field(port_name, field_name)
    local key = port_name .. "//" .. field_name
    if fields[key] then return fields[key] end
    -- Per PORTA e nome, mai per solo nome: "P1 Button 1" esiste in piu' porte.
    local port = manager.machine.ioport.ports[port_name]
    if not port then error("porta non trovata: " .. port_name) end
    local f = port.fields[field_name]
    if not f then error("campo non trovato: " .. port_name .. " " .. field_name) end
    fields[key] = f
    return f
end

local function fire1(on) find_port_field(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
-- FIRE2 del gioco = "P1 Button 1" di :STD_JOY1. I nomi MAME sono INVERTITI
-- rispetto a quelli del gioco, verificato sul campo in slice52 -- e' scritto
-- anche in mame_drive_intro.lua, e vale la pena ripeterlo qui perche' un
-- pulsante premuto sulla porta sbagliata non da' errore, da' un gioco fermo.
local function fire2(on) find_port_field(":STD_JOY1", "P1 Button 1"):set_value(on and 1 or 0) end
local function dpad(name, on) find_port_field(":STD_JOY1", name):set_value(on and 1 or 0) end
local DPAD = { U = "P1 Up", D = "P1 Down", L = "P1 Left", R = "P1 Right" }
local function release_all() for _, nm in pairs(DPAD) do dpad(nm, false) end end

local function u16s(a)  -- int a 16 bit con segno, little endian
    local v = mem:read_u8(a) + mem:read_u8(a + 1) * 256
    if v >= 32768 then v = v - 65536 end
    return v
end

local function b(n) if has(n) then return u8(probe[n]) else return -1 end end
local function w(n) if has(n) then return u16s(probe[n]) else return -1 end end

local function pos()
    return string.format("citta'=(%d,%d) mondo=(%d,%d) passi=%d shop=%d/%d",
        b("town_mx"), b("town_my"), b("world_player_mx"), b("world_player_my"),
        w("town_total_shifts"), b("town_shop_id"), b("town_shop_hits"))
end

-- NON leggere world_cells ($2000) da qui. Ci ho provato e ha dato un FALSO
-- INDIZIO: usciva tutto zero mentre la citta' si disegnava. La RAM SGM a
-- $2000-$5FFF non si legge in modo affidabile dallo spazio ":maincpu" di
-- MAME. Cio' che il gioco SCRIVE va fatto raccontare al gioco, copiandolo in
-- una variabile del BSS e leggendo quella -- come si e' fatto per trovare il
-- difetto di slice63.

local function shot(label)
    print(string.format("SNAP (%s) @frame %d  %s", label, frames, pos()))
    manager.machine.video:snapshot()
end

-- ============================================================
--  il piano: una lista di azioni, eseguita una alla volta
-- ============================================================
-- Il cammino dentro Coneria e' stato verificato sui dati con
-- tools/analyze_town_props.ps1 PRIMA di scriverlo qui, casella per casella.
-- Ingresso a (16,23). Il corridoio sud e' l'unico buco nelle mura.
--
--        11 12 13 14 15 16
--   18    S  #  #  .  .  .        S = porta del negozio, shop_id 51
--   19    r  .  .  .  #  .        r = TP_SPEC_CLOSEROOM, si passa
--   20    .  #  .  .  .  .
--   21    .  .  .  .  .  .        <- la fila larga
--   22    .  .  .  .  .  .
--   23    #  #  #  #  #  @        <- ingresso, mura tutt'intorno
--   24    W  W  W  W  W  W        <- prato: TP_TELE_WARP, l'uscita
local PLAN = {
    { k = "wall", dir = "L", why = "muro a ovest dell'ingresso (15,23)" },
    { k = "wall", dir = "R", why = "muro a est dell'ingresso (17,23)" },
    { k = "step", dir = "U", n = 2, why = "su, nella fila larga" },
    { k = "step", dir = "L", n = 5, why = "ovest fino alla colonna 11" },
    { k = "shot", why = "CONERIA -- meta' strada" },
    { k = "step", dir = "U", n = 3, why = "su fino alla porta del negozio (11,18)" },
    { k = "check_shop", want = 51, why = "shop_id della porta a (11,18)" },
    -- Calpestare la porta APRE il negozio (slice65): da qui in poi non gira
    -- piu' il ciclo della citta' ma l'overlay del banco 22, e nessun passo
    -- funziona finche' non si esce. L'attesa serve al disegno della
    -- schermata; lo scatto e' l'unica prova che il listino esce giusto,
    -- perche' i nomi e i prezzi non finiscono in nessuna variabile.
    { k = "wait", n = 150, why = "il negozio si disegna" },
    { k = "shot", why = "NEGOZIO -- la locanda di Coneria (shop_id 51)" },
    { k = "fire2", why = "FIRE2: si esce dal negozio" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "shot", why = "CONERIA -- tornati dal negozio, sulla soglia" },
    { k = "step", dir = "D", n = 3, why = "giu', via dalla porta" },
    { k = "step", dir = "R", n = 5, why = "est, di nuovo sopra l'ingresso" },
    -- SECONDA VISITA, e non e' ridondanza: la locanda e' un negozio di
    -- SERVIZIO e non ha listino, quindi non mostra ne' nomi ne' prezzi ne'
    -- icone. L'armeria (shop_id 1, porta a (11,10)) e' l'unica prova che la
    -- catena id -> nome -> icona -> prezzo arriva davvero a schermo -- ed e'
    -- anche il caso in cui, senza icone, si leggerebbe "Wooden" due volte.
    -- Il giro lungo e' obbligato: da (11,18) la colonna 11 e' murata a nord,
    -- e l'unico passaggio verso la meta' alta e' la fila 14.
    { k = "step", dir = "U", n = 7, why = "su per la colonna 16 fino alla fila 14" },
    { k = "step", dir = "L", n = 5, why = "ovest lungo la fila 14 fino alla colonna 11" },
    { k = "step", dir = "U", n = 4, why = "su fino alla porta dell'armeria (11,10)" },
    { k = "check_shop", want = 1, why = "shop_id della porta a (11,10)" },
    { k = "wait", n = 150, why = "l'armeria si disegna" },
    { k = "shot", why = "NEGOZIO -- l'armeria di Coneria (nomi, icone, prezzi)" },
    { k = "fire2", why = "FIRE2: si esce dall'armeria" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "step", dir = "D", n = 4, why = "giu', di nuovo sulla fila 14" },
    { k = "step", dir = "R", n = 5, why = "est fino alla colonna 16" },
    { k = "step", dir = "D", n = 9, why = "giu' per la colonna 16 fino all'ingresso" },
    { k = "shot", why = "CONERIA -- di nuovo sull'ingresso" },
    { k = "exit", dir = "D", why = "un passo a sud: prato = TP_TELE_WARP" },
    -- QUESTO SCATTO ESCE VERDE PIATTO, ED E' GIUSTO COSI'. enter_ow azzera la
    -- name table (`vdp_vfill(0x1800, 0x00, 768)`) prima di scambiare la
    -- tabella dei pattern, e in overworld il tile 0 e' erba piena: finche' il
    -- ridisegno non arriva, lo schermo e' un prato. E' la stessa trappola gia'
    -- catalogata per l'ingresso in citta' (~140 frame di expand_town), presa
    -- una seconda volta dall'altro lato -- e la prima lettura era stata "la
    -- overworld si ridisegna male al rientro". Resta perche' e' il modo piu'
    -- diretto di far vedere quanto dura il buco.
    { k = "shot", why = "OVERWORLD -- subito dopo l'uscita (prato = ridisegno in corso)" },
    -- LA DOMANDA DECISIVA, e non si risponde guardando lo schermo. Dopo
    -- l'uscita lo schermo e' un prato verde, e ci sono DUE spiegazioni che a
    -- occhio sono la stessa immagine:
    --   a) siamo in overworld, ma ridisegnata male;
    --   b) non siamo mai usciti, e stiamo camminando nel prato ESTERNO di
    --      Coneria -- che nella mappa della citta' e' $47 ovunque, 3447
    --      macrotile di erba identica.
    -- Si distinguono da QUALE contatore si muove: in overworld cambia
    -- world_player_mx/my, in citta' cambia town_mx/my. Un passo, e si sa.
    { k = "who_moves", dir = "L", why = "chi si muove: la overworld o la citta'?" },
    -- Il primo passo qui sopra e' partito mentre enter_ow stava ancora
    -- lavorando, quindi il suo tempo e' "enter_ow + un passo". Questi tre
    -- misurano il passo DA SOLO: la differenza e' il costo del rientro.
    { k = "ow_step", dir = "L", n = 2, why = "due passi in overworld, per il costo del passo da solo" },
    { k = "shot", why = "OVERWORLD -- ridisegno finito" },
    -- IL TERZO PASSO A OVEST RIENTRA IN CITTA', e non e' un incidente del
    -- percorso: sulla overworld Coneria e' un gruppo di macrotile
    -- x=151..154, y=160..162, e le colonne 151 e 154 sono ENTRAMBE fatte del
    -- macrotile $49, teleport id 1. Sono sei caselle d'ingresso, le uniche
    -- del mondo con quell'id. Da (154,162) si va a 153 e 152 (macro $3D,
    -- niente teleport) e al terzo passo si e' sulla colonna ovest.
    -- La prima corsa lo aveva letto come "passo bloccato": la sonda guardava
    -- solo le coordinate del mondo, che in citta' smettono di muoversi.
    -- Questa azione NON provoca il rientro: lo ASPETTA. Il terzo passo l'ha
    -- gia' fatto scattare, ma enter_town impiega ~140 frame a espandere la
    -- mappa, quindi al momento dello scatto qui sopra i contatori dicono
    -- ancora "citta' di prima". Preme e attende che lo stato si azzeri.
    { k = "reenter", dir = "L", why = "il terzo passo a ovest e' rientrato a Coneria dalla colonna 151" },
    { k = "shot", why = "CONERIA -- rientrati dalla colonna ovest" },
    { k = "done" },
}

local pi = 1          -- indice nel piano
local reps = 0        -- ripetizioni gia' fatte dell'azione corrente
local phase = "idle"  -- idle | press | settle
local timer = 0
local start_mx, start_my, start_wx, start_wy
local ok_count, fail_count = 0, 0

local function report(good, msg)
    if good then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    print(string.format("  [%s] %s", good and " ok " or "FALLITO", msg))
end

local WALL_PRESS = 40   -- frame di pressione contro un muro: abbondanti
local STEP_LIMIT = 240  -- se un passo non arriva entro questi frame, e' un difetto
local SETTLE     = 20   -- respiro fra un'azione e l'altra

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then
        shot(a.why); pi = pi + 1; return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "check_shop" then
        -- SI ASPETTA, non si campiona. E' la regola del ciclo chiuso
        -- ([[mame-drive-closed-loop]]), e questo controllo la violava di
        -- nascosto: leggeva town_shop_id UNA volta, poco dopo che la posizione
        -- era cambiata. Ma la posizione la scrive `town_tick` PRIMA di
        -- ridisegnare la citta', e la porta la apre DOPO -- fra le due passa
        -- un ridisegno intero, che da slice76 e' cresciuto (gli abitanti e i
        -- loro contorni). Il campionamento cadeva nel mezzo e leggeva ancora
        -- lo shop_id PRECEDENTE: alla prima porta 0, alla seconda quello della
        -- prima. Un difetto della prova che si legge come un difetto del
        -- gioco, e per giunta "quasi giusto".
        local got = b("town_shop_id")
        if got == a.want then
            report(true, string.format("%s: %d dopo %d quadri", a.why, got, reps))
            reps = 0; pi = pi + 1; return
        end
        reps = reps + 1
        if reps >= 240 then
            report(false, string.format("%s: dopo %d quadri vale ancora %d, atteso %d",
                a.why, reps, got, a.want))
            reps = 0; pi = pi + 1
        end
        return
    end
    start_mx, start_my = b("town_mx"), b("town_my")
    start_wx, start_wy = b("world_player_mx"), b("world_player_my")
    if a.k == "wait" or a.k == "fire2" then
        if a.k == "fire2" then print(string.format("f=%d  %s", frames, a.why)) end
        phase = "press"; timer = 0; return
    end
    if reps == 0 then
        print(string.format("f=%d  %s (%s)  da %s", frames, a.why, a.dir, pos()))
    end
    dpad(DPAD[a.dir], true)
    phase = "press"; timer = 0
end

local function next_action()
    reps = 0; pi = pi + 1; phase = "settle"; timer = 0
end

local function frame_action()
    local a = PLAN[pi]
    if not a then return end

    if phase == "idle" then begin_action(); return end

    timer = timer + 1

    if phase == "settle" then
        if timer >= SETTLE then phase = "idle" end
        return
    end

    -- phase == "press"
    local mx, my = b("town_mx"), b("town_my")

    if a.k == "fire2" then
        -- Tenuto premuto per un po', poi rilasciato: l'overlay aspetta un
        -- FRONTE (rilascio + pressione), non un livello, o si chiuderebbe da
        -- solo con la direzione ancora premuta che lo ha aperto.
        if timer < 30 then
            fire2(true)
        else
            fire2(false)
            report(true, a.why)
            next_action()
        end
        return
    end

    if a.k == "wait" then
        if timer >= a.n then
            print(string.format("  dopo %d frame: %s  main_bank=%d", a.n, pos(), b("main_bank")))
            next_action()
        end
        return
    end

    if a.k == "reenter" then
        -- Si riconosce dallo stato che enter_town azzera: i passi tornano a
        -- zero e la posizione torna sull'ingresso. Guardare le coordinate del
        -- mondo qui non servirebbe -- restano ferme sulla casella della
        -- citta', esattamente come se il passo fosse stato rifiutato.
        if w("town_total_shifts") == 0 and mx == 16 and my == 23 then
            release_all()
            report(true, string.format("%s: dentro, citta'=(%d,%d) mondo=(%d,%d)",
                a.why, mx, my, b("world_player_mx"), b("world_player_my")))
            next_action()
        elseif timer >= STEP_LIMIT then
            release_all()
            report(false, string.format("%s: NON e' rientrato dopo %d frame (%s)", a.why, timer, pos()))
            next_action()
        end
        return
    end

    if a.k == "ow_step" then
        local wx, wy = b("world_player_mx"), b("world_player_my")
        if wx ~= start_wx or wy ~= start_wy then
            release_all()
            reps = reps + 1
            print(string.format("    passo %d/%d -> mondo=(%d,%d)  %d frame", reps, a.n, wx, wy, timer))
            if reps >= a.n then
                report(true, string.format("%s: arrivato a (%d,%d)", a.why, wx, wy))
                next_action()
            else
                phase = "settle"; timer = 0
            end
        elseif timer >= STEP_LIMIT then
            release_all()
            report(false, string.format("%s: passo %d bloccato a (%d,%d)", a.why, reps + 1, wx, wy))
            next_action()
        end
        return
    end

    if a.k == "who_moves" then
        local wx, wy = b("world_player_mx"), b("world_player_my")
        local town_moved  = (mx ~= start_mx or my ~= start_my)
        local world_moved = (wx ~= start_wx or wy ~= start_wy)
        if town_moved or world_moved or timer >= STEP_LIMIT then
            release_all()
            if world_moved and not town_moved then
                report(true, string.format("%s: si muove la OVERWORLD -> (%d,%d). Siamo fuori. (%d frame dall'uscita, cioe' enter_ow + un passo)",
                    a.why, wx, wy, timer))
            elseif town_moved and not world_moved then
                report(false, string.format("%s: si muove la CITTA' -> (%d,%d). NON siamo usciti.",
                    a.why, mx, my))
            elseif town_moved and world_moved then
                report(false, string.format("%s: si muovono TUTTE E DUE: citta'=(%d,%d) mondo=(%d,%d)",
                    a.why, mx, my, wx, wy))
            else
                report(false, string.format("%s: non si muove NIENTE dopo %d frame (%s)",
                    a.why, timer, pos()))
            end
            next_action()
        end
        return
    end

    if a.k == "wall" then
        if timer >= WALL_PRESS then
            release_all()
            local moved = (mx ~= start_mx or my ~= start_my)
            report(not moved, string.format("%s: %s -> (%d,%d)", a.why,
                moved and "SI E' MOSSO" or "fermo", mx, my))
            next_action()
        end
        return
    end

    if a.k == "exit" then
        -- L'uscita si riconosce da town_warp_out, non dalla posizione: appena
        -- si esce si e' di nuovo in overworld e town_mx non conta piu'.
        if b("town_warp_out") == 1 then
            release_all()
            report(true, string.format("%s: uscito, mondo=(%d,%d)", a.why,
                b("world_player_mx"), b("world_player_my")))
            next_action()
        elseif timer >= STEP_LIMIT then
            release_all()
            report(false, string.format("%s: NON e' uscito dopo %d frame (%s)",
                a.why, timer, pos()))
            next_action()
        end
        return
    end

    -- a.k == "step": si tiene premuto finche' la posizione non cambia
    if mx ~= start_mx or my ~= start_my then
        release_all()
        reps = reps + 1
        print(string.format("    passo %d/%d -> (%d,%d)", reps, a.n, mx, my))
        if reps >= a.n then
            report(true, string.format("%s: arrivato a (%d,%d)", a.why, mx, my))
            next_action()
        else
            phase = "settle"; timer = 0   -- begin_action ripremera' la stessa direzione
        end
        return
    end
    if timer >= STEP_LIMIT then
        release_all()
        report(false, string.format("%s: passo %d bloccato, fermo a (%d,%d)",
            a.why, reps + 1, mx, my))
        next_action()
    end
end

-- ATTESA LUNGA PRIMA DI COMINCIARE, e non e' prudenza: expand_town espande
-- 4096 macrotile in 16384 celle, e sul Z80 ci mette ~140 frame (oltre due
-- secondi). Uno scatto a t+150 cadeva IN MEZZO all'espansione e mostrava la
-- overworld ancora sullo schermo -- che, letta come "citta' disegnata male",
-- mandava fuori strada.
local SEQ = {}
local function at(f, fn) SEQ[f] = fn end

at(2300, function() shot("overworld allo spawn") end)

-- Tre passi in su e uno a destra: si entra in citta'. Questo pezzo resta a
-- tempo perche' fuori citta' non c'e' town_mx da guardare, e il cammino e'
-- gia' verificato dalle corse precedenti.
local t = 2350
for i = 1, 3 do
    at(t,      function() dpad("P1 Up", true) end)
    at(t + 8,  function() dpad("P1 Up", false) end)
    t = t + 60
end
at(t, function() shot("davanti alla porta") end)
at(t + 40, function() dpad("P1 Right", true) end)
at(t + 48, function() dpad("P1 Right", false) end)

local TOWN_READY = t + 300
at(TOWN_READY, function()
    shot("CONERIA -- ingresso")
    print("== inizio prova collisioni/negozio/uscita, " .. pos())
end)

local last = ""
sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1

    -- attraversamento dell'intro, a pulsantate cieche: qui non e' il soggetto
    if frames >= 700 and frames < 2200 then
        -- SOLO FIRE1, da slice73. Le pressioni cieche servono a superare
        -- legenda, menu di boot e selezione dei personaggi, e a tutti e tre
        -- basta FIRE1: FIRE2 li' fa solo "classe precedente", cioe' niente
        -- che questa corsa debba scegliere. Ma da slice73 FIRE2 APRE IL MENU,
        -- e se l'intro finisce prima del frame 2200 le pulsazioni rimaste
        -- cadono nel ciclo dell'overworld: il menu si apre e si chiude decine
        -- di volte, i passi verso Coneria finiscono dentro una schermata che
        -- non li usa, e la corsa comincia FUORI dalla citta' -- con ogni
        -- controllo che fallisce per il motivo sbagliato. Costato una corsa.
        local on = (frames % 16) < 5
        fire1(on)
    elseif frames == 2200 then
        fire1(false)
    end

    local fn = SEQ[frames]
    if fn then fn() end

    if frames > TOWN_READY then frame_action() end

    if frames > 2300 and frames <= TOWN_READY then
        local now = pos()
        if now ~= last then print(string.format("  f=%d  %s", frames, now)); last = now end
    end
end)
