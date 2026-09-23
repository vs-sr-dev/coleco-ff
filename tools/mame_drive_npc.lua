-- mame_drive_npc.lua -- gli abitanti di Coneria: si vedono, bloccano, parlano.
--
-- PERCHE' UNO SCRIPT SUO. mame_drive_town.lua cammina, sbatte contro i muri ed
-- entra nei negozi, ma non preme MAI FIRE1: fino a slice76 quel tasto in citta'
-- non faceva niente. Qui il soggetto e' proprio quello.
--
-- ============================================================
--  LE QUATTRO COSE DA PROVARE, E PERCHE' TRE NON SI VEDONO IN RAM
-- ============================================================
--  1. **l'abitante blocca il passo.** Si vede in RAM: town_mx/town_my non
--     cambiano. Ma un passo rifiutato da un abitante e un passo rifiutato da
--     un muro si scrivono nello stesso modo, quindi la prova sta in COPPIA
--     con il punto 3: sulla stessa casella si rifiuta il passo E si apre il
--     dialogo giusto. Un muro il dialogo non ce l'ha.
--  2. **si e' parlato, e a chi.** town_talk_hits e town_talk_obj, due sonde
--     nate apposta: un dialogo non muove il gruppo, non tocca l'oro e non
--     cambia una statistica, quindi senza quei due byte "ha parlato
--     all'abitante giusto" e "non e' successo niente" sono lo stesso stato.
--  3. **il TESTO GIUSTO A SCHERMO.** Questa e' la prova vera, e si legge dalla
--     VRAM. Le sonde dicono che il gioco ha scelto l'abitante $36; solo la
--     name table dice che sullo schermo c'e' scritto "This is Coneria, the".
--     Fra i due c'e' tutta la catena -- id, routine, id di dialogo, offset nel
--     banco 26, font a base 160 -- e ognuno di quei passaggi puo' sbagliare
--     restituendo un risultato PLAUSIBILE.
--  4. **il font in citta' e' a 160, non a $20.** La citta' si porta le proprie
--     256 tile e il font sta nei buchi che il tileset lascia. Se la base fosse
--     sbagliata il testo uscirebbe come muretti, cioe' identico a un dialogo
--     che non c'e'. `vram_text` sottrae la base: se il numero non torna, il
--     confronto fallisce da solo.
--
-- LA RIGA DA 24 CARATTERI NON E' UN CASO. "I am Arylon, the Dancer!" e'
-- esattamente larga quanto la colonna di testo del riquadro, e la name table
-- e' un nastro di 768 byte: una riga larga uno di piu' non si taglia, ricompare
-- all'inizio della riga dopo (difetto #1 di slice73). E' il caso limite, ed e'
-- il motivo per cui quell'abitante e' nel piano nonostante sia il piu' lontano.

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")

local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

-- La mappa dei tile della citta' (src/world_state.h): il font comincia a 160.
local FONT_BASE  = 160
local FONT_FIRST = 0x20
local NPC_TILE_BASE = 96
-- La pianta del riquadro (src/ovl_talk.c).
local BOX_TOP, BOX_BOT, BOX_LEFT, BOX_RIGHT = 14, 23, 2, 29
local TEXT_COL, TEXT_ROW = 4, 15

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
                     "town_mx", "town_my", "town_total_shifts", "town_facing",
                     "town_talk_hits", "town_talk_obj", "town_talk_dlg" }) do has(n) end

local function u8(a) return mem:read_u8(a) end
local function u16s(a)
    local v = mem:read_u8(a) + mem:read_u8(a + 1) * 256
    if v >= 32768 then v = v - 65536 end
    return v
end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end
local function w(n) if has(n) then return u16s(probe[n]) else return -1 end end

local function pos()
    return string.format("citta'=(%d,%d) passi=%d parlate=%d/obj=%02X/dlg=%02X",
        b("town_mx"), b("town_my"), w("town_total_shifts"),
        b("town_talk_hits"), b("town_talk_obj"), b("town_talk_dlg"))
end

-- Testo dalla name table, RIPORTATO ALLA BASE DEL FONT DELLA CITTA'. Un tile
-- fuori dall'intervallo del font diventa '?': cosi' un riquadro rimasto pieno
-- di tile di citta' (cioe' un dialogo mai disegnato) si legge subito.
local function vram_text(row, col, len)
    local s = ""
    for c = col, col + len - 1 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        local ch = t - FONT_BASE + FONT_FIRST
        s = s .. ((t >= FONT_BASE and ch < 0x7F) and string.char(ch) or "?")
    end
    return s
end

local function fields_get(port_name, field_name)
    local key = port_name .. "//" .. field_name
    if fields[key] then return fields[key] end
    local port = manager.machine.ioport.ports[port_name]
    if not port then error("porta non trovata: " .. port_name) end
    local f = port.fields[field_name]
    if not f then error("campo non trovato: " .. port_name .. " " .. field_name) end
    fields[key] = f
    return f
end
-- I nomi MAME sono INVERTITI rispetto a quelli del gioco: FIRE1 del gioco e'
-- "P1 Button 2" del keypad. Verificato sul campo in slice52.
local function fire1(on) fields_get(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
local function fire2(on) fields_get(":STD_JOY1", "P1 Button 1"):set_value(on and 1 or 0) end
local function dpad(name, on) fields_get(":STD_JOY1", name):set_value(on and 1 or 0) end
local DPAD = { U = "P1 Up", D = "P1 Down", L = "P1 Left", R = "P1 Right" }
local function release_all() for _, nm in pairs(DPAD) do dpad(nm, false) end end

local ok_count, fail_count = 0, 0
local function report(good, msg)
    if good then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    print(string.format("  [%s] %s", good and " ok " or "FALLITO", msg))
end

local function shot(label)
    print(string.format("SNAP (%s) @frame %d  %s", label, frames, pos()))
    manager.machine.video:snapshot()
end

-- ============================================================
--  il piano
-- ============================================================
-- Le rotte vengono da tools/plan_town_route.ps1, non indovinate: una rotta
-- sbagliata e una collisione rotta si scrivono nello stesso modo nel log.
--
-- Gli abitanti di Coneria e dove stanno (tools/extract_dialogue.ps1 -Maps 0):
--   $31 (16, 1)  $32 ( 7,13)  $34 ( 4, 1)  $35 (15,12)
--   $36 (18,20)  $37 ( 5, 6)  $38 (27, 5)  $39 (30,11)
local PLAN = {
    -- Prima il MURO, che e' il termine di paragone: stessa forma di prova
    -- (premi, non ti muovi, parli) ma senza nessuno davanti.
    { k = "wall", dir = "L", why = "muro a ovest dell'ingresso (15,23)" },
    { k = "talk", why = "si parla al MURO", obj = 0x00,
      lines = { "Nothing here." } },
    { k = "close", why = "si chiude il riquadro", dlg = 0x00 },
    { k = "shot", why = "CONERIA -- il dialogo del muro appena chiuso" },

    -- Abitante $36 a (18,20): il piu' vicino all'ingresso.
    { k = "step", dir = "U", n = 2, why = "fino a (16,21)" },
    { k = "step", dir = "R", n = 2, why = "fino a (18,21)" },
    -- QUI STA LA COPPIA. Lo stesso passo verso nord si rifiuta (c'e' qualcuno)
    -- e lo stesso tasto FIRE1 apre il suo dialogo. Un muro fa solo la prima.
    { k = "wall", dir = "U", why = "l'abitante $36 a (18,20) blocca il passo" },
    { k = "talk", why = "si parla all'abitante $36", obj = 0x36,
      lines = { "This is Coneria, the", "dream city." } },
    { k = "shot", why = "DIALOGO -- l'abitante $36 di Coneria" },
    { k = "box", why = "la cornice del riquadro" },
    { k = "close", why = "si chiude il riquadro", dlg = 0x48 },
    { k = "npc_drawn", nx = 18, ny = 20, slot = 4,
      why = "l'abitante $36 e' ridisegnato dopo il dialogo" },

    -- Abitante $35 a (15,12): la battuta da 24 caratteri, larga esattamente
    -- quanto la colonna di testo.
    { k = "step", dir = "L", n = 2, why = "torna alla colonna 16" },
    { k = "step", dir = "U", n = 8, why = "su fino a (16,13)" },
    { k = "step", dir = "L", n = 1, why = "fino a (15,13)" },
    { k = "wall", dir = "U", why = "l'abitante $35 a (15,12) blocca il passo" },
    { k = "talk", why = "si parla all'abitante $35", obj = 0x35,
      lines = { "I am Arylon, the Dancer!" } },
    -- La riga SOTTO quella da 24 caratteri deve essere VUOTA. Se la stringa
    -- avesse sforato la colonna, il carattere di troppo si troverebbe qui --
    -- ed e' l'unico posto in cui quel difetto si vede.
    { k = "empty_line", row = TEXT_ROW + 1, why = "niente sborda sotto la riga da 24" },
    { k = "shot", why = "DIALOGO -- la riga da 24 caratteri, al limite del riquadro" },
    { k = "close", why = "si chiude il riquadro", dlg = 0x47 },
    { k = "done" },
}

local pi, reps, phase, timer = 1, 0, "idle", 0
local start_mx, start_my, start_hits

local WALL_PRESS = 40
local STEP_LIMIT = 240
local SETTLE     = 20
local TALK_PRESS = 20    -- FIRE1 tenuto, poi rilasciato: l'overlay vuole un fronte
local TALK_DRAW  = 40    -- quadri per il disegno del riquadro

local function check_lines(a)
    local good = true
    for i, want in ipairs(a.lines) do
        local got = vram_text(TEXT_ROW + i - 1, TEXT_COL, #want)
        if got ~= want then good = false end
        report(got == want, string.format("riga %d: <%s> atteso <%s>", i, got, want))
    end
    return good
end

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); pi = pi + 1; return end
    if a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    end
    if a.k == "box" then
        -- La cornice si AFFERMA, non si fotografa: e' la regola di slice66 e
        -- del riquadro dei comandi di slice69. Angoli, lati e barre verticali.
        local tl = vram:read_u8(0x1800 + BOX_TOP * 32 + BOX_LEFT)
        local tr = vram:read_u8(0x1800 + BOX_TOP * 32 + BOX_RIGHT)
        local bl = vram:read_u8(0x1800 + BOX_BOT * 32 + BOX_LEFT)
        local plus = FONT_BASE + string.byte("+") - FONT_FIRST
        report(tl == plus and tr == plus and bl == plus,
               string.format("%s: angoli %d/%d/%d (atteso %d)", a.why, tl, tr, bl, plus))
        local top = vram_text(BOX_TOP, BOX_LEFT, BOX_RIGHT - BOX_LEFT + 1)
        report(top == "+" .. string.rep("-", BOX_RIGHT - BOX_LEFT - 1) .. "+",
               string.format("%s: bordo alto <%s>", a.why, top))
        pi = pi + 1; return
    end
    if a.k == "empty_line" then
        -- 24 colonne, non 26: la 25a e' il margine e la 26a e' gia' la BARRA
        -- VERTICALE del riquadro, che sta sotto la base del font e uscirebbe
        -- come '?'. La prima stesura leggeva 26 e falliva sul proprio bordo.
        local got = vram_text(a.row, TEXT_COL, 24)
        report(got == string.rep(" ", 24),
               string.format("%s: <%s>", a.why, got))
        pi = pi + 1; return
    end
    if a.k == "npc_drawn" then
        -- Le quattro tile dell'abitante devono essere tornate al loro posto
        -- dopo il ridisegno. Sono NPC_TILE_BASE + slot*4 + (riga*2 + colonna);
        -- lo slot e' la posizione nella tabella degli oggetti della mappa, che
        -- e' anche quella con cui la grafica e' stata cotta.
        -- La colonna di schermo: il giocatore sta fisso alla cella (15,11),
        -- cioe' al macrotile (town_mx, town_my). Da li' si ricava dove cade
        -- l'abitante senza dover leggere la camera.
        local mx, my = b("town_mx"), b("town_my")
        local sc = 15 + (a.nx - mx) * 2
        local sr = 11 + (a.ny - my) * 2
        local base = NPC_TILE_BASE + a.slot * 4
        local got = {}
        local good = true
        for k = 0, 3 do
            local t = vram:read_u8(0x1800 + (sr + math.floor(k / 2)) * 32 + sc + (k % 2))
            got[#got + 1] = t
            if t ~= base + k then good = false end
        end
        report(good, string.format("%s: tile %d,%d,%d,%d a schermo (%d,%d), attese %d..%d",
               a.why, got[1], got[2], got[3], got[4], sc, sr, base, base + 3))
        pi = pi + 1; return
    end

    start_mx, start_my = b("town_mx"), b("town_my")
    start_hits = b("town_talk_hits")
    if a.k == "talk" or a.k == "close" then
        print(string.format("f=%d  %s", frames, a.why))
        phase = "press"; timer = 0; return
    end
    if reps == 0 then
        print(string.format("f=%d  %s (%s)  da %s", frames, a.why, a.dir, pos()))
    end
    dpad(DPAD[a.dir], true)
    phase = "press"; timer = 0
end

local function next_action() reps = 0; pi = pi + 1; phase = "settle"; timer = 0 end

local function frame_action()
    local a = PLAN[pi]
    if not a then return end
    if phase == "idle" then begin_action(); return end
    timer = timer + 1
    if phase == "settle" then
        if timer >= SETTLE then phase = "idle" end
        return
    end

    local mx, my = b("town_mx"), b("town_my")

    if a.k == "talk" then
        if timer < TALK_PRESS then fire1(true); return end
        fire1(false)
        if timer < TALK_PRESS + TALK_DRAW then return end
        local hits = b("town_talk_hits")
        report(hits == start_hits + 1,
               string.format("%s: parlate %d -> %d", a.why, start_hits, hits))
        report(b("town_talk_obj") == a.obj,
               string.format("%s: obj %02X, atteso %02X", a.why, b("town_talk_obj"), a.obj))
        check_lines(a)
        next_action(); return
    end

    if a.k == "close" then
        -- Fronte di salita: si arriva qui con il FIRE1 gia' rilasciato, quindi
        -- una pressione nuova chiude. Poi si aspetta il ridisegno della citta'.
        if timer < TALK_PRESS then fire1(true); return end
        fire1(false)
        if timer < TALK_PRESS + TALK_DRAW then return end
        -- La riga di testo non deve piu' esserci: al suo posto ci sono le tile
        -- della citta', che stanno tutte sotto la base del font.
        local t = vram:read_u8(0x1800 + TEXT_ROW * 32 + TEXT_COL)
        report(t < FONT_BASE,
               string.format("%s: la riga di testo e' tornata citta' (tile %d)", a.why, t))
        -- L'ID DEL DIALOGO SI LEGGE QUI, NON APPENA IL RIQUADRO COMPARE, ed e'
        -- costato una corsa: `town_talk_dlg` lo assegna il VALORE DI RITORNO
        -- dell'overlay, che torna solo quando il riquadro si chiude. Chiedendolo
        -- a riquadro aperto si legge quello della parlata PRECEDENTE -- cioe' un
        -- valore plausibile, e alla seconda prova perfino uno "quasi giusto".
        report(b("town_talk_dlg") == a.dlg,
               string.format("%s: dlg %02X, atteso %02X", a.why, b("town_talk_dlg"), a.dlg))
        next_action(); return
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

    -- a.k == "step"
    if mx ~= start_mx or my ~= start_my then
        release_all()
        reps = reps + 1
        if reps >= a.n then
            report(true, string.format("%s: arrivato a (%d,%d)", a.why, mx, my))
            next_action()
        else
            phase = "settle"; timer = 0
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

-- ============================================================
--  arrivo in citta': stessa apertura di mame_drive_town.lua
-- ============================================================
local SEQ = {}
local function at(f, fn) SEQ[f] = fn end

at(2300, function() shot("overworld allo spawn") end)
local t = 2350
for i = 1, 3 do
    at(t,     function() dpad("P1 Up", true) end)
    at(t + 8, function() dpad("P1 Up", false) end)
    t = t + 60
end
at(t + 40, function() dpad("P1 Right", true) end)
at(t + 48, function() dpad("P1 Right", false) end)

-- expand_town espande 4096 macrotile in 16384 celle: ~140 quadri. Uno scatto
-- prima cadrebbe in mezzo all'espansione e mostrerebbe ancora l'overworld.
local TOWN_READY = t + 300
at(TOWN_READY, function()
    shot("CONERIA -- ingresso, con gli abitanti")
    print("== inizio prova abitanti, " .. pos())
end)

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    -- SOLO FIRE1 per superare l'intro, e SOLO fino al 2200: da slice73 FIRE2
    -- apre il menu e da slice76 FIRE1 apre un dialogo. Pulsantate cieche
    -- lasciate cadere nel ciclo della citta' aprirebbero riquadri a caso.
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
    elseif frames == 2200 then
        fire1(false)
    end
    local fn = SEQ[frames]
    if fn then fn() end
    if frames > TOWN_READY then frame_action() end
end)
