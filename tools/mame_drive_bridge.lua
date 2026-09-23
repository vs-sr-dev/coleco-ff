-- mame_drive_bridge.lua -- il PONTE (slice78).
--
-- Gira sulla build _t con FORCE_BRIDGE, che semina WPROG_BRIDGE e mette lo
-- spawn sulla riva sud: il ponte lo accende il Re in fondo a una quest di sei
-- tappe, e rifarla qui vorrebbe dire che un difetto del ponte e uno della
-- quest fanno fallire la stessa corsa. La quest ha gia' la sua corsa.
--
-- LE CINQUE COSE DA PROVARE, e perche' quattro NON si vedono a occhio
--  1. IL PONTE SI DISEGNA. Le quattro tile 236-239 devono stare nelle celle
--     giuste della name table. A occhio "un ponte c'e'" e "il ponte e' due
--     celle piu' in la'" sono la stessa immagine; dalla VRAM no.
--  2. SI ATTRAVERSA. La posizione in overworld cambia e arriva a (152,152) --
--     cioe' su un macrotile di OCEANO, che senza il ponte rifiuta il passo.
--  3. L'ACQUA INTORNO RESTA ACQUA. E' la meta' che si dimentica: un ponte
--     fatto cambiando l'attributo del macrotile renderebbe camminabile TUTTO
--     l'oceano di quel tipo, e la corsa passerebbe lo stesso. Qui si prova
--     che la casella ACCANTO al ponte rifiuta ancora.
--  4. LA SCENA PARTE, e parte UNA VOLTA SOLA. `bridgescene` fa 0 -> 2, e al
--     secondo passaggio resta 2. "Non e' partita" e "non ci sono passato"
--     dalla RAM si distinguono, a schermo no.
--  5. NIENTE INCONTRI SUL PONTE. Sotto c'e' oceano: un incontro li' sarebbe
--     una battaglia NAVALE presa a piedi. Si prova che il magic della
--     battaglia resta zero per tutta la traversata.

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")

local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

local BRIDGE_TILE_BASE = 236     -- src/ff1_bridge_tile.h
local BRIDGE_X, BRIDGE_Y = 152, 152
local VIEW_PX, VIEW_PY = 15, 11  -- il giocatore e' fisso a questa cella
local BATTLE_MAGIC_A = 0x6000

local missing = {}
local function has(name)
    if probe[name] then return true end
    if not missing[name] then
        missing[name] = true
        print("!! SONDA MANCANTE: " .. name .. " -- il campo sara' n/d")
    end
    return false
end
for _, n in ipairs({ "world_player_mx", "world_player_my", "bridgescene",
                     "main_bank", "audio_enabled", "audio_bank" }) do has(n) end

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

local function pos()
    return string.format("ow=(%d,%d) scena=%d", b("world_player_mx"),
                         b("world_player_my"), b("bridgescene"))
end

local function fields_get(p, f)
    local k = p .. "//" .. f
    if fields[k] then return fields[k] end
    local port = manager.machine.ioport.ports[p]
    if not port then error("porta non trovata: " .. p) end
    fields[k] = port.fields[f]
    if not fields[k] then error("campo non trovato: " .. p .. " " .. f) end
    return fields[k]
end
local function fire1(on) fields_get(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
local function dpad(nm, on) fields_get(":STD_JOY1", nm):set_value(on and 1 or 0) end
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

-- Dove cade il ponte sullo schermo, viste le coordinate del giocatore. Il
-- giocatore sta fisso alla cella (15,11) e una casella e' due celle.
local function bridge_screen_cell()
    local mx, my = b("world_player_mx"), b("world_player_my")
    return VIEW_PX + (BRIDGE_X - mx) * 2, VIEW_PY + (BRIDGE_Y - my) * 2
end

-- ============================================================
--  il piano
-- ============================================================
local PLAN = {
    { k = "shot", why = "OVERWORLD -- la riva sud, col ponte gia' costruito" },
    -- Il ponte si vede da lontano: siamo a (152,154), lui a (152,152), cioe'
    -- quattro celle piu' su -- dentro lo schermo.
    { k = "tiles", why = "il ponte e' disegnato prima di arrivarci" },
    { k = "step", dir = "U", n = 1, why = "fino a (152,153), la riva" },
    -- La traversata.
    { k = "step", dir = "U", n = 1, why = "SUL PONTE (152,152)" },
    { k = "at", x = 152, y = 152, why = "si e' sul ponte" },
    { k = "scene", why = "la scena del ponte parte e finisce" },
    { k = "shot", why = "OVERWORLD -- tornati dalla scena, sul ponte" },
    { k = "probe", why = "la scena e' segnata come fatta", scene = 2 },
    -- LA PROVA CHE IL PASSO E' UN'ECCEZIONE A UNA CASELLA SOLA, e va fatta
    -- DAL PONTE: la riga y=152 e' tutta oceano, quindi (151,152) e' acqua e
    -- deve rifiutare anche stando in piedi sul ponte. Se il ponte fosse stato
    -- fatto cambiando l'attributo del macrotile, tutto l'oceano di quel tipo
    -- sarebbe diventato camminabile e questo passo passerebbe.
    --
    -- La prima stesura provava l'acqua "a ovest della RIVA" (152,153) ed era
    -- SBAGLIATA: li' a ovest c'e' terra, e il gioco faceva bene a passare.
    -- Sesta volta che un controllo piu' preciso del vero accusa il codice
    -- giusto -- la mappa si guarda PRIMA di scrivere l'asserzione.
    { k = "wall", dir = "L", why = "dal ponte, l'oceano a ovest rifiuta ancora",
      expect_move = false },
    -- Dall'altra parte: (152,151) esiste solo passando dal ponte.
    { k = "step", dir = "U", n = 1, why = "sceso a nord, (152,151)" },
    { k = "at", x = 152, y = 151, why = "si e' sull'altra sponda" },
    { k = "shot", why = "OVERWORLD -- il continente nuovo" },
    -- Si ripassa: la scena NON deve ripartire.
    { k = "step", dir = "D", n = 1, why = "di nuovo sul ponte" },
    { k = "norescene", why = "la scena NON riparte" },
    { k = "done" },
}

local pi, reps, phase, timer = 1, 0, "idle", 0
local start_x, start_y

local WALL_PRESS  = 40
local STEP_LIMIT  = 240
local SETTLE      = 20
local SCENE_LIMIT = 3600     -- 4 pagine x 512 quadri massimi
local battle_seen = false

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); pi = pi + 1; return end
    if a.k == "done" then
        report(not battle_seen, "nessun incontro durante la traversata")
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    end
    if a.k == "tiles" then
        local sc, sr = bridge_screen_cell()
        local got, good = {}, true
        for q = 0, 3 do
            local c = sc + (q % 2)
            local r = sr + math.floor(q / 2)
            local t = -1
            if c >= 0 and c < 32 and r >= 0 and r < 24 then
                t = vram:read_u8(0x1800 + r * 32 + c)
            end
            got[#got + 1] = t
            if t ~= BRIDGE_TILE_BASE + q then good = false end
        end
        report(good, string.format("%s: tile %d,%d,%d,%d alla cella (%d,%d), attese %d..%d",
               a.why, got[1], got[2], got[3], got[4], sc, sr,
               BRIDGE_TILE_BASE, BRIDGE_TILE_BASE + 3))
        pi = pi + 1; return
    end
    if a.k == "at" then
        local x, y = b("world_player_mx"), b("world_player_my")
        report(x == a.x and y == a.y,
               string.format("%s: ow=(%d,%d), atteso (%d,%d)", a.why, x, y, a.x, a.y))
        pi = pi + 1; return
    end
    if a.k == "probe" then
        report(b("bridgescene") == a.scene,
               string.format("%s: bridgescene=%d, atteso %d", a.why, b("bridgescene"), a.scene))
        pi = pi + 1; return
    end
    start_x, start_y = b("world_player_mx"), b("world_player_my")
    if a.k == "scene" or a.k == "norescene" then
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

    -- Un incontro durante la traversata e' un difetto, e va visto ovunque
    -- capiti: sotto il ponte c'e' oceano.
    if u16(BATTLE_MAGIC_A) ~= 0 then battle_seen = true end

    if a.k == "scene" then
        -- La scena e' finita quando bridgescene vale 2 E il gioco e' tornato
        -- in overworld. Le pagine si sfogliano col tasto: una pulsazione,
        -- come in battaglia -- le pressioni che cadono nel ridisegno si
        -- perdono invece di accumularsi.
        local kk = timer % 30
        if kk == 0 then fire1(true) elseif kk == 6 then fire1(false) end
        if timer == 60 then shot("SCENA DEL PONTE -- la title card") end
        if b("bridgescene") == 2 and timer > 120 then
            fire1(false)
            report(true, string.format("%s: chiusa a f=%d", a.why, frames))
            phase = "settle"; timer = -120; reps = 0; pi = pi + 1
            return
        end
        if timer >= SCENE_LIMIT then
            fire1(false)
            report(false, string.format("%s: NON chiusa dopo %d quadri (scena=%d)",
                   a.why, timer, b("bridgescene")))
            next_action()
        end
        return
    end

    if a.k == "norescene" then
        -- Si preme la direzione e si guarda che NON succeda niente: la
        -- posizione cambia (si cammina sul ponte) ma la scena resta 2.
        if timer < WALL_PRESS then dpad(DPAD["D"], true); return end
        release_all()
        if timer < WALL_PRESS + 120 then return end
        report(b("bridgescene") == 2,
               string.format("%s: bridgescene=%d (atteso 2, cioe' invariato)",
                             a.why, b("bridgescene")))
        next_action(); return
    end

    local x, y = b("world_player_mx"), b("world_player_my")

    if a.k == "wall" then
        if timer >= WALL_PRESS then
            release_all()
            local moved = (x ~= start_x or y ~= start_y)
            report(moved == a.expect_move,
                   string.format("%s: %s -> (%d,%d)", a.why,
                                 moved and "si e' mosso" or "fermo", x, y))
            next_action()
        end
        return
    end

    -- step
    if x ~= start_x or y ~= start_y then
        release_all()
        reps = reps + 1
        if reps >= a.n then
            report(true, string.format("%s: arrivato a (%d,%d)", a.why, x, y))
            next_action()
        else
            phase = "settle"; timer = 0
        end
        return
    end
    if timer >= STEP_LIMIT then
        release_all()
        report(false, string.format("%s: passo %d bloccato, fermo a (%d,%d)",
                                    a.why, reps + 1, x, y))
        next_action()
    end
end

-- ============================================================
--  avvio: si salta l'intro a pulsantate cieche
-- ============================================================
local PLAN_FROM = 2350

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
    elseif frames == 2200 then
        fire1(false)
    end
    if frames > PLAN_FROM then frame_action() end
end)
