-- mame_drive_menumagic.lua -- MAGIC fuori dalla battaglia. (slice75)
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_MAGMENU (ROM col suffisso _t):
--   * classi FISSE FT/TH/WM/BM: il mago bianco e' quello che quelle magie le
--     impara, e gli altri tre sono i tre bersagli in tre condizioni che non si
--     sovrappongono -- ferito, avvelenato+pietrificato, caduto. Cosi' ogni
--     prova ha UN solo esito giusto;
--   * le tredici magie di fuori battaglia in mano al mago bianco, piu' HARM,
--     che e' da battaglia e serve al rifiuto;
--   * nove cariche per livello, tranne l'ottavo che parte a SECCO: e' l'unico
--     modo di esercitare "non hai cariche" in una corsa sola.
--
-- LE PROVE, e perche' quelle:
--   1. la griglia mostra gli otto livelli, le cariche e i nomi veri
--   2. CURE sul ferito          -> HP dentro l'intervallo NES 16-31
--   3. HARM (da battaglia)      -> rifiutata, e la carica NON si consuma
--   4. un livello vuoto         -> "NOTHING THERE"
--   5. HEAL                     -> cura TUTTI, ma salta il pietrificato e il
--      caduto (MenuRecoverPartyHP salta chi e' fuori dal campo)
--   6. PURE sull'avvelenato     -> il veleno se ne va, la pietra resta
--   7. CUR4 sul PIETRIFICATO    -> RIFIUTATA. E' il fix #1: sul NES CUR4 non
--      controlla le alterazioni (bank_0E.asm:6547 dice "BUGGED") e riempie gli
--      HP di un morto, che resta morto
--   8. SOFT                     -> la pietra si scioglie, e torna con 1 HP
--   9. CUR4 sul vivo            -> HP al massimo: l'altro ramo della stessa
--      magia, cosi' il rifiuto di prima non passa per "CUR4 non funziona"
--  10. LIFE sul caduto          -> in piedi con UN HP
--  11. LIF2 con l'ottavo a secco-> "NOT ENOUGH MP": le cariche si guardano
--      PRIMA dell'effetto, non dopo
--  12. EXIT in citta'           -> il gruppo torna in overworld
--  13. EXIT in OVERWORLD        -> "IT DOES NOTHING HERE" e la carica resta
--      (fix #2: il NES la consuma lo stesso). Questa prova serve DUE volte:
--      e' anche l'unico modo pulito di affermare che il passo 12 e' arrivato
--      davvero in overworld -- quel messaggio in citta' non compare.
--
-- COSA QUESTA CORSA NON PROVA, detto invece che taciuto: il ramo "HP pieni" di
-- LIF2, perche' servirebbe un secondo caduto e il gruppo ne ha uno solo. E'
-- una riga dentro un `if` che le altre prove coprono.
--
-- USO
--   .\tools\build_all.ps1 -Slice slice75 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23','ovl_menu:24','ovl_magic:25' -Defines FORCE_MAGMENU
--   & mame.exe coleco -exp sgm -cart build\slice75_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 600 `
--       -autoboot_script tools\mame_drive_menumagic.lua

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")
local mem = manager.machine.devices[":maincpu"].spaces["program"]

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end

local missing = {}
local function has(name)
    if probe[name] then return true end
    if not missing[name] then
        missing[name] = true
        print("!! SONDA MANCANTE: " .. name)
    end
    return false
end
for _, n in ipairs({ "town_mx", "town_my", "main_bank", "party_chr_size",
                     "world_player_mx", "world_player_my" }) do has(n) end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_CLS, O_AIL, O_NAME = 0, 1, 2
local O_CURHP, O_MAXHP     = 12, 14
local O_LEVEL              = 27
local O_CURMP0, O_MAXMP0   = 28, 36
local AIL_DEAD, AIL_STONE, AIL_POISON = 0x01, 0x02, 0x04
local WM = 2   -- il mago bianco: e' lui che lancia

local function refresh_chr_size()
    if not probe.party_chr_size then return end
    local v = u8(probe.party_chr_size)
    if v ~= 0 and v ~= CHR_SIZE then
        print(string.format("passo del personaggio: il gioco dice %d, lo script diceva %d", v, CHR_SIZE))
        CHR_SIZE = v
    end
end
local function chr(i, off) return u8(CHR0 + i * CHR_SIZE + off) end
local function chr16(i, off) return u16(CHR0 + i * CHR_SIZE + off) end
local function mp(lvl) return chr(WM, O_CURMP0 + lvl) end
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
local function dump_party(why)
    print(string.format("-- %s", why))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s %s HP %d/%d  mal=$%02X",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??",
            chr16(i, O_CURHP), chr16(i, O_MAXHP), chr(i, O_AIL)))
    end
    local m = {}
    for k = 0, 7 do m[#m + 1] = string.format("L%d %d/%d", k + 1, mp(k), chr(WM, O_MAXMP0 + k)) end
    print("   cariche del mago bianco: " .. table.concat(m, "  "))
end

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
local KEYPAD = {}
local function keypad_field(ch)
    if KEYPAD[ch] then return KEYPAD[ch] end
    local port = manager.machine.ioport.ports[":STD_KEYPAD1"]
    for nm, f in pairs(port.fields) do
        if nm:sub(1, 1) == ch and nm:find("pad") then KEYPAD[ch] = f; return f end
    end
    error("tasto del tastierino non trovato: " .. ch)
end
local function keypad(ch, on) keypad_field(ch):set_value(on and 1 or 0) end
local function press_any(btn, on)
    if btn:len() == 1 and btn >= "0" and btn <= "9" then keypad(btn, on) else press(btn, on) end
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
local function shot(label)
    print(string.format("SNAP (%s) @frame %d", label, frames))
    manager.machine.video:snapshot()
end

local vram = manager.machine.devices[":tms9928a"].spaces["vram"]
local function vram_text(row, col, len)
    local s = ""
    for c = col, col + len - 1 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
    end
    return s
end
local function check_text(why, row, col, want)
    local got = vram_text(row, col, #want)
    report(got == want, string.format("%s: riga %d col %d = '%s' (atteso '%s')", why, row, col, got, want))
end
local function dump_screen(why, r0, r1)
    print(string.format("   [VRAM %s]", why))
    for r = r0, r1 do
        local s = ""
        for c = 0, 31 do
            local t = vram:read_u8(0x1800 + r * 32 + c)
            s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
        end
        print(string.format("     %2d |%s|", r, s))
    end
end
-- Il cursore della griglia: '>' su una cella sola fra le ventiquattro.
-- Affermato e non fotografato, come vuole slice66.
local ROW_L0, COL_CELL0, CELL_STEP = 3, 8, 7
local function check_cursor(why, lvl, col)
    local bad = {}
    for l = 0, 7 do
        for k = 0, 2 do
            local t = vram:read_u8(0x1800 + (ROW_L0 + l) * 32 + COL_CELL0 + k * CELL_STEP)
            local want = (l == lvl and k == col) and 0x3E or 0x20
            if t ~= want then
                bad[#bad + 1] = string.format("L%d c%d: $%02X invece di $%02X", l + 1, k, t, want)
            end
        end
    end
    if #bad == 0 then report(true, string.format("%s: cursore su L%d colonna %d", why, lvl + 1, col))
    else report(false, string.format("%s: %s", why, table.concat(bad, ", "))) end
end

-- =====================================================================
--  il piano
-- =====================================================================
local SNAP = {}

local PLAN = {
    { k = "dump", why = "CONERIA -- ingresso, col gruppo seminato" },
    { k = "tap", btn = "F2", why = "FIRE2: si apre il menu" },
    { k = "wait", n = 60, why = "il menu si disegna" },
    { k = "text", row = 5, col = 4, want = "MAGIC", why = "la seconda voce non dice piu' NOT YET" },
    { k = "tap", btn = "2", why = "tastierino 2: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: chiede chi lancia" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: si apre la griglia" },
    { k = "wait", n = 120, why = "tredici nomi dal banco 11" },
    { k = "screen", why = "la griglia della magia", r0 = 1, r1 = 21 },
    { k = "shot", why = "MAGIC -- otto livelli, le cariche e i nomi veri" },
    { k = "text", row = 1,  col = 1,  want = "MAGIC",  why = "il titolo" },
    { k = "text", row = 1,  col = 8,  want = "MERLIN", why = "e chi lancia" },
    { k = "text", row = 3,  col = 0,  want = "L1",     why = "il primo livello" },
    { k = "text", row = 3,  col = 3,  want = "9/9",    why = "con le sue cariche" },
    { k = "text", row = 3,  col = 9,  want = "CURE",   why = "CURE al primo livello" },
    { k = "text", row = 3,  col = 16, want = "HARM",   why = "e HARM accanto (da battaglia)" },
    { k = "text", row = 4,  col = 9,  want = "----",   why = "il secondo livello e' vuoto" },
    { k = "text", row = 5,  col = 9,  want = "CUR2",   why = "terzo livello" },
    { k = "text", row = 5,  col = 16, want = "HEAL",   why = "e HEAL accanto" },
    { k = "text", row = 8,  col = 9,  want = "SOFT",   why = "sesto livello" },
    { k = "text", row = 8,  col = 16, want = "EXIT",   why = "e EXIT accanto" },
    { k = "text", row = 10, col = 3,  want = "0/9",    why = "l'ottavo livello e' a secco" },
    { k = "text", row = 10, col = 9,  want = "LIF2",   why = "e ci sta LIF2" },
    { k = "cursor", why = "appena aperta", lvl = 0, col = 0 },

    -- ---------- CURE sul ferito ----------
    { k = "snapshot" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia CURE" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "1", why = "tastierino 1: il guerriero, che ha 5 HP" },
    { k = "tap", btn = "F1", why = "FIRE1: curalo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 21, col = 1, want = "FEELING BETTER!", why = "l'esito e' scritto" },
    { k = "chk", why = "CURE sul ferito", fn = function()
        local hp = chr16(0, O_CURHP)
        -- 5 + 16..31, tagliato al massimo (il guerriero ne ha 35). L'intervallo
        -- e' quello del NES esatto: cambia il generatore, non i numeri.
        report(hp >= 21 and hp <= 35, string.format("HP = %d (5 + 16..31, max 35)", hp))
        report(mp(0) == 8, string.format("una carica di L1 consumata: %d (erano 9)", mp(0)))
    end },
    { k = "text", row = 3, col = 3, want = "8/9", why = "e la griglia lo dice" },

    -- ---------- HARM: e' da battaglia ----------
    { k = "tap", btn = "R", why = "destra: HARM" },
    { k = "cursor", why = "sul secondo posto", lvl = 0, col = 1 },
    { k = "tap", btn = "F1", why = "FIRE1: prova a lanciarla" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "text", row = 21, col = 1, want = "THAT ONE IS FOR BATTLE", why = "il rifiuto e' dichiarato" },
    { k = "chk", why = "un rifiuto non costa niente", fn = function()
        report(mp(0) == 8, string.format("le cariche di L1 non si sono mosse: %d", mp(0)))
    end },

    -- ---------- un livello vuoto ----------
    { k = "tap", btn = "D", why = "giu': il secondo livello, che e' vuoto" },
    { k = "tap", btn = "F1", why = "FIRE1: su una casella vuota" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "text", row = 21, col = 1, want = "NOTHING THERE", why = "casella vuota" },

    -- ---------- HEAL su tutti ----------
    { k = "tap", btn = "D", why = "giu': terzo livello, HEAL" },
    { k = "cursor", why = "su HEAL", lvl = 2, col = 1 },
    { k = "snapshot" },
    { k = "tap", btn = "F1", why = "FIRE1: HEAL, che cura il gruppo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 21, col = 1, want = "THE PARTY FEELS BETTER!", why = "l'esito e' scritto" },
    { k = "chk", why = "HEAL cura chi puo' essere curato", fn = function()
        report(chr16(0, O_CURHP) == chr16(0, O_MAXHP),
            string.format("il guerriero e' al massimo: %d/%d", chr16(0, O_CURHP), chr16(0, O_MAXHP)))
        report(chr16(WM, O_CURHP) == chr16(WM, O_MAXHP), "e anche chi lancia")
        -- I DUE CHE NON DEVONO ESSERE TOCCATI: MenuRecoverPartyHP salta chi e'
        -- fuori dal campo, ed e' la stessa regola della tenda.
        report(chr16(1, O_CURHP) == SNAP.hp1,
            string.format("il pietrificato NON e' curato: %d", chr16(1, O_CURHP)))
        report(chr16(3, O_CURHP) == 0,
            string.format("e il caduto nemmeno: %d", chr16(3, O_CURHP)))
        report(mp(2) == 8, string.format("una carica di L3 consumata: %d", mp(2)))
    end },

    -- ---------- PURE sull'avvelenato ----------
    { k = "tap", btn = "D", why = "giu': quarto livello" },
    { k = "tap", btn = "L", why = "sinistra: PURE" },
    { k = "cursor", why = "su PURE", lvl = 3, col = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: lancia PURE" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "2", why = "tastierino 2: il ladro" },
    { k = "tap", btn = "F1", why = "FIRE1: curalo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 21, col = 1, want = "THE POISON IS GONE", why = "l'esito e' scritto" },
    { k = "chk", why = "PURE toglie il veleno e SOLO quello", fn = function()
        report((chr(1, O_AIL) & AIL_POISON) == 0, string.format("veleno via: mal=$%02X", chr(1, O_AIL)))
        report((chr(1, O_AIL) & AIL_STONE) ~= 0, "e la pietra resta: e' un'altra magia")
        report(mp(3) == 8, string.format("una carica di L4 consumata: %d", mp(3)))
    end },

    -- ---------- CUR4 sul PIETRIFICATO: il fix ----------
    { k = "tap", btn = "D", why = "giu' (1/3): quinto livello" },
    { k = "tap", btn = "D", why = "giu' (2/3): sesto" },
    { k = "tap", btn = "D", why = "giu' (3/3): settimo, CUR4" },
    { k = "cursor", why = "su CUR4", lvl = 6, col = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: lancia CUR4" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "2", why = "tastierino 2: il pietrificato" },
    { k = "tap", btn = "F1", why = "FIRE1: prova a curarlo" },
    { k = "wait", n = 40, why = "la risposta compare" },
    { k = "text", row = 21, col = 1, want = "THAT ONE DOESN'T NEED IT", why = "il rifiuto" },
    { k = "chk", why = "CUR4 su un pietrificato: FIX #1", fn = function()
        -- Sul NES CUR4 non guarda le alterazioni: riempirebbe gli HP di un
        -- pietrificato, che resta pietrificato -- una carica di settimo livello
        -- spesa, e la schermata che mostra il numero salito.
        report(chr16(1, O_CURHP) == SNAP.hp1,
            string.format("gli HP non si sono mossi: %d", chr16(1, O_CURHP)))
        report(mp(6) == 9, string.format("e la carica di L7 e' intatta: %d", mp(6)))
    end },

    -- ---------- SOFT ----------
    { k = "tap", btn = "U", why = "su: sesto livello, SOFT" },
    { k = "cursor", why = "su SOFT", lvl = 5, col = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: lancia SOFT" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "2", why = "tastierino 2: il pietrificato" },
    { k = "tap", btn = "F1", why = "FIRE1: sciogli la pietra" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 21, col = 1, want = "THE STONE CRUMBLES", why = "l'esito e' scritto" },
    { k = "chk", why = "SOFT sul pietrificato", fn = function()
        report((chr(1, O_AIL) & AIL_STONE) == 0, string.format("pietra sciolta: mal=$%02X", chr(1, O_AIL)))
        report(mp(5) == 8, string.format("una carica di L6 consumata: %d", mp(5)))
    end },

    -- ---------- CUR4 sul vivo: l'altro ramo ----------
    { k = "tap", btn = "D", why = "giu': settimo livello, CUR4" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia CUR4" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "2", why = "tastierino 2: adesso e' vivo" },
    { k = "tap", btn = "F1", why = "FIRE1: curalo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "chk", why = "CUR4 su chi si puo' curare", fn = function()
        -- Senza questa prova il rifiuto di prima passerebbe per "CUR4 non
        -- funziona" invece che per "CUR4 rifiuta chi non deve curare".
        report(chr16(1, O_CURHP) == chr16(1, O_MAXHP),
            string.format("HP al massimo: %d/%d", chr16(1, O_CURHP), chr16(1, O_MAXHP)))
        report(mp(6) == 8, string.format("e ADESSO la carica si consuma: %d", mp(6)))
    end },

    -- ---------- LIFE sul caduto ----------
    { k = "tap", btn = "U", why = "su (1/2): sesto livello" },
    { k = "tap", btn = "U", why = "su (2/2): quinto, CUR3" },
    { k = "tap", btn = "R", why = "destra: LIFE" },
    { k = "cursor", why = "su LIFE", lvl = 4, col = 1 },
    { k = "tap", btn = "F1", why = "FIRE1: lancia LIFE" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "4", why = "tastierino 4: il mago nero, caduto" },
    { k = "tap", btn = "F1", why = "FIRE1: rialzalo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 21, col = 1, want = "BACK ON HIS FEET!", why = "l'esito e' scritto" },
    { k = "chk", why = "LIFE sul caduto", fn = function()
        report((chr(3, O_AIL) & AIL_DEAD) == 0, string.format("non e' piu' caduto: mal=$%02X", chr(3, O_AIL)))
        -- UN HP, non di piu': quella e' LIF2. La differenza fra le due magie e'
        -- tutta qui.
        report(chr16(3, O_CURHP) == 1, string.format("e torna con UN HP: %d", chr16(3, O_CURHP)))
        report(mp(4) == 8, string.format("una carica di L5 consumata: %d", mp(4)))
    end },
    { k = "shot", why = "MAGIC -- il gruppo rimesso in sesto" },

    -- ---------- LIF2 senza cariche ----------
    { k = "tap", btn = "D", why = "giu' (1/3)" },
    { k = "tap", btn = "D", why = "giu' (2/3)" },
    { k = "tap", btn = "D", why = "giu' (3/3): ottavo livello" },
    { k = "tap", btn = "L", why = "sinistra: LIF2" },
    { k = "cursor", why = "su LIF2", lvl = 7, col = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: lancia LIF2, senza cariche" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    -- NON "non ne ha bisogno": le cariche si guardano PRIMA, quindi la
    -- schermata dei bersagli non deve nemmeno aprirsi.
    { k = "text", row = 21, col = 1, want = "NOT ENOUGH MP", why = "il rifiuto giusto, e nell'ordine giusto" },

    -- ---------- EXIT in citta' ----------
    { k = "tap", btn = "U", why = "su (1/2): settimo livello" },
    { k = "tap", btn = "U", why = "su (2/2): sesto" },
    { k = "tap", btn = "R", why = "destra: EXIT" },
    { k = "cursor", why = "su EXIT", lvl = 5, col = 1 },
    { k = "chk", why = "prima di EXIT", fn = function()
        SNAP.mp5 = mp(5)
        SNAP.wx, SNAP.wy = b("world_player_mx"), b("world_player_my")
        report(true, string.format("cariche L6 = %d, overworld = (%d,%d)", SNAP.mp5, SNAP.wx, SNAP.wy))
    end },
    { k = "tap", btn = "F1", why = "FIRE1: lancia EXIT" },
    -- ATTESA CORTA, e non e' un dettaglio: il messaggio di EXIT vive novanta
    -- quadri e poi la schermata SPARISCE -- si esce dalla citta'. Con la solita
    -- attesa da 40 il controllo arrivava a corsa finita e leggeva una riga
    -- vuota, cioe' accusava il codice giusto per la terza volta in due
    -- sessioni. Un messaggio che precede una transizione va letto SUBITO.
    { k = "wait", n = 10, why = "il messaggio compare" },
    { k = "text", row = 21, col = 1, want = "THE PARTY IS PULLED AWAY", why = "l'esito e' scritto" },
    { k = "wait", n = 400, why = "il menu si chiude e l'overworld si ridisegna" },
    { k = "shot", why = "OVERWORLD -- EXIT ha portato via il gruppo" },
    { k = "chk", why = "EXIT in citta'", fn = function()
        report(mp(5) == SNAP.mp5 - 1, string.format("la carica si consuma: %d", mp(5)))
        -- Si torna alle coordinate da cui si era entrati: sono ancora in
        -- world_player_mx/my, che la citta' non tocca mai.
        report(b("world_player_mx") == SNAP.wx and b("world_player_my") == SNAP.wy,
            string.format("alle coordinate d'ingresso: (%d,%d)", b("world_player_mx"), b("world_player_my")))
        report(b("main_bank") == 0, string.format("banco mappato = %d", b("main_bank")))
    end },

    -- ---------- EXIT in OVERWORLD: fix #2, e la prova che siamo usciti ------
    { k = "tap", btn = "F2", why = "FIRE2: si apre il menu, stavolta fuori" },
    { k = "wait", n = 60, why = "il menu si disegna" },
    { k = "tap", btn = "2", why = "tastierino 2: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: chiede chi lancia" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: si apre la griglia" },
    { k = "wait", n = 120, why = "i nomi si ridisegnano" },
    { k = "tap", btn = "D", why = "giu' (1/5)" },
    { k = "tap", btn = "D", why = "giu' (2/5)" },
    { k = "tap", btn = "D", why = "giu' (3/5)" },
    { k = "tap", btn = "D", why = "giu' (4/5)" },
    { k = "tap", btn = "D", why = "giu' (5/5): sesto livello" },
    { k = "tap", btn = "R", why = "destra: EXIT" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia EXIT dall'overworld" },
    { k = "wait", n = 40, why = "la risposta compare" },
    -- QUESTO MESSAGGIO IN CITTA' NON COMPARE: e' anche la prova che il passo
    -- precedente e' arrivato davvero in overworld.
    { k = "text", row = 21, col = 1, want = "IT DOES NOTHING HERE", why = "EXIT fuori da un sotterraneo: FIX #2" },
    { k = "chk", why = "e non costa niente", fn = function()
        report(mp(5) == SNAP.mp5 - 1,
            string.format("la carica di L6 e' quella di prima: %d (il NES l'avrebbe spesa)", mp(5)))
    end },
    { k = "shot", why = "MAGIC -- EXIT in overworld non fa niente, e lo dice" },
    { k = "dump", why = "alla fine" },
    { k = "done" },
}

-- =====================================================================
--  esecuzione
-- =====================================================================
local pi, phase, timer = 1, "idle", 0
local SETTLE, TAP_PRESS, TAP_REST = 16, 12, 14

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); pi = pi + 1; return
    elseif a.k == "dump" then dump_party(a.why); pi = pi + 1; return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "snapshot" then
        SNAP.hp1 = chr16(1, O_CURHP)
        print(string.format("   [istantanea] HP2=%d", SNAP.hp1))
        pi = pi + 1; return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why)); a.fn(); pi = pi + 1; return
    elseif a.k == "cursor" then
        check_cursor(a.why, a.lvl, a.col); pi = pi + 1; return
    elseif a.k == "text" then
        check_text(a.why, a.row, a.col, a.want); pi = pi + 1; return
    elseif a.k == "screen" then
        dump_screen(a.why, a.r0 or 0, a.r1 or 23); pi = pi + 1; return
    end
    if a.k == "wait" then phase = "press"; timer = 0; return end
    if a.k == "tap" then
        print(string.format("f=%d  %s", frames, a.why)); phase = "press"; timer = 0; return
    end
end

local function next_action() pi = pi + 1; phase = "settle"; timer = 0 end

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
        if timer <= TAP_PRESS then press_any(a.btn, true)
        elseif timer <= TAP_PRESS + TAP_REST then press_any(a.btn, false)
        else release_everything(); next_action() end
        return
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

local TOWN_READY = t + 300
at(TOWN_READY, function()
    refresh_chr_size()
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d",
        u16(PARTY_BASE), PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE))
    if u16(PARTY_BASE) ~= PARTY_MAGIC then
        print("!! MAGIC DEL GRUPPO DIVERSO: i campi qui sotto non valgono")
    end
end)

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    -- SOLO FIRE1: da slice73 FIRE2 apre il menu, e una pulsazione cieca caduta
    -- nel ciclo della citta' lo aprirebbe e chiuderebbe decine di volte.
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
    elseif frames == 2200 then
        fire1(false)
    end
    local fn = SEQ[frames]
    if fn then fn() end
    if frames > TOWN_READY then frame_action() end
end)
