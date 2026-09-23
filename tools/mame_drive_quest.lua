-- mame_drive_quest.lua -- LA PRIMA QUEST INTERA (slice77).
--
-- Re -> Garland -> principessa -> LUTE -> ponte: la corsa attraversa tutte e
-- quattro le mappe, i tre tipi di teletrasporto e le quattro routine di
-- dialogo che cambiano qualcosa. Gira sulla build _t con FORCE_QUEST:
-- incontri casuali spenti (la rotta per il tempio ha 32 caselle FIGHT) e
-- gruppo potenziato (la battaglia di Garland qui e' un passaggio della
-- storia, non il soggetto -- il soggetto suo e' mame_drive_battle.lua).
--
-- LE COSE CHE SOLO QUESTA CORSA PUO' PROVARE:
--   1. ENTR: overworld -> castello (tele 9) e -> tempio (tele 13);
--   2. NORM: le scale del castello nei DUE versi, e il teletrasporto della
--      principessa (routine 9), che e' un NORM lanciato da un dialogo;
--   3. EXIT: il portone del castello, l'unico teletrasporto che scrive
--      world_player_mx/my con coordinate proprie;
--   4. le routine 8/9/10/11 nel loro ordine di storia, coi flag TALK_FX nel
--      byte alto del ritorno (sonda town_talk_fx) e gli effetti veri: il
--      ponte in WORLD.progress, il LUTE in PARTY.item, Garland che sparisce.
--
-- Le rotte interne vengono da plan_town_route.ps1 (-MapId 8/24/12); quella
-- di overworld da una BFS sugli stessi byte del gioco (costo 100 alle caselle
-- FIGHT: 32 sono inevitabili, ed e' il motivo del FORCE_QUEST).

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")

local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

local FONT_BASE  = 160
local FONT_FIRST = 0x20
local TEXT_COL, TEXT_ROW = 4, 15

-- RAM condivisa (indirizzi FISSI, non di .map): world_state.h e party_state.h.
local WORLD_PROGRESS = 0x6502     -- bit 0 = WPROG_BRIDGE
local BATTLE_MAGIC_A = 0x6000     -- u16: BATTLE_STATE_MAGIC finche' si combatte
local BATTLE_MAGIC   = 0xB47E
local PARTY_BASE     = 0x6100     -- magic(2) n(1) gp(3) chr[4] item[]
local ITEM_LUTE      = 0x01

local missing = {}
local function has(name)
    if probe[name] then return true end
    if not missing[name] then
        missing[name] = true
        print("!! SONDA MANCANTE: " .. name .. " -- il campo sara' n/d")
    end
    return false
end
for _, n in ipairs({ "world_player_mx", "world_player_my", "cur_map_slot",
                     "town_mx", "town_my", "town_warp_out", "party_chr_size",
                     "town_talk_hits", "town_talk_obj", "town_talk_dlg",
                     "town_talk_fx" }) do has(n) end

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

local function lute_addr()
    -- item[] sta in coda a chr[4]; il passo lo pubblica il gioco
    -- (party_chr_size), come per tutte le sonde del gruppo.
    return PARTY_BASE + 6 + 4 * b("party_chr_size") + ITEM_LUTE
end

local function pos()
    return string.format("mappa=%d citta'=(%d,%d) ow=(%d,%d) dlg=%02X fx=%02X",
        b("cur_map_slot"), b("town_mx"), b("town_my"),
        b("world_player_mx"), b("world_player_my"),
        b("town_talk_dlg"), b("town_talk_fx"))
end

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
local function fire1(on) fields_get(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
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
-- slot: 0=Coneria 1=castello1F 2=castello2F 3=tempio (map_desc in slice77).
local PLAN = {
    -- ---- overworld -> castello (ENTR 9) --------------------------------
    -- Da (153,165) sei passi a nord; il sesto calpesta (153,159) ed entra.
    { k = "owstep", dir = "U", n = 5, why = "spawn -> sotto il castello" },
    { k = "enter", dir = "U", slot = 1, tx = 12, ty = 35,
      why = "ENTR 9: si entra nel castello 1F a (12,35)" },
    { k = "shot", why = "CASTELLO 1F -- l'ingresso" },

    -- ---- 1F -> scale -> 2F (NORM 0) ------------------------------------
    -- Rotta di plan_town_route.ps1 -MapId 8: 17 passi a nord, dritti.
    { k = "step", dir = "U", n = 16, why = "1F: fino a (12,19), sotto le scale" },
    { k = "enter", dir = "U", slot = 2, tx = 12, ty = 18,
      why = "NORM 0: le scale portano al 2F, stesse coordinate" },
    { k = "shot", why = "CASTELLO 2F -- dalle scale" },

    -- ---- il Re, prima della principessa: routine 8, ramo [1] ------------
    { k = "step", dir = "U", n = 13, why = "2F: fino a (12,5), sotto il trono" },
    { k = "wall", dir = "U", why = "il Re a (12,4) blocca il passo" },
    { k = "talk", why = "si parla al Re (principessa rapita)", obj = 0x01,
      lines = { "LIGHT WARRIORS.. Just as", "in Lukahn's prophecy." } },
    { k = "shot", why = "IL RE -- la profezia" },
    { k = "close", why = "il Re: dlg [1], nessun effetto", dlg = 0x01, fx = 0x00 },

    -- ---- si torna giu' e fuori (NORM 62, poi EXIT 4) --------------------
    { k = "step", dir = "D", n = 12, why = "2F: fino a (12,17)" },
    { k = "enter", dir = "D", slot = 1, tx = 12, ty = 18,
      why = "NORM 62: le scale al contrario" },
    { k = "step", dir = "D", n = 16, why = "1F: fino a (12,34)" },
    { k = "step", dir = "D", n = 1, why = "1F: la soglia (12,35)" },
    { k = "exitow", dir = "D", wx = 153, wy = 159,
      why = "EXIT 4: il portone, overworld a (153,159)" },
    { k = "shot", why = "OVERWORLD -- appena fuori dal castello" },

    -- ---- overworld -> tempio (rotta BFS, 74 passi + l'ingresso) ---------
    { k = "owstep", dir = "D", n = 1,  why = "ow: giu' dal portone" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "D", n = 4,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "D", n = 3,  why = "ow" },
    { k = "owstep", dir = "L", n = 5,  why = "ow: si aggira la citta'" },
    { k = "owstep", dir = "U", n = 2,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 2,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 2,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 9,  why = "ow: su lungo il fiume" },
    { k = "owstep", dir = "L", n = 3,  why = "ow" },
    { k = "owstep", dir = "U", n = 1,  why = "ow" },
    { k = "owstep", dir = "L", n = 2,  why = "ow" },
    { k = "owstep", dir = "U", n = 1,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 1,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 10, why = "ow" },
    { k = "owstep", dir = "L", n = 2,  why = "ow" },
    { k = "owstep", dir = "U", n = 1,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 8,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 1,  why = "ow" },
    { k = "owstep", dir = "L", n = 1,  why = "ow" },
    { k = "owstep", dir = "U", n = 6,  why = "ow: l'ultima salita" },
    { k = "enter", dir = "L", slot = 3, tx = 20, ty = 30,
      why = "ENTR 13: il Temple of Fiends a (20,30)" },
    { k = "shot", why = "TEMPLE OF FIENDS -- l'ingresso" },

    -- ---- Garland: routine 11 -------------------------------------------
    { k = "step", dir = "U", n = 8, why = "tempio: fino a (20,22)" },
    { k = "wall", dir = "U", why = "Garland a (20,21) blocca il passo" },
    { k = "talk", why = "si parla a Garland", obj = 0x02,
      lines = { "No one touches my", "Princess!!" } },
    { k = "shot", why = "GARLAND -- nessuno tocca la principessa" },
    { k = "close", why = "Garland: dlg [1] e chiede la BATTAGLIA",
      dlg = 0x04, fx = 0x02 },
    { k = "battle", why = "la battaglia con Garland ($7F)" },
    { k = "shot", why = "TEMPIO -- dopo la battaglia, Garland non c'e' piu'" },
    { k = "at", slot = 3, tx = 20, ty = 22,
      why = "dopo la battaglia si e' dove si era" },

    -- ---- la principessa rapita: routine 9 ------------------------------
    -- La casella di Garland adesso e' libera: tre passi fino a (20,19).
    { k = "step", dir = "U", n = 3, why = "sopra la casella di Garland" },
    { k = "wall", dir = "U", why = "la principessa a (20,18) blocca il passo" },
    { k = "talk", why = "si parla alla principessa rapita", obj = 0x03,
      lines = { "So, you are the", "LIGHT WARRIORS!" } },
    { k = "close", why = "principessa: dlg [1] e chiede il TELEPORT",
      dlg = 0x05, fx = 0x04 },
    -- Il NORM $3F la riporta a casa: castello 2F, stanza a (12,7).
    { k = "at", slot = 2, tx = 12, ty = 7, timeout = 500,
      why = "NORMTELE_SAVEDPRINCESS: castello 2F a (12,7)" },
    { k = "shot", why = "CASTELLO 2F -- la stanza della principessa" },

    -- ---- il LUTE: routine 10 -------------------------------------------
    { k = "step", dir = "U", n = 2, why = "fino a (12,5)" },
    { k = "wall", dir = "L", why = "la principessa SALVATA a (11,5) e' visibile e blocca" },
    { k = "talk", why = "la principessa da' il LUTE", obj = 0x12,
      lines = { "This LUTE has been", "passed down from Queen" } },
    { k = "shot", why = "IL LUTE -- 2000 anni di regine" },
    { k = "close", why = "principessa: dlg [1] con la FANFARA",
      dlg = 0x06, fx = 0x01, wait = 260 },
    { k = "flag", why = "il LUTE e' nello zaino", lute = true, want = 1 },

    -- ---- il Re accende il ponte: routine 8, ramo [2] --------------------
    { k = "wall", dir = "U", why = "il Re a (12,4), di nuovo" },
    { k = "talk", why = "il Re ringrazia e ordina il ponte", obj = 0x01,
      lines = { "Thank you for saving the", "Princess. To aid your" } },
    { k = "shot", why = "IL PONTE -- ordinato" },
    { k = "close", why = "il Re: dlg [2] con la FANFARA",
      dlg = 0x02, fx = 0x01, wait = 260 },
    { k = "flag", why = "WPROG_BRIDGE acceso", addr = WORLD_PROGRESS, mask = 0x01, want = 1 },

    -- ---- il Re, terza battuta: il ramo [3] ------------------------------
    { k = "talk", why = "il Re a ponte costruito", obj = 0x01,
      lines = { "The Princess always", "worries about you." } },
    { k = "close", why = "il Re: dlg [3], nessun effetto", dlg = 0x03, fx = 0x00 },
    { k = "done" },
}

local pi, reps, phase, timer = 1, 0, "idle", 0
local start_mx, start_my, start_hits

local WALL_PRESS = 40
local STEP_LIMIT = 240
local SETTLE     = 20
local TALK_PRESS = 20
local TALK_DRAW  = 40
local ENTER_LIMIT = 600     -- expand_town costa ~140 quadri, piu' la grafica
local BATTLE_LIMIT = 4200

local function check_lines(a)
    for i, want in ipairs(a.lines) do
        local got = vram_text(TEXT_ROW + i - 1, TEXT_COL, #want)
        report(got == want, string.format("riga %d: <%s> atteso <%s>", i, got, want))
    end
end

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); pi = pi + 1; return end
    if a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    end
    if a.k == "flag" then
        local addr = a.addr or lute_addr()
        local v = u8(addr)
        local got = a.mask and ((v & a.mask) ~= 0 and 1 or 0) or v
        report(got == a.want, string.format("%s: RAM[%04X]=%02X -> %d, atteso %d",
               a.why, addr, v, got, a.want))
        pi = pi + 1; return
    end

    start_mx, start_my = b("town_mx"), b("town_my")
    start_hits = b("town_talk_hits")
    if a.k == "talk" or a.k == "close" then
        print(string.format("f=%d  %s", frames, a.why))
        phase = "press"; timer = 0; return
    end
    if a.k == "battle" or a.k == "at" then
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

    if a.k == "battle" then
        -- La PULSAZIONE di FIRE1 di mame_drive_battle.lua: durante la
        -- risoluzione l'overlay non legge il joystick, quindi le pressioni
        -- che cadono li' si perdono e il driver non corre piu' del gioco.
        -- La battaglia e' finita quando run_battle azzera il magic.
        local m = u16(BATTLE_MAGIC_A)
        if timer < 60 then return end   -- l'arena si sta disegnando
        if m == 0 and timer > 120 then
            report(true, string.format("%s: chiusa a f=%d (timer %d)", a.why, frames, timer))
            fire1(false)
            -- il ritorno rimette grafica e tema della mappa: si lascia respirare
            phase = "settle"; timer = -120; reps = 0; pi = pi + 1
            return
        end
        local kk = timer % 24
        if kk == 0 then fire1(true) elseif kk == 5 then fire1(false) end
        if timer >= BATTLE_LIMIT then
            report(false, string.format("%s: NON chiusa dopo %d quadri (magic=%04X)",
                   a.why, timer, m))
            fire1(false); next_action()
        end
        return
    end

    if a.k == "at" then
        local okpos = (b("cur_map_slot") == a.slot and b("town_mx") == a.tx
                       and b("town_my") == a.ty)
        if okpos then
            report(true, string.format("%s: mappa %d (%d,%d)", a.why,
                   a.slot, a.tx, a.ty))
            next_action(); return
        end
        if timer >= (a.timeout or 120) then
            report(false, string.format("%s: mappa %d (%d,%d), atteso %d (%d,%d)",
                   a.why, b("cur_map_slot"), b("town_mx"), b("town_my"),
                   a.slot, a.tx, a.ty))
            next_action()
        end
        return
    end

    if a.k == "talk" then
        if timer < TALK_PRESS then fire1(true); return end
        fire1(false)
        if timer < TALK_PRESS + TALK_DRAW then return end
        local hits = b("town_talk_hits")
        report(hits == ((start_hits + 1) % 256),
               string.format("%s: parlate %d -> %d", a.why, start_hits, hits))
        report(b("town_talk_obj") == a.obj,
               string.format("%s: obj %02X, atteso %02X", a.why, b("town_talk_obj"), a.obj))
        check_lines(a)
        next_action(); return
    end

    if a.k == "close" then
        if timer < TALK_PRESS then fire1(true); return end
        fire1(false)
        if timer < TALK_PRESS + TALK_DRAW then return end
        report(b("town_talk_dlg") == a.dlg,
               string.format("%s: dlg %02X, atteso %02X", a.why, b("town_talk_dlg"), a.dlg))
        -- Il byte alto del ritorno dell'overlay: 0 niente, 1 fanfara,
        -- 2 battaglia, 4 teletrasporto (TALK_FX_* >> 8).
        report(b("town_talk_fx") == a.fx,
               string.format("%s: fx %02X, atteso %02X", a.why, b("town_talk_fx"), a.fx))
        -- La fanfara BLOCCA il gioco per ~200 quadri: le azioni successive
        -- devono aspettare che finisca, o i loro tasti cadono nel vuoto.
        if a.wait then phase = "settle"; timer = -(a.wait); reps = 0; pi = pi + 1
        else next_action() end
        return
    end

    if a.k == "wall" then
        if timer >= WALL_PRESS then
            release_all()
            local mx, my = b("town_mx"), b("town_my")
            local moved = (mx ~= start_mx or my ~= start_my)
            report(not moved, string.format("%s: %s -> (%d,%d)", a.why,
                moved and "SI E' MOSSO" or "fermo", mx, my))
            next_action()
        end
        return
    end

    if a.k == "enter" then
        -- Si TIENE PREMUTA la direzione finche' lo slot di mappa non cambia,
        -- e si rilascia in quell'istante. Una pulsazione corta (8 quadri, la
        -- prima stesura) cade dentro il ridisegno del passo precedente --
        -- quando il gioco il joystick non lo legge -- e il passo non parte
        -- MAI: e' costato trentotto rossi a cascata. Rilasciare al cambio di
        -- slot invece e' sicuro: cur_map_slot lo scrive town_select_map
        -- PRIMA di enter_town, e per i ~140 quadri dell'espansione il gioco
        -- e' bloccato -- il tasto e' gia' su quando il ciclo nuovo riparte.
        if b("cur_map_slot") ~= a.slot then
            dpad(DPAD[a.dir], true)
            if timer >= ENTER_LIMIT then
                release_all()
                report(false, string.format("%s: mappa %d (%d,%d), atteso %d (%d,%d)",
                    a.why, b("cur_map_slot"), b("town_mx"), b("town_my"),
                    a.slot, a.tx, a.ty))
                next_action()
            end
            return
        end
        release_all()
        -- Lo slot e' quello atteso: si aspetta che anche la posizione lo
        -- sia (enter_town la scrive presto, ma non nello stesso quadro).
        if b("town_mx") == a.tx and b("town_my") == a.ty then
            report(true, string.format("%s: mappa %d (%d,%d)", a.why, a.slot, a.tx, a.ty))
            -- respiro lungo: la grafica nuova sta ancora arrivando
            phase = "settle"; timer = -160; reps = 0; pi = pi + 1
            return
        end
        if timer >= ENTER_LIMIT then
            report(false, string.format("%s: mappa %d ma posizione (%d,%d), attesa (%d,%d)",
                a.why, a.slot, b("town_mx"), b("town_my"), a.tx, a.ty))
            next_action()
        end
        return
    end

    if a.k == "exitow" then
        -- Stessa regola dell'enter: si tiene premuto finche' town_warp_out
        -- non si alza, e si rilascia in quell'istante.
        if b("town_warp_out") ~= 1 then
            dpad(DPAD[a.dir], true)
            if timer >= ENTER_LIMIT then
                release_all()
                report(false, string.format("%s: warp_out=%d dopo %d quadri",
                    a.why, b("town_warp_out"), timer))
                next_action()
            end
            return
        end
        release_all()
        if timer < 40 then return end   -- enter_ow sta ridisegnando
        local wx, wy = b("world_player_mx"), b("world_player_my")
        report(wx == a.wx and wy == a.wy,
               string.format("%s: ow=(%d,%d), atteso (%d,%d)", a.why, wx, wy, a.wx, a.wy))
        phase = "settle"; timer = -80; reps = 0; pi = pi + 1
        return
    end

    -- step / owstep: il passo si vede dalla POSIZIONE, non dal tempo.
    local mx, my
    if a.k == "owstep" then mx, my = b("world_player_mx"), b("world_player_my")
    else mx, my = b("town_mx"), b("town_my") end

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

-- Per gli owstep la posizione di partenza e' quella OW.
local orig_begin = begin_action
begin_action = function()
    local a = PLAN[pi]
    if a and a.k == "owstep" then
        start_mx, start_my = b("world_player_mx"), b("world_player_my")
        start_hits = b("town_talk_hits")
        if reps == 0 then
            print(string.format("f=%d  %s (%s)  da %s", frames, a.why, a.dir, pos()))
        end
        dpad(DPAD[a.dir], true)
        phase = "press"; timer = 0
        return
    end
    orig_begin()
end

-- ============================================================
--  l'apertura: stesso salto dell'intro di mame_drive_npc.lua
-- ============================================================
local PLAN_FROM = 2350

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    -- SOLO FIRE1 per superare l'intro, e SOLO fino al 2200: oltre, un FIRE1
    -- cieco aprirebbe un dialogo.
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
    elseif frames == 2200 then
        fire1(false)
    end
    if frames == 2300 then shot("overworld allo spawn") end
    if frames > PLAN_FROM then frame_action() end
end)
