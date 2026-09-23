-- mame_drive_itemshop.lua -- si comprano gli oggetti: quantita', tetto, oro,
-- e la persistenza dello zaino all'uscita.  (slice71)
--
-- PERCHE' UNO SCRIPT NUOVO E NON UN PEZZO IN PIU'
-- Stessa ragione per cui mame_drive_magicshop.lua e' nato separato da
-- mame_drive_shop.lua: il portafoglio. Il gruppo parte con 400 GP, questa
-- corsa ne spende 345 apposta -- l'ultimo acquisto DEVE fallire per mancanza
-- d'oro, ed e' una delle prove. Incastrata dentro un'altra corsa, quel
-- fallimento diventerebbe un effetto collaterale invece di un risultato.
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_ITEM (ROM col suffisso _t).
-- Serve per UNA cosa sola: `PARTY.item[PURE]` seminato a 98. Il tetto di 99
-- per tipo non si raggiungerebbe mai comprando -- a 75 GP l'una servirebbero
-- 7425 GP -- e resterebbe l'unico rifiuto del negozio mai esercitato.
-- 98 e non 99 apposta: cosi' la corsa prova PRIMA che l'ultimo acquisto
-- consentito passi, e solo dopo che il successivo venga rifiutato. Partendo da
-- 99 un negozio guasto che rifiuta sempre supererebbe la prova.
--
-- LE PROVE, e perche' quelle:
--   1. il negozio si apre         -> shop_id 61, tre voci (HEAL PURE TENT):
--                                    la lista del ROM ne dichiara cinque e si
--                                    ferma al primo zero
--   2. la colonna delle quantita' -> quello che il giocatore vede, e l'unico
--                                    posto in cui il seme a 98 e' visibile
--   3. HEAL comprata due volte    -> la quantita' SOMMA (0->1->2) e l'oro
--                                    scende due volte: e' la differenza fra
--                                    "scrive 1" e "incrementa"
--   4. il tastierino sceglie      -> voce 2 con un tasto solo, senza scorrere
--   5. PURE 98 -> 99              -> l'ultimo acquisto consentito passa
--   6. PURE ancora                -> RIFIUTATO dal tetto: ne' oro ne' quantita'
--   7. TENT due volte             -> l'oro scende sotto il prezzo
--   8. TENT la terza              -> RIFIUTATO dall'oro, con l'altro messaggio
--   9. fuori dal negozio          -> lo zaino c'e' ancora. `PARTY.item[]` sta
--                                    in RAM SGM, non nella BSS dell'overlay:
--                                    se fosse finito li' sparirebbe uscendo, e
--                                    a schermo sembrerebbe che il negozio non
--                                    ha mai venduto niente
--
-- USO
--   .\tools\build_all.ps1 -Slice slice71 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23' -Defines FORCE_ITEM
--   & mame.exe coleco -exp sgm -cart build\slice71_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 500 `
--       -autoboot_script tools\mame_drive_itemshop.lua

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")
local mem = manager.machine.devices[":maincpu"].spaces["program"]

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end

-- --- sonde della slice -----------------------------------------------------
local missing = {}
local function has(name)
    if probe[name] then return true end
    if not missing[name] then
        missing[name] = true
        print("!! SONDA MANCANTE: " .. name .. " -- il campo sara' n/d")
    end
    return false
end
for _, n in ipairs({ "town_mx", "town_my", "town_shop_id", "main_bank",
                     "party_chr_size" }) do has(n) end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

-- --- il gruppo in RAM SGM (party_state.h) ----------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A          -- slice71: e' cambiato, c'e' l'inventario
local PARTY_N     = 4
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6  -- magic(2) n(1) gp(3)
local O_CLS, O_AIL, O_NAME = 0, 1, 2
local O_CURHP, O_MAXHP     = 12, 14
local O_LEVEL              = 27

-- --- lo ZAINO --------------------------------------------------------------
-- Sta IN CODA al blocco, dopo i quattro personaggi, e il suo indirizzo si
-- RICAVA dal passo che il gioco pubblica invece di essere cablato: e' la
-- trappola numero 1 del catalogo, gia' costata una corsa intera quando la voce
-- del personaggio e' passata da 44 a 79. Cablando 0x6100+322 questo script
-- leggerebbe l'inventario giusto oggi e le magie di qualcuno domani.
local function inv_base() return CHR0 + PARTY_N * CHR_SIZE end
local function inv(id)    return u8(inv_base() + id) end
local ITEM_HEAL, ITEM_PURE, ITEM_TENT = 0x19, 0x1A, 0x16
local ITEM_NAME = { [0x16] = "TENT", [0x17] = "CABIN", [0x18] = "HOUSE",
                    [0x19] = "HEAL", [0x1A] = "PURE",  [0x1B] = "SOFT" }

local function refresh_chr_size()
    if not probe.party_chr_size then return end
    local v = u8(probe.party_chr_size)
    if v ~= 0 and v ~= CHR_SIZE then
        print(string.format("passo del personaggio: il gioco dice %d, lo script diceva %d -- uso quello del gioco", v, CHR_SIZE))
        CHR_SIZE = v
    end
end
local function chr(i, off) return u8(CHR0 + i * CHR_SIZE + off) end
local function chr16(i, off) return u16(CHR0 + i * CHR_SIZE + off) end
local function gold()
    return u8(PARTY_BASE + 3) + u8(PARTY_BASE + 4) * 256 + u8(PARTY_BASE + 5) * 65536
end
local CLSNAME = {[0]="FT",[1]="TH",[2]="BB",[3]="RM",[4]="WM",[5]="BM"}
local function name_of(i)
    local s = ""
    for k = 0, 5 do
        local c = chr(i, O_NAME + k)
        if c == 0 then break end
        s = s .. string.char(c)
    end
    return s
end
local function dump_inv(why)
    local parts = {}
    for id = 0x16, 0x1B do
        parts[#parts + 1] = string.format("%s=%d", ITEM_NAME[id], inv(id))
    end
    -- Anche gli oggetti CHIAVE, in blocco: sono le caselle $01-$15 e devono
    -- restare a zero. Un byte acceso li' vorrebbe dire che l'azzeramento non
    -- ha coperto tutto lo zaino, e nessuna delle prove qui sotto lo vedrebbe.
    local keys = 0
    for id = 0x00, 0x15 do keys = keys + inv(id) end
    print(string.format("-- zaino %s   oro=%d   %s   (somma delle caselle chiave: %d)",
        why, gold(), table.concat(parts, " "), keys))
end
local function dump_party(why)
    print(string.format("-- %s   oro=%d", why, gold()))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s %s lv%d HP %d/%d",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??", chr(i, O_LEVEL),
            chr16(i, O_CURHP), chr16(i, O_MAXHP)))
    end
    dump_inv(why)
end

-- --- il listino composto (shop_state.h) ------------------------------------
local SHOP_BASE  = 0x6300
local SHOP_MAGIC = 0x5703

-- --- ingressi --------------------------------------------------------------
local function find_port_field(port_name, field_name)
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
-- "P1 Button 2" del keypad, FIRE2 e' "P1 Button 1" del joystick.
local function fire1(on) find_port_field(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
local function fire2(on) find_port_field(":STD_JOY1", "P1 Button 1"):set_value(on and 1 or 0) end
local DPAD = { U = "P1 Up", D = "P1 Down", L = "P1 Left", R = "P1 Right" }
local function dpad(name, on) find_port_field(":STD_JOY1", name):set_value(on and 1 or 0) end
local function release_all()
    for _, nm in pairs(DPAD) do dpad(nm, false) end
    fire1(false); fire2(false)
end
local function press(btn, on)
    if btn == "F1" then fire1(on)
    elseif btn == "F2" then fire2(on)
    else dpad(DPAD[btn], on) end
end

-- Le CIFRE del tastierino: i campi si chiamano "3 (pad 1)", non
-- "P1 Keypad 3" -- la cifra sta in TESTA. Cercarla in coda non da' errore di
-- sintassi, da' tasti che non arrivano, cioe' un negozio che nel log sembra
-- ignorare il tastierino. Copiato da mame_drive_magicshop.lua, dove la forma
-- e' stata pagata.
local KEYPAD = {}
local keypad_dumped = false
local function keypad_field(ch)
    if KEYPAD[ch] then return KEYPAD[ch] end
    local port = manager.machine.ioport.ports[":STD_KEYPAD1"]
    if not port then error("porta del tastierino non trovata") end
    if not keypad_dumped then
        keypad_dumped = true
        local names = {}
        for nm, _ in pairs(port.fields) do names[#names + 1] = nm end
        table.sort(names)
        print("campi di :STD_KEYPAD1 -> " .. table.concat(names, " | "))
    end
    for nm, f in pairs(port.fields) do
        if nm:sub(1, 1) == ch and nm:find("pad") then
            KEYPAD[ch] = f
            print(string.format("tastierino '%s' -> campo \"%s\"", ch, nm))
            return f
        end
    end
    error("tasto del tastierino non trovato: " .. ch)
end
local function keypad(ch, on) keypad_field(ch):set_value(on and 1 or 0) end
local function is_digit(btn) return btn == "1" or btn == "2" or btn == "3" or btn == "4" end
local function press_any(btn, on)
    if is_digit(btn) then keypad(btn, on) else press(btn, on) end
end
local function release_everything()
    release_all()
    for _, f in pairs(KEYPAD) do f:set_value(0) end
end

local ok_count, fail_count = 0, 0
local function report(good, msg)
    if good then ok_count = ok_count + 1 else fail_count = fail_count + 1 end
    print(string.format("  [%s] %s", good and " ok " or "FALLITO", msg))
end
local function pos()
    return string.format("citta'=(%d,%d) shop=%d banco=%d",
        b("town_mx"), b("town_my"), b("town_shop_id"), b("main_bank"))
end
local function shot(label)
    print(string.format("SNAP (%s) @frame %d  %s", label, frames, pos()))
    manager.machine.video:snapshot()
end

-- CIO' CHE E' DAVVERO IN VRAM. La colonna delle quantita' e i due messaggi di
-- rifiuto non lasciano traccia in RAM: senza questa lettura, un negozio che
-- aggiorna l'inventario ma non ridisegna la colonna passerebbe tutte le prove.
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]
local function vram_row(row)
    local s = ""
    for c = 0, 31 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
    end
    return s
end
local function vram_text(row, col, len)
    local s = ""
    for c = col, col + len - 1 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
    end
    return s
end
local function check_cursor(why, row0, step, n, sel)
    local bad = {}
    for i = 0, n - 1 do
        local r = row0 + i * step
        local t = vram:read_u8(0x1800 + r * 32)
        local want = (i == sel) and 0x3E or 0x20
        if t ~= want then
            bad[#bad + 1] = string.format("riga %d: $%02X invece di $%02X", r, t, want)
        end
    end
    if #bad == 0 then
        report(true, string.format("%s: cursore solo sulla riga %d", why, row0 + sel * step))
    else
        report(false, string.format("%s: %s", why, table.concat(bad, ", ")))
    end
end
local function dump_screen(why, r0, r1)
    print(string.format("   [VRAM %s]", why))
    for r = r0, r1 do print(string.format("     %2d |%s|", r, vram_row(r))) end
end

-- La voce `k` del listino: quantita' in RAM e quantita' a schermo, insieme.
-- Separate sarebbero due prove che passano indipendentemente; insieme sono
-- l'unica che dice "il giocatore vede quello che il gioco ha scritto".
local ROW_ITEM0 = 3
local COL_QTY   = 26
local function check_qty(why, k, id, want)
    local row = ROW_ITEM0 + k * 2
    local got = inv(id)
    report(got == want, string.format("%s: in RAM %s = %d (atteso %d)",
        why, ITEM_NAME[id] or string.format("$%02X", id), got, want))
    local txt  = vram_text(row, COL_QTY, 4)
    local wtxt = string.format("x%3d", want)
    report(txt == wtxt, string.format("%s: a schermo riga %d = '%s' (atteso '%s')",
        why, row, txt, wtxt))
end
local function check_text(why, row, col, want)
    local got = vram_text(row, col, #want)
    report(got == want, string.format("%s: riga %d = '%s' (atteso '%s')", why, row, got, want))
end

-- =====================================================================
--  il piano
-- =====================================================================
-- Il cammino esce da:  .\tools\plan_town_route.ps1 -ToShop 61
-- Copiato, non riscritto: una rotta indovinata a mano finisce dentro un muro,
-- e nel log un passo bloccato per rotta sbagliata e uno bloccato per
-- collisione rotta si scrivono nello stesso modo.
local SNAP = {}

local PLAN = {
    -- ---------- il negozio di oggetti (shop_id 61), porta a (27,10) --------
    { k = "step", dir = "U", n = 10, why = "fino a (16,13)" },
    { k = "step", dir = "R", n = 1,  why = "fino a (17,13)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (17,12)" },
    { k = "step", dir = "R", n = 3,  why = "fino a (20,12)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (20,11)" },
    { k = "step", dir = "R", n = 7,  why = "fino a (27,11)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (27,10): la porta apre il negozio" },
    { k = "wait", n = 120, why = "il negozio di oggetti si disegna" },
    { k = "check_shop", want = 61, why = "shop_id del negozio di oggetti" },
    { k = "chk", why = "il listino composto", fn = function()
        report(u16(SHOP_BASE) == SHOP_MAGIC,
            string.format("magic del listino = $%04X (atteso $%04X)", u16(SHOP_BASE), SHOP_MAGIC))
        report(u8(SHOP_BASE + 3) == 6,
            string.format("tipo = %d (atteso 6: oggetti)", u8(SHOP_BASE + 3)))
        -- La lista del ROM e' [19 1A 16 00 20]: cinque byte dichiarati, ma si
        -- ferma al primo zero perche' le liste si SOVRAPPONGONO e il $20 dopo
        -- appartiene gia' al negozio successivo. Quattro voci qui vorrebbero
        -- dire che lo zero viene saltato invece che rispettato.
        report(u8(SHOP_BASE + 4) == 3,
            string.format("voci = %d (attese 3: HEAL PURE TENT, la lista chiude al primo zero)", u8(SHOP_BASE + 4)))
    end },
    { k = "screen", why = "il negozio di oggetti appena aperto", r0 = 1, r1 = 16 },
    { k = "shot", why = "OGGETTI -- listino, prezzi e lo zaino" },
    { k = "cursor", why = "appena aperto, il cursore sta sulla voce 1", row0 = 3, step = 2, n = 3, sel = 0 },

    -- La colonna delle quantita' PRIMA di comprare. Il 98 su PURE viene dal
    -- seme di -DFORCE_ITEM: se questo controllo fallisce, la ROM caricata non
    -- e' la build di prova e tutto il resto della corsa non significa niente.
    { k = "qty", k2 = 0, id = 0x19, want = 0,  why = "HEAL prima di comprare" },
    { k = "qty", k2 = 1, id = 0x1A, want = 98, why = "PURE seminata a 98 (-DFORCE_ITEM)" },
    { k = "qty", k2 = 2, id = 0x16, want = 0,  why = "TENT prima di comprare" },

    -- ---------- prova 1: HEAL, due volte ----------
    { k = "snap", why = "prima di HEAL" },
    { k = "tap", btn = "F1", why = "FIRE1: compra HEAL (60 GP)" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "qty", k2 = 0, id = 0x19, want = 1, why = "HEAL comprata" },
    { k = "chk", why = "l'oro dopo la prima HEAL", fn = function()
        report(gold() == SNAP.gold - 60, string.format("oro = %d (era %d, HEAL costa 60)", gold(), SNAP.gold))
    end },
    { k = "text", row = 22, col = 1, want = "THANK YOU!", why = "il messaggio dell'acquisto" },
    { k = "snap", why = "prima della seconda HEAL" },
    { k = "tap", btn = "1", why = "tastierino 1: la voce 1, senza scorrere" },
    { k = "cursor", why = "il tastierino ha scelto la voce 1", row0 = 3, step = 2, n = 3, sel = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: compra HEAL un'altra volta" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    -- 2 e non 1: e' la differenza fra un negozio che INCREMENTA e uno che
    -- SCRIVE. Con una sola compera i due si comportano allo stesso modo.
    { k = "qty", k2 = 0, id = 0x19, want = 2, why = "HEAL comprata due volte: somma" },
    { k = "chk", why = "l'oro dopo la seconda HEAL", fn = function()
        report(gold() == SNAP.gold - 60, string.format("oro = %d (era %d)", gold(), SNAP.gold))
    end },
    { k = "shot", why = "OGGETTI -- due HEAL nello zaino" },

    -- ---------- prova 2: PURE, l'ultimo posto e poi il tetto ----------
    { k = "snap", why = "prima di PURE" },
    { k = "tap", btn = "2", why = "tastierino 2: dritti a PURE" },
    { k = "cursor", why = "il tastierino ha scelto la voce 2", row0 = 3, step = 2, n = 3, sel = 1 },
    { k = "tap", btn = "F1", why = "FIRE1: compra PURE, la novantanovesima" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "qty", k2 = 1, id = 0x1A, want = 99, why = "PURE: l'ultimo acquisto consentito passa" },
    { k = "chk", why = "l'oro dopo PURE", fn = function()
        report(gold() == SNAP.gold - 75, string.format("oro = %d (era %d, PURE costa 75)", gold(), SNAP.gold))
    end },
    { k = "snap", why = "prima di PURE oltre il tetto" },
    { k = "tap", btn = "F1", why = "FIRE1: compra PURE la centesima" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "qty", k2 = 1, id = 0x1A, want = 99, why = "PURE: il tetto regge" },
    { k = "chk", why = "il tetto non costa niente", fn = function()
        report(gold() == SNAP.gold, string.format("oro = %d: niente speso (era %d)", gold(), SNAP.gold))
    end },
    { k = "text", row = 22, col = 1, want = "YOU'RE CARRYING TOO MANY", why = "il messaggio del tetto" },
    { k = "shot", why = "OGGETTI -- 99 PURE, il negozio rifiuta" },

    -- ---------- prova 3: TENT finche' l'oro basta ----------
    -- Restano 205 GP e la tenda ne costa 75: due passano, la terza no. Il
    -- rifiuto per mancanza d'oro e quello per il tetto sono due strade diverse
    -- dentro la stessa funzione, e vanno distinti dal MESSAGGIO -- in RAM si
    -- scrivono uguali, cioe' non scrivendo niente.
    { k = "snap", why = "prima delle tende" },
    { k = "tap", btn = "3", why = "tastierino 3: dritti a TENT" },
    { k = "cursor", why = "il tastierino ha scelto la voce 3", row0 = 3, step = 2, n = 3, sel = 2 },
    { k = "tap", btn = "F1", why = "FIRE1: prima tenda (75 GP)" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "tap", btn = "F1", why = "FIRE1: seconda tenda (75 GP)" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "qty", k2 = 2, id = 0x16, want = 2, why = "due tende" },
    { k = "chk", why = "l'oro dopo due tende", fn = function()
        report(gold() == SNAP.gold - 150, string.format("oro = %d (era %d, due tende costano 150)", gold(), SNAP.gold))
        report(gold() < 75, string.format("e adesso non basta piu' per una terza: %d GP contro 75", gold()))
    end },
    { k = "snap", why = "prima della terza tenda" },
    { k = "tap", btn = "F1", why = "FIRE1: terza tenda, e l'oro non basta" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "qty", k2 = 2, id = 0x16, want = 2, why = "la terza tenda non e' arrivata" },
    { k = "chk", why = "il rifiuto per l'oro", fn = function()
        report(gold() == SNAP.gold, string.format("oro = %d: invariato (era %d)", gold(), SNAP.gold))
    end },
    { k = "text", row = 22, col = 1, want = "YOU CAN'T AFFORD IT", why = "il messaggio dell'oro" },
    { k = "shot", why = "OGGETTI -- l'oro e' finito" },

    -- ---------- prova 4: lo zaino sopravvive all'uscita ----------
    { k = "tap", btn = "F2", why = "FIRE2: si esce dal negozio" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "step", dir = "D", n = 1, why = "un passo fuori dalla porta" },
    { k = "chk", why = "lo zaino fuori dal negozio", fn = function()
        report(inv(ITEM_HEAL) == 2, string.format("HEAL = %d (attese 2)", inv(ITEM_HEAL)))
        report(inv(ITEM_PURE) == 99, string.format("PURE = %d (attese 99)", inv(ITEM_PURE)))
        report(inv(ITEM_TENT) == 2, string.format("TENT = %d (attese 2)", inv(ITEM_TENT)))
        -- Le caselle mai toccate devono essere ancora zero: e' la prova
        -- dell'azzeramento, e senza di essa un inventario "che funziona"
        -- potrebbe stare sopra spazzatura mai ripulita.
        local dirty = {}
        for id = 0x00, 0x15 do
            if inv(id) ~= 0 then dirty[#dirty + 1] = string.format("$%02X=%d", id, inv(id)) end
        end
        report(#dirty == 0, string.format("le caselle mai toccate sono a zero%s",
            (#dirty > 0) and (": SPORCHE " .. table.concat(dirty, " ")) or ""))
    end },
    { k = "shot", why = "CONERIA -- fuori dal negozio, lo zaino e' pieno" },
    { k = "dump", why = "alla fine" },
    { k = "done" },
}

-- =====================================================================
--  esecuzione
-- =====================================================================
local pi = 1
local reps = 0
local phase = "idle"
local timer = 0
local start_mx, start_my

local STEP_LIMIT = 240
local SETTLE     = 16
local TAP_PRESS  = 12    -- il negozio legge FRONTI: premuto e poi RILASCIATO
local TAP_REST   = 14

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); pi = pi + 1; return
    elseif a.k == "dump" then dump_party(a.why); pi = pi + 1; return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "snap" then
        SNAP.gold = gold()
        print(string.format("   [istantanea %s] oro=%d", a.why, SNAP.gold))
        pi = pi + 1; return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn()
        pi = pi + 1; return
    elseif a.k == "cursor" then
        check_cursor(a.why, a.row0, a.step, a.n, a.sel)
        pi = pi + 1; return
    elseif a.k == "qty" then
        check_qty(a.why, a.k2, a.id, a.want)
        pi = pi + 1; return
    elseif a.k == "text" then
        check_text(a.why, a.row, a.col, a.want)
        pi = pi + 1; return
    elseif a.k == "screen" then
        dump_screen(a.why, a.r0 or 0, a.r1 or 23)
        pi = pi + 1; return
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
    if a.k == "wait" then phase = "press"; timer = 0; return end
    if a.k == "tap" then
        print(string.format("f=%d  %s", frames, a.why))
        phase = "press"; timer = 0; return
    end
    if reps == 0 then print(string.format("f=%d  %s (%s)  da %s", frames, a.why, a.dir, pos())) end
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

    if a.k == "wait" then
        if timer >= a.n then next_action() end
        return
    end

    if a.k == "tap" then
        -- Premuto e RILASCIATO: dentro il negozio si comanda a fronti.
        if timer <= TAP_PRESS then press_any(a.btn, true)
        elseif timer <= TAP_PRESS + TAP_REST then press_any(a.btn, false)
        else release_everything(); next_action() end
        return
    end

    -- a.k == "step": si tiene premuto FINCHE' la posizione non cambia, e non
    -- per N frame -- il redraw della citta' si mangia un numero variabile di
    -- vblank e a tempo fisso lo stesso cammino esce diverso a ogni corsa.
    local mx, my = b("town_mx"), b("town_my")
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
        report(false, string.format("%s: passo %d bloccato, fermo a (%d,%d)", a.why, reps + 1, mx, my))
        next_action()
    end
end

-- =====================================================================
--  avvio: intro a pulsantate cieche, poi dentro Coneria
-- =====================================================================
local SEQ = {}
local function at(f, fn) SEQ[f] = fn end

local t = 2350
for i = 1, 3 do
    at(t,     function() dpad("P1 Up", true) end)
    at(t + 8, function() dpad("P1 Up", false) end)
    t = t + 60
end
at(t + 40, function() dpad("P1 Right", true) end)
at(t + 48, function() dpad("P1 Right", false) end)

-- expand_town espande 4096 macrotile in 16384 celle: ~140 frame.
local TOWN_READY = t + 300
at(TOWN_READY, function()
    refresh_chr_size()
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d  zaino a $%04X",
        u16(PARTY_BASE), PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE, inv_base()))
    if u16(PARTY_BASE) ~= PARTY_MAGIC then
        print("!! MAGIC DEL GRUPPO DIVERSO: il layout e' cambiato, i campi qui sotto non valgono")
    end
    dump_party("CONERIA -- ingresso")
end)

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
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
end)
