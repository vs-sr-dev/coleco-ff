-- mame_drive_menu.lua -- il menu: statistiche, zaino, uso degli oggetti.
-- (slice73)
--
-- PERCHE' QUESTA CORSA NON CAMMINA QUASI PER NIENTE
-- Tutte le altre partono dall'ingresso di Coneria e attraversano la citta' per
-- arrivare a una porta. Il menu invece si apre DOVE SI E', con FIRE2: la
-- prova puo' cominciare sul primo quadro utile. L'unico spostamento e' UN
-- PASSO A SUD -- il prato sotto l'ingresso e' TP_TELE_WARP e riporta in
-- overworld -- e serve a una cosa sola, ma essenziale: la tenda si usa solo
-- FUORI dalle citta', e senza uscire quel ramo non si esercita.
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_MENU (ROM col suffisso _t):
--   * classi FISSE FT/TH/WM/BM. La schermata delle statistiche si controlla
--     NUMERO PER NUMERO contro lut_ClassStartingStats, e con classi a caso
--     "INT vale 20" non si distingue da "INT vale 20 per chi non doveva";
--   * zaino pieno di roba dei tre tipi -- consumabili, oggetti chiave e una
--     SFERA, che non deve comparire in lista;
--   * un ferito, un avvelenato e un pietrificato, cioe' i tre bersagli delle
--     tre pozioni. Senza di loro ogni uso finirebbe nel ramo "non ne ha
--     bisogno", e la prova direbbe solo che i rifiuti funzionano;
--   * 20 EXP al guerriero, cosi' la riga NEXT mostra un numero CALCOLATO (40
--     meno 20) e non la soglia intera -- che sarebbe uguale a una riga che
--     stampa la tabella senza fare la sottrazione.
--
-- LE PROVE, e perche' quelle:
--   1. il menu si apre e si chiude con FIRE2. La chiusura e' una prova: il
--      tasto e' ancora premuto quando l'overlay esce, e senza il fronte il
--      menu si riaprirebbe subito -- a schermo, un menu che non si chiude
--   2. STATUS del MAGO NERO      -> i dieci numeri della tabella delle classi,
--      INT compreso. E' la statistica che da slice59 fa qualcosa e che fino a
--      oggi nessuna schermata diceva
--   3. STATUS del GUERRIERO      -> NEXT = 20, cioe' la sottrazione a 24 bit
--   4. lo zaino                  -> otto voci e non nove: la sfera si salta
--   5. HEAL sul ferito           -> 5 + 30 = 35, cioe' esattamente il massimo:
--      il taglio al massimo e la cura si provano nello stesso colpo
--   6. PURE sull'avvelenato      -> il bit del veleno si spegne
--   7. SOFT sul pietrificato     -> la pietra si scioglie E gli HP passano da
--      0 a 1: in FF1 non esiste un vivo a zero HP
--   8. HEAL su chi sta bene      -> rifiutato, e la pozione RESTA
--   9. la TENDA in citta'        -> rifiutata (in citta' c'e' la locanda)
--  10. la LIUTO                  -> "non serve a niente qui": gli oggetti
--      chiave si vedono e non si usano finche' non ci sono i luoghi
--  11. la TENDA in overworld     -> +30 HP a tutti, e il pietrificato NON
--      viene curato dal riposo
--
-- USO
--   .\tools\build_all.ps1 -Slice slice73 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23','ovl_menu:24' -Defines FORCE_MENU
--   & mame.exe coleco -exp sgm -cart build\slice73_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 500 `
--       -autoboot_script tools\mame_drive_menu.lua

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
        print("!! SONDA MANCANTE: " .. name .. " -- il campo sara' n/d")
    end
    return false
end
for _, n in ipairs({ "town_mx", "town_my", "main_bank", "party_chr_size",
                     "world_player_mx", "world_player_my" }) do has(n) end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

-- --- il gruppo in RAM SGM (party_state.h) ----------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local PARTY_N     = 4
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_CLS, O_AIL, O_NAME = 0, 1, 2
local O_CURHP, O_MAXHP     = 12, 14
local O_STR                = 16   -- str agil int vit luck
local O_DMG, O_HIT, O_ABSORB, O_EVADE, O_RESIST, O_MAGDEF = 21, 22, 23, 24, 25, 26
local O_LEVEL              = 27
local O_CURMP0, O_MAXMP0   = 28, 36

local function inv_base() return CHR0 + PARTY_N * CHR_SIZE end
local function inv(id)    return u8(inv_base() + id) end
local ITEM_LUTE, ITEM_CROWN, ITEM_ORB = 0x01, 0x02, 0x12
local ITEM_TENT, ITEM_CABIN, ITEM_HOUSE = 0x16, 0x17, 0x18
local ITEM_HEAL, ITEM_PURE, ITEM_SOFT   = 0x19, 0x1A, 0x1B
local AIL_POISON, AIL_STONE = 0x04, 0x02

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
        print(string.format("   %d %-6s %s lv%d HP %d/%d  mal=$%02X  STR %d AGL %d INT %d VIT %d LUK %d  dmg %d hit %d abs %d eva %d mdef %d",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??", chr(i, O_LEVEL),
            chr16(i, O_CURHP), chr16(i, O_MAXHP), chr(i, O_AIL),
            chr(i, O_STR), chr(i, O_STR+1), chr(i, O_STR+2), chr(i, O_STR+3), chr(i, O_STR+4),
            chr(i, O_DMG), chr(i, O_HIT), chr(i, O_ABSORB), chr(i, O_EVADE), chr(i, O_MAGDEF)))
    end
    local parts = {}
    for _, p in ipairs({ {ITEM_LUTE,"LUTE"}, {ITEM_CROWN,"CROWN"}, {ITEM_ORB,"ORB"},
                         {ITEM_TENT,"TENT"}, {ITEM_CABIN,"CABIN"}, {ITEM_HOUSE,"HOUSE"},
                         {ITEM_HEAL,"HEAL"}, {ITEM_PURE,"PURE"}, {ITEM_SOFT,"SOFT"} }) do
        parts[#parts + 1] = string.format("%s=%d", p[2], inv(p[1]))
    end
    print("   zaino: " .. table.concat(parts, " "))
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

local KEYPAD = {}
local function keypad_field(ch)
    if KEYPAD[ch] then return KEYPAD[ch] end
    local port = manager.machine.ioport.ports[":STD_KEYPAD1"]
    if not port then error("porta del tastierino non trovata") end
    -- I campi si chiamano "3 (pad 1)": la cifra sta in TESTA. Cercarla in coda
    -- non da' errore, da' tasti che non arrivano.
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
local function is_digit(btn) return btn:len() == 1 and btn >= "0" and btn <= "9" end
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
    return string.format("citta'=(%d,%d) ow=(%d,%d) banco=%d",
        b("town_mx"), b("town_my"), b("world_player_mx"), b("world_player_my"), b("main_bank"))
end
local function shot(label)
    print(string.format("SNAP (%s) @frame %d  %s", label, frames, pos()))
    manager.machine.video:snapshot()
end

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
local function check_text(why, row, col, want)
    local got = vram_text(row, col, #want)
    report(got == want, string.format("%s: riga %d col %d = '%s' (atteso '%s')", why, row, col, got, want))
end
local function check_cursor(why, col, row0, step, n, sel)
    local bad = {}
    for i = 0, n - 1 do
        local r = row0 + i * step
        local t = vram:read_u8(0x1800 + r * 32 + col)
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

-- Nessuna riga bianca in mezzo alla lista dello zaino: e' cosi' che si
-- vedrebbe una sfera elencata, e non lo direbbe nessun byte in RAM.
local function check_item_rows(why, want_names)
    local bad = {}
    for k = 1, #want_names do
        local got = vram_text(3 + k - 1, 2, #want_names[k])
        if got ~= want_names[k] then
            bad[#bad + 1] = string.format("riga %d: '%s' invece di '%s'", 3 + k - 1, got, want_names[k])
        end
    end
    -- e la riga DOPO l'ultima dev'essere vuota
    local after = vram_text(3 + #want_names, 0, 16)
    if after ~= string.rep(" ", 16) then
        bad[#bad + 1] = string.format("riga %d non vuota: '%s'", 3 + #want_names, after)
    end
    if #bad == 0 then
        report(true, string.format("%s: %d voci, nell'ordine giusto e senza righe bianche", why, #want_names))
    else
        report(false, string.format("%s: %s", why, table.concat(bad, ", ")))
    end
end

-- =====================================================================
--  il piano
-- =====================================================================
local SNAP = {}

local PLAN = {
    -- ---------- il menu si apre, in citta' ----------
    { k = "tap", btn = "F2", why = "FIRE2: si apre il menu" },
    { k = "wait", n = 60, why = "il menu si disegna" },
    { k = "screen", why = "menu principale", r0 = 0, r1 = 17 },
    { k = "shot", why = "MENU -- le cinque voci, il gruppo e l'oro" },
    { k = "text", row = 1,  col = 1,  want = "MENU",   why = "il titolo" },
    { k = "text", row = 3,  col = 4,  want = "ITEM",   why = "prima voce" },
    { k = "text", row = 11, col = 4,  want = "STATUS", why = "quinta voce" },
    { k = "text", row = 15, col = 1,  want = "GOLD",   why = "l'oro c'e'" },
    { k = "text", row = 15, col = 10, want = "400",    why = "e vale 400" },
    { k = "cursor", why = "appena aperto", col = 1, row0 = 3, step = 2, n = 5, sel = 0 },

    -- ---------- STATUS del mago nero: i dieci numeri ----------
    { k = "tap", btn = "5", why = "tastierino 5: dritti a STATUS" },
    { k = "cursor", why = "il tastierino ha scelto STATUS", col = 1, row0 = 3, step = 2, n = 5, sel = 4 },
    { k = "tap", btn = "F1", why = "FIRE1: apre la scelta del personaggio" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "cursor", why = "scelta del personaggio", col = 13, row0 = 3, step = 3, n = 4, sel = 0 },
    { k = "tap", btn = "4", why = "tastierino 4: il mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: mostra le sue statistiche" },
    { k = "wait", n = 40, why = "la schermata si disegna" },
    { k = "screen", why = "statistiche del mago nero", r0 = 1, r1 = 22 },
    { k = "shot", why = "STATUS -- il mago nero, INT 20" },
    { k = "text", row = 3,  col = 1,  want = "MORDRD",     why = "il nome" },
    { k = "text", row = 4,  col = 1,  want = "BLACK MAGE", why = "la classe per esteso" },
    { k = "text", row = 6,  col = 8,  want = "25",         why = "HP correnti" },
    { k = "text", row = 6,  col = 14, want = "25",         why = "HP massimi" },
    { k = "text", row = 7,  col = 13, want = "0",          why = "EXP a zero" },
    { k = "text", row = 8,  col = 12, want = "40",         why = "NEXT: i 40 della prima soglia" },
    -- I dieci numeri della tabella delle classi, riga per riga. Il mago nero e'
    -- il caso migliore perche' i suoi valori sono tutti diversi fra loro: uno
    -- scambio di campi -- l'errore naturale in una schermata a due colonne --
    -- non puo' passare inosservato.
    { k = "text", row = 10, col = 1,  want = "STR",    why = "etichetta STR" },
    { k = "text", row = 10, col = 9,  want = "1",      why = "STR del mago nero" },
    { k = "text", row = 11, col = 8,  want = "10",     why = "AGL" },
    { k = "text", row = 12, col = 1,  want = "INT",    why = "etichetta INT" },
    { k = "text", row = 12, col = 8,  want = "20",     why = "INT -- la statistica che da slice59 fa qualcosa" },
    { k = "text", row = 13, col = 9,  want = "1",      why = "VIT" },
    { k = "text", row = 14, col = 8,  want = "10",     why = "LUCK" },
    { k = "text", row = 10, col = 13, want = "DAMAGE", why = "etichetta del danno" },
    { k = "text", row = 10, col = 29, want = "1",      why = "danno" },
    { k = "text", row = 11, col = 29, want = "5",      why = "mira" },
    { k = "text", row = 12, col = 29, want = "0",      why = "assorbimento (nessuna armatura)" },
    { k = "text", row = 13, col = 28, want = "58",     why = "evasione" },
    { k = "text", row = 14, col = 28, want = "20",     why = "difesa magica" },
    { k = "text", row = 16, col = 4,  want = "1  2/2", why = "le due cariche di primo livello" },
    { k = "text", row = 16, col = 11, want = "2  0/0", why = "e niente al secondo" },
    { k = "tap", btn = "F2", why = "FIRE2: si torna al menu" },
    { k = "wait", n = 40, why = "il menu si ridisegna" },

    -- ---------- STATUS del guerriero: la sottrazione ----------
    { k = "tap", btn = "F1", why = "FIRE1: di nuovo STATUS" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "1", why = "tastierino 1: il guerriero" },
    { k = "tap", btn = "F1", why = "FIRE1: le sue statistiche" },
    { k = "wait", n = 40, why = "la schermata si disegna" },
    { k = "shot", why = "STATUS -- il guerriero, NEXT calcolato" },
    { k = "text", row = 4, col = 1,  want = "FIGHTER", why = "la classe" },
    { k = "text", row = 7, col = 12, want = "20",      why = "EXP seminati" },
    -- 20 e non 40: e' la SOTTRAZIONE a 24 bit. Una riga che stampasse la
    -- soglia della tabella direbbe 40 ed avrebbe l'aria di funzionare.
    { k = "text", row = 8, col = 12, want = "20",      why = "NEXT = 40 - 20, cioe' quanto MANCA" },
    { k = "text", row = 10, col = 8, want = "20",      why = "STR del guerriero" },
    { k = "text", row = 12, col = 9, want = "1",       why = "INT del guerriero: uno" },
    { k = "tap", btn = "F2", why = "FIRE2: si torna al menu" },
    { k = "wait", n = 40, why = "il menu si ridisegna" },

    -- ---------- lo zaino ----------
    { k = "tap", btn = "1", why = "tastierino 1: ITEM" },
    { k = "cursor", why = "il tastierino ha scelto ITEM", col = 1, row0 = 3, step = 2, n = 5, sel = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: si apre lo zaino" },
    { k = "wait", n = 60, why = "la lista si disegna (nove nomi dal banco 16)" },
    { k = "screen", why = "lo zaino", r0 = 1, r1 = 20 },
    { k = "shot", why = "ITEM -- otto voci, e la sfera non c'e'" },
    -- OTTO e non nove. La sfera e' nello zaino (FORCE_MENU la semina) ma il
    -- suo nome nel ROM e' sette spazi: elencarla darebbe una riga bianca.
    { k = "items", why = "la lista", names = { "LUTE", "CROWN", "TENT", "CABIN", "HOUSE", "HEAL", "PURE", "SOFT" } },
    { k = "chk", why = "la sfera c'e' davvero in RAM", fn = function()
        report(inv(ITEM_ORB) == 1,
            string.format("sfera in zaino = %d (attesa 1: il salto e' nella LISTA, non nei dati)", inv(ITEM_ORB)))
    end },

    -- ---------- HEAL sul ferito ----------
    { k = "snap", why = "prima di HEAL" },
    { k = "tap", btn = "D", why = "giu': CROWN" },
    { k = "tap", btn = "D", why = "giu': TENT" },
    { k = "tap", btn = "D", why = "giu': CABIN" },
    { k = "tap", btn = "D", why = "giu': HOUSE" },
    { k = "tap", btn = "D", why = "giu': HEAL" },
    { k = "cursor", why = "il cursore e' su HEAL", col = 0, row0 = 3, step = 1, n = 8, sel = 5 },
    { k = "tap", btn = "F1", why = "FIRE1: usa HEAL" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "cursor", why = "scelta del bersaglio", col = 0, row0 = 16, step = 1, n = 4, sel = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: al guerriero, che ha 5 HP" },
    { k = "wait", n = 40, why = "la lista si ridisegna" },
    { k = "chk", why = "HEAL sul ferito", fn = function()
        -- 5 + 30 = 35, ed e' esattamente il massimo del guerriero: la cura e
        -- il taglio al massimo si provano nello stesso colpo.
        report(chr16(0, O_CURHP) == 35, string.format("HP = %d (5 + 30, e 35 e' anche il massimo)", chr16(0, O_CURHP)))
        report(chr16(0, O_CURHP) == chr16(0, O_MAXHP), "non ha sfondato il massimo")
        report(inv(ITEM_HEAL) == 4, string.format("pozioni = %d (erano 5)", inv(ITEM_HEAL)))
    end },
    { k = "text", row = 3 + 5, col = 12, want = "4", why = "e la lista lo dice" },

    -- ---------- HEAL su chi sta bene: rifiutata ----------
    { k = "tap", btn = "F1", why = "FIRE1: usa HEAL di nuovo" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "1", why = "tastierino 1: di nuovo il guerriero, che ora e' pieno" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela lo stesso" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "chk", why = "HEAL su chi sta bene", fn = function()
        -- NON e' un rifiuto: sul NES la pozione si puo' sprecare su chi sta
        -- bene, e cura zero. Qui l'unica cosa che non deve succedere e' che
        -- gli HP sfondino il massimo -- e la pozione si consuma, com'e' giusto.
        report(chr16(0, O_CURHP) == chr16(0, O_MAXHP),
            string.format("gli HP restano al massimo: %d/%d", chr16(0, O_CURHP), chr16(0, O_MAXHP)))
    end },

    -- ---------- PURE sull'avvelenato ----------
    { k = "tap", btn = "D", why = "giu': PURE" },
    { k = "tap", btn = "F1", why = "FIRE1: usa PURE" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "2", why = "tastierino 2: il ladro, avvelenato" },
    { k = "tap", btn = "F1", why = "FIRE1: curalo" },
    { k = "wait", n = 40, why = "la lista si ridisegna" },
    { k = "chk", why = "PURE sull'avvelenato", fn = function()
        report((chr(1, O_AIL) & AIL_POISON) == 0,
            string.format("il veleno e' andato: mal=$%02X", chr(1, O_AIL)))
        report(inv(ITEM_PURE) == 2, string.format("antidoti = %d (erano 3)", inv(ITEM_PURE)))
    end },

    -- ---------- SOFT sul pietrificato ----------
    { k = "tap", btn = "D", why = "giu': SOFT" },
    { k = "tap", btn = "F1", why = "FIRE1: usa SOFT" },
    { k = "wait", n = 20, why = "compare la scelta del bersaglio" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco, pietrificato" },
    { k = "tap", btn = "F1", why = "FIRE1: sciogli la pietra" },
    { k = "wait", n = 40, why = "la lista si ridisegna" },
    { k = "chk", why = "SOFT sul pietrificato", fn = function()
        report((chr(2, O_AIL) & AIL_STONE) == 0,
            string.format("la pietra e' sciolta: mal=$%02X", chr(2, O_AIL)))
        -- UN HP, non zero: in FF1 un vivo a zero HP non esiste, ed e' la
        -- stessa regola con cui la clinica rialza i caduti.
        report(chr16(2, O_CURHP) == 1,
            string.format("torna in piedi con UN HP: %d (era 0)", chr16(2, O_CURHP)))
        report(inv(ITEM_SOFT) == 1, string.format("ammorbidenti = %d (erano 2)", inv(ITEM_SOFT)))
    end },
    { k = "shot", why = "ITEM -- tre pozioni usate, tre malanni in meno" },

    -- ---------- la tenda in citta': rifiutata ----------
    { k = "tap", btn = "U", why = "su: PURE" },
    { k = "tap", btn = "U", why = "su: HEAL" },
    { k = "tap", btn = "U", why = "su: HOUSE" },
    { k = "tap", btn = "U", why = "su: CABIN" },
    { k = "tap", btn = "U", why = "su: TENT" },
    { k = "cursor", why = "il cursore e' su TENT", col = 0, row0 = 3, step = 1, n = 8, sel = 2 },
    { k = "snap", why = "prima della tenda in citta'" },
    { k = "tap", btn = "F1", why = "FIRE1: pianta la tenda, ma siamo in citta'" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "text", row = 22, col = 1, want = "NOT INSIDE A TOWN", why = "il messaggio del rifiuto" },
    { k = "chk", why = "la tenda in citta'", fn = function()
        report(inv(ITEM_TENT) == 4, string.format("tende = %d: non se n'e' consumata nessuna", inv(ITEM_TENT)))
        report(chr16(1, O_CURHP) == SNAP.hp1, string.format("e nessuno si e' riposato: HP2 = %d", chr16(1, O_CURHP)))
    end },

    -- ---------- il liuto: un oggetto chiave ----------
    { k = "tap", btn = "U", why = "su: CROWN" },
    { k = "tap", btn = "U", why = "su: LUTE" },
    { k = "tap", btn = "F1", why = "FIRE1: prova a usare il liuto" },
    { k = "wait", n = 30, why = "la risposta compare" },
    { k = "text", row = 22, col = 1, want = "IT HAS NO USE HERE", why = "gli oggetti chiave si vedono e non si usano" },
    { k = "chk", why = "il liuto resta", fn = function()
        report(inv(ITEM_LUTE) == 1, string.format("liuto = %d", inv(ITEM_LUTE)))
    end },

    -- ---------- fuori dal menu, fuori dalla citta' ----------
    { k = "tap", btn = "F2", why = "FIRE2: si chiude lo zaino" },
    { k = "wait", n = 30, why = "torna il menu principale" },
    { k = "tap", btn = "F2", why = "FIRE2: si chiude il menu" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "shot", why = "CONERIA -- il menu si e' chiuso e non si e' riaperto" },
    { k = "chk", why = "il menu resta chiuso", fn = function()
        -- Se FIRE2 fosse letto a livello invece che a fronte, l'overlay
        -- sarebbe gia' rientrato: si vedrebbe dal banco mappato.
        report(b("main_bank") == 0,
            string.format("banco mappato = %d (atteso 0: siamo nel ciclo della citta')", b("main_bank")))
    end },
    { k = "exit", dir = "D", why = "un passo a sud: il prato riporta in overworld" },
    { k = "wait", n = 200, why = "enter_ow ridisegna" },

    -- ---------- la tenda in overworld: funziona ----------
    { k = "snap", why = "prima della tenda in overworld" },
    { k = "tap", btn = "F2", why = "FIRE2: si apre il menu, stavolta fuori" },
    { k = "wait", n = 60, why = "il menu si disegna" },
    { k = "shot", why = "MENU -- aperto dall'overworld" },
    { k = "tap", btn = "F1", why = "FIRE1: ITEM" },
    { k = "wait", n = 60, why = "la lista si disegna" },
    { k = "tap", btn = "D", why = "giu': CROWN" },
    { k = "tap", btn = "D", why = "giu': TENT" },
    { k = "tap", btn = "F1", why = "FIRE1: pianta la tenda" },
    { k = "wait", n = 40, why = "il gruppo si riposa" },
    { k = "text", row = 22, col = 1, want = "THE PARTY RESTS", why = "il messaggio del riposo" },
    { k = "chk", why = "la tenda in overworld", fn = function()
        report(inv(ITEM_TENT) == 3, string.format("tende = %d (erano 4)", inv(ITEM_TENT)))
        -- +30 a chi puo' riceverli, senza sfondare il massimo. Il mago bianco
        -- e' quello che si vede meglio: aveva 1 HP dopo SOFT.
        report(chr16(2, O_CURHP) == math.min(SNAP.hp2 + 30, chr16(2, O_MAXHP)),
            string.format("il mago bianco: %d -> %d (max %d)", SNAP.hp2, chr16(2, O_CURHP), chr16(2, O_MAXHP)))
        report(chr16(0, O_CURHP) == chr16(0, O_MAXHP),
            string.format("chi era gia' pieno resta pieno: %d/%d", chr16(0, O_CURHP), chr16(0, O_MAXHP)))
    end },
    { k = "shot", why = "ITEM -- la tenda funziona fuori dalle mura" },
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
local TAP_PRESS  = 12
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
        SNAP.hp1 = chr16(1, O_CURHP)
        SNAP.hp2 = chr16(2, O_CURHP)
        print(string.format("   [istantanea %s] HP2=%d HP3=%d", a.why, SNAP.hp1, SNAP.hp2))
        pi = pi + 1; return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn()
        pi = pi + 1; return
    elseif a.k == "cursor" then
        check_cursor(a.why, a.col, a.row0, a.step, a.n, a.sel)
        pi = pi + 1; return
    elseif a.k == "text" then
        check_text(a.why, a.row, a.col, a.want)
        pi = pi + 1; return
    elseif a.k == "items" then
        check_item_rows(a.why, a.names)
        pi = pi + 1; return
    elseif a.k == "screen" then
        dump_screen(a.why, a.r0 or 0, a.r1 or 23)
        pi = pi + 1; return
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
        -- Premuto e RILASCIATO: il menu legge FRONTI, come il negozio.
        if timer <= TAP_PRESS then press_any(a.btn, true)
        elseif timer <= TAP_PRESS + TAP_REST then press_any(a.btn, false)
        else release_everything(); next_action() end
        return
    end

    -- "exit": si tiene premuto finche' il banco della citta' molla, cioe'
    -- finche' town_mx smette di avere senso. Si riconosce dal fatto che la
    -- posizione in citta' non cambia PIU' e quella in overworld si': qui basta
    -- tenere premuto per un tempo fisso, perche' e' l'ULTIMO passo del piano
    -- che riguardi la citta'.
    if a.k == "exit" then
        if timer <= 20 then dpad(DPAD[a.dir], true)
        else release_all(); next_action() end
        return
    end

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
