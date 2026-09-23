-- mame_drive_equip.lua -- WEAPON / ARMOR: l'equipaggiamento manuale.
-- (slice74)
--
-- PERCHE' QUESTA CORSA NON CAMMINA
-- Come quella del menu: la schermata si apre con FIRE2 dove si e', quindi la
-- prova comincia sul primo quadro utile dentro Coneria. Non c'e' nemmeno il
-- passo verso l'overworld -- qui non ci sono rami che dipendano dal luogo.
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_EQMENU (ROM col suffisso _t):
--   * classi FISSE FT/BB/WM/BM, scelte per i PERMESSI. Il guerriero porta
--     quasi tutto, il monaco quasi niente ma le nunchucks si', i due maghi
--     hanno divieti diversi. Con classi a caso "rifiutato" non si distingue
--     da "rifiutato a chi poteva";
--   * uno zaino di ferraglia seminato a mano (party_new_game): un'arma
--     indossata, una vietata, una permessa che deve SCALZARE la prima; e fra
--     le armature una corazza indossata, un'altra corazza (stesso posto: la
--     scalza) e uno scudo (posto diverso: convive).
--
-- LE PROVE, e perche' quelle:
--   1. la griglia si apre e mostra TUTTE E SEDICI le caselle -- e' il NES
--      (CopyEquipToItemBox copia le sedici, `cursor` = personaggio*4+casella),
--      ed e' l'unica forma in cui lo scambio si vede mentre si fa
--   2. l'ASTERISCO sta su cio' che si indossa, e solo li'
--   3. l'ICONA di tipo c'e'. Non e' un ornamento: fra le armature "Iron" sono
--      tre voci diverse. Fino a slice74 il menu non ne mostrava NESSUNA --
--      cercava l'icona dentro il nome, dove nel ROM sta e nei nostri dati no
--   4. EQUIP su un'arma vietata     -> rifiutata, e il byte in RAM non cambia
--   5. EQUIP su un'arma permessa    -> indossata, e la PRIMA si spegne: un'arma
--      sola addosso, sempre
--   6. EQUIP su cio' che si indossa -> si toglie (sul NES non passa nemmeno da
--      IsEquipLegal: togliersi qualcosa e' sempre lecito)
--   7. TRADE fra due personaggi     -> le due caselle si scambiano ed escono
--      ENTRAMBE spente: il permesso del nuovo proprietario non l'ha chiesto
--      nessuno
--   8. EQUIP dopo il TRADE          -> il mago nero non puo' il martello: la
--      prova che il permesso si richiede sul nuovo padrone
--   9. DROP annullato con FIRE2     -> l'oggetto resta
--  10. DROP confermato              -> sparisce
--  11. ARMOR: scudo e corazza convivono, due corazze no
--  12. all'uscita le caselle si COMPATTANO (eq_sort), che e' il presupposto
--      del negozio: la merce va nella prima casella libera
--
-- USO
--   .\tools\build_all.ps1 -Slice slice74 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23','ovl_menu:24' -Defines FORCE_EQMENU
--   & mame.exe coleco -exp sgm -cart build\slice74_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 500 `
--       -autoboot_script tools\mame_drive_equip.lua

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
for _, n in ipairs({ "town_mx", "town_my", "main_bank", "party_chr_size" }) do has(n) end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

-- --- il gruppo in RAM SGM (party_state.h) ----------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local PARTY_N     = 4
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_CLS, O_AIL, O_NAME = 0, 1, 2
local O_CURHP, O_MAXHP     = 12, 14
local O_DMG, O_HIT, O_ABSORB, O_EVADE = 21, 22, 23, 24
local O_LEVEL              = 27
-- Le caselle di equipaggiamento stanno IN CODA alla voce (slice65), dopo le
-- tre basi: 44 dmg_b, 45 hitrate_b, 46 evade_b, poi quattro armi e quattro
-- armature. Il passo lo pubblica il gioco (party_chr_size), gli offset dentro
-- la voce no -- e sono l'unica cosa cablata qui dentro.
local O_WEAPON, O_ARMOR    = 47, 51

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
local function wpn(i, k) return chr(i, O_WEAPON + k) end
local function arm(i, k) return chr(i, O_ARMOR + k) end
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
local function slots_str(i)
    local w, a = {}, {}
    for k = 0, 3 do
        w[#w + 1] = string.format("%02X", wpn(i, k))
        a[#a + 1] = string.format("%02X", arm(i, k))
    end
    return table.concat(w, " ") .. " | " .. table.concat(a, " ")
end
local function dump_party(why)
    print(string.format("-- %s", why))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s %s lv%d HP %d/%d  dmg %d hit %d abs %d eva %d   armi/armature: %s",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??", chr(i, O_LEVEL),
            chr16(i, O_CURHP), chr16(i, O_MAXHP),
            chr(i, O_DMG), chr(i, O_HIT), chr(i, O_ABSORB), chr(i, O_EVADE),
            slots_str(i)))
    end
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
local function shot(label)
    print(string.format("SNAP (%s) @frame %d", label, frames))
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
local function dump_screen(why, r0, r1)
    print(string.format("   [VRAM %s]", why))
    for r = r0, r1 do print(string.format("     %2d |%s|", r, vram_row(r))) end
end

-- --- la griglia dell'equipaggiamento ---------------------------------------
-- La cella di `sel` = personaggio*4 + casella, con la stessa formula
-- dell'overlay (eq_cell): due colonne per riga, i blocchi ogni quattro righe.
local ROW_EQ0, ROW_EQ_STEP = 5, 4
local function eq_cell(sel)
    local k = sel % 4
    local col = (k % 2) * 16
    local row = ROW_EQ0 + math.floor(sel / 4) * ROW_EQ_STEP + 1 + math.floor(k / 2)
    return col, row
end
-- Il cursore '>' su una casella sola, e il '<' della sorgente del TRADE dove
-- lo si aspetta. E' la regola di slice66: una posizione a schermo che vale
-- come prova si ASSERISCE, non si fotografa.
local function check_eq_cursor(why, sel, src)
    local bad = {}
    for s = 0, PARTY_N * 4 - 1 do
        local col, row = eq_cell(s)
        local t = vram:read_u8(0x1800 + row * 32 + col)
        local want = 0x20
        if s == src then want = 0x3C end
        if s == sel then want = 0x3E end
        if t ~= want then
            bad[#bad + 1] = string.format("casella %d (r%d c%d): $%02X invece di $%02X", s, row, col, t, want)
        end
    end
    if #bad == 0 then
        report(true, string.format("%s: cursore sulla casella %d%s", why, sel,
            src and (", presa la %d"):format(src) or ""))
    else
        report(false, string.format("%s: %s", why, table.concat(bad, ", ")))
    end
end
-- Nome, asterisco e ICONA di una cella. `star` = true se dev'essere indossata,
-- `icon` = true se ci si aspetta una tile di icona (le tile delle icone stanno
-- a $10-$1B, cioe' sotto lo spazio: si riconoscono da quello).
local function check_eq_slot(why, sel, star, name, icon)
    local col, row = eq_cell(sel)
    local bad = {}
    local st = vram:read_u8(0x1800 + row * 32 + col + 1)
    local want_st = star and 0x2A or 0x20
    if st ~= want_st then
        bad[#bad + 1] = string.format("asterisco: $%02X invece di $%02X", st, want_st)
    end
    if icon ~= nil then
        local ic = vram:read_u8(0x1800 + row * 32 + col + 2)
        local is_icon = (ic >= 0x10 and ic < 0x1C)
        if is_icon ~= icon then
            bad[#bad + 1] = string.format("icona: tile $%02X (attesa %s)", ic, icon and "un'icona" or "nessuna")
        end
    end
    local got = vram_text(row, col + 3, #name)
    if got ~= name then
        bad[#bad + 1] = string.format("nome '%s' invece di '%s'", got, name)
    end
    if #bad == 0 then
        report(true, string.format("%s: casella %d = %s%s", why, sel, star and "*" or "", name))
    else
        report(false, string.format("%s (casella %d): %s", why, sel, table.concat(bad, ", ")))
    end
end

-- =====================================================================
--  il piano
-- =====================================================================
local SNAP = {}
local EQ = 0x80   -- bit 7 = indossato

local PLAN = {
    -- ---------- si apre WEAPON ----------
    { k = "dump", why = "CONERIA -- ingresso, con lo zaino seminato" },
    { k = "chk", why = "il seme e' quello atteso", fn = function()
        report(wpn(0,0) == (EQ|4) and wpn(0,1) == 1 and wpn(0,2) == 5,
            string.format("guerriero: %s", slots_str(0)))
        report(wpn(1,0) == 1 and wpn(1,1) == 4, string.format("monaco: %s", slots_str(1)))
        report(arm(0,0) == (EQ|1) and arm(0,1) == 4 and arm(0,2) == 19,
            string.format("armature del guerriero: %s", slots_str(0)))
    end },
    { k = "tap", btn = "F2", why = "FIRE2: si apre il menu" },
    { k = "wait", n = 60, why = "il menu si disegna" },
    { k = "text", row = 7, col = 4, want = "WEAPON", why = "la terza voce non dice piu' NOT YET" },
    { k = "tap", btn = "3", why = "tastierino 3: WEAPON" },
    { k = "tap", btn = "F1", why = "FIRE1: si apre la griglia" },
    { k = "wait", n = 90, why = "sedici nomi dal banco 11" },
    { k = "screen", why = "la griglia delle armi", r0 = 1, r1 = 21 },
    { k = "shot", why = "WEAPON -- sedici caselle, i tre modi, l'asterizzato in mano" },
    { k = "text", row = 1,  col = 1,  want = "WEAPON", why = "il titolo" },
    { k = "text", row = 3,  col = 2,  want = "EQUIP",  why = "primo modo" },
    { k = "text", row = 3,  col = 12, want = "TRADE",  why = "secondo modo" },
    { k = "text", row = 3,  col = 22, want = "DROP",   why = "terzo modo" },
    { k = "text", row = 3,  col = 1,  want = ">",      why = "il cursore di modo parte su EQUIP" },
    { k = "text", row = 5,  col = 2,  want = "ARTHUR", why = "il primo blocco e' il guerriero" },
    { k = "text", row = 5,  col = 10, want = "FT",     why = "con la sua sigla di classe" },
    { k = "text", row = 17, col = 2,  want = "MORDRD", why = "e il quarto il mago nero" },
    -- L'asterisco e l'icona: la casella 0 del guerriero e' il Rapier, in mano.
    --
    -- IL RAPIER NON HA ICONA, ed e' giusto cosi': nel ROM l'icona di tipo
    -- occupa il 7o carattere del nome, quindi ce l'hanno solo i nomi che senza
    -- di essa sarebbero ambigui. "Rapier" riempie tutte e sei le lettere e non
    -- si confonde con niente; "Wooden" e "Iron" invece sono mezzo nome, e
    -- l'icona dice se sono nunchaku o martello. Verificato in
    -- src/data/item_names.h, tabella ff1_item_icon: $1F = 0, $1C/$1E != 0.
    -- La prima stesura di questa corsa chiedeva l'icona su TUTTE le voci ed e'
    -- fallita sul codice giusto -- di nuovo un controllo piu' preciso del vero.
    { k = "slot", why = "il Rapier in mano", sel = 0, star = true, name = "Rapier", icon = false },
    { k = "slot", why = "le nunchucks nello zaino", sel = 1, star = false, name = "Wooden", icon = true },
    { k = "slot", why = "il martello nello zaino", sel = 2, star = false, name = "Iron", icon = true },
    { k = "cursor", why = "appena aperta", sel = 0 },

    -- ---------- EQUIP su un'arma VIETATA ----------
    { k = "tap", btn = "R", why = "destra: le nunchucks, che un guerriero non puo'" },
    { k = "cursor", why = "il cursore si e' spostato di lato", sel = 1 },
    { k = "snapshot" },
    { k = "tap", btn = "F1", why = "FIRE1: prova a impugnarle" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "text", row = 22, col = 1, want = "THAT CLASS CANNOT USE IT", why = "il divieto e' scritto" },
    { k = "chk", why = "il divieto e' anche in RAM", fn = function()
        report(wpn(0,1) == 1, string.format("le nunchucks restano nello zaino: $%02X", wpn(0,1)))
        report(wpn(0,0) == (EQ|4), string.format("e il Rapier resta in mano: $%02X", wpn(0,0)))
        report(chr(0, O_DMG) == SNAP.dmg0 and chr(0, O_HIT) == SNAP.hit0,
            string.format("le sotto-statistiche non si sono mosse: dmg %d mira %d",
                chr(0, O_DMG), chr(0, O_HIT)))
    end },

    -- ---------- EQUIP su un'arma PERMESSA: scalza la prima ----------
    { k = "tap", btn = "D", why = "giu': la casella vuota" },
    { k = "tap", btn = "L", why = "sinistra: il martello" },
    { k = "cursor", why = "il cursore e' sul martello", sel = 2 },
    { k = "tap", btn = "F1", why = "FIRE1: impugna il martello" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 22, col = 1, want = "NOW EQUIPPED", why = "l'esito e' scritto" },
    { k = "chk", why = "un'arma sola addosso", fn = function()
        report(wpn(0,2) == (EQ|5), string.format("il martello e' in mano: $%02X", wpn(0,2)))
        -- LA PROVA CHE CONTA: il Rapier si e' spento da solo. Se restasse
        -- acceso, equip_recalc sommerebbe i bonus di DUE armi.
        report(wpn(0,0) == 4, string.format("e il Rapier si e' spento: $%02X (era $%02X)", wpn(0,0), EQ|4))
        -- SI GUARDA LA MIRA, NON IL DANNO, e la ragione e' nei dati: Rapier e
        -- IronHammer danno **lo stesso** +9 di danno (lut_WeaponData $03 e $04),
        -- quindi il danno resta 19 tanto se lo scambio e' avvenuto quanto se
        -- non fosse successo niente. La mira invece passa da 10+5 a 10+0, e
        -- quella e' una differenza che solo lo scambio puo' produrre.
        report(chr(0, O_DMG) == 19 and chr(0, O_HIT) == 10,
            string.format("dmg %d (uguale: le due armi danno +9 entrambe) e mira %d (era %d: il +5 del Rapier e' andato)",
                chr(0, O_DMG), chr(0, O_HIT), SNAP.hit0))
    end },
    { k = "slot", why = "l'asterisco si e' spostato", sel = 2, star = true, name = "Iron", icon = true },
    { k = "slot", why = "e il Rapier non ce l'ha piu'", sel = 0, star = false, name = "Rapier", icon = false },
    { k = "shot", why = "WEAPON -- il martello scalza lo stocco" },

    -- ---------- EQUIP di nuovo: si toglie ----------
    { k = "tap", btn = "F1", why = "FIRE1 di nuovo: riponilo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 22, col = 1, want = "PUT AWAY", why = "l'esito e' scritto" },
    { k = "chk", why = "togliersi qualcosa e' sempre lecito", fn = function()
        report(wpn(0,2) == 5, string.format("il martello e' nello zaino: $%02X", wpn(0,2)))
        -- 10 e 10, cioe' le BASE: adesso il guerriero e' a mani nude davvero,
        -- perche' il Rapier lo aveva gia' spento l'equipaggiamento del martello.
        -- Non 19: quello era il valore CON un'arma addosso.
        report(chr(0, O_DMG) == 10 and chr(0, O_HIT) == 10,
            string.format("e le sotto-statistiche sono tornate alle basi: dmg %d mira %d",
                chr(0, O_DMG), chr(0, O_HIT)))
    end },

    -- ---------- TRADE fra guerriero e mago nero ----------
    { k = "tap", btn = "2", why = "tastierino 2: modo TRADE" },
    { k = "text", row = 3, col = 11, want = ">", why = "il cursore di modo si e' spostato" },
    { k = "tap", btn = "F1", why = "FIRE1: prende il martello" },
    { k = "wait", n = 20, why = "compare il secondo cursore" },
    { k = "text", row = 22, col = 1, want = "NOW PICK THE OTHER SLOT", why = "chiede la seconda casella" },
    { k = "cursor", why = "la casella presa e' marcata", sel = 2, src = 2 },
    { k = "tap", btn = "D", why = "giu' verso il mago nero (1/5)" },
    { k = "tap", btn = "D", why = "giu' (2/5)" },
    { k = "tap", btn = "D", why = "giu' (3/5)" },
    { k = "tap", btn = "D", why = "giu' (4/5)" },
    { k = "tap", btn = "D", why = "giu' (5/5): mago nero, prima casella" },
    { k = "tap", btn = "R", why = "destra: la sua casella vuota" },
    { k = "cursor", why = "arrivati dall'altra parte", sel = 13, src = 2 },
    { k = "tap", btn = "F1", why = "FIRE1: scambia" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 22, col = 1, want = "SWAPPED", why = "l'esito e' scritto" },
    { k = "chk", why = "il martello ha cambiato mano", fn = function()
        report(wpn(0,2) == 0, string.format("il guerriero non ce l'ha piu': $%02X", wpn(0,2)))
        report(wpn(3,1) == 5, string.format("il mago nero ce l'ha, e SPENTO: $%02X", wpn(3,1)))
    end },
    { k = "slot", why = "e si vede", sel = 13, star = false, name = "Iron", icon = true },
    { k = "shot", why = "WEAPON -- il martello e' passato al mago nero" },

    -- ---------- EQUIP dopo il TRADE: il permesso si richiede ----------
    { k = "tap", btn = "1", why = "tastierino 1: modo EQUIP" },
    { k = "tap", btn = "F1", why = "FIRE1: che il mago nero lo impugni" },
    { k = "wait", n = 30, why = "il rifiuto compare" },
    { k = "text", row = 22, col = 1, want = "THAT CLASS CANNOT USE IT", why = "un mago nero non porta martelli" },
    { k = "chk", why = "il permesso vale sul NUOVO padrone", fn = function()
        report(wpn(3,1) == 5, string.format("resta nello zaino: $%02X", wpn(3,1)))
    end },

    -- ---------- DROP: prima annullato, poi confermato ----------
    { k = "tap", btn = "3", why = "tastierino 3: modo DROP" },
    { k = "tap", btn = "L", why = "sinistra: il coltellino del mago nero" },
    { k = "cursor", why = "sul coltellino", sel = 12 },
    { k = "tap", btn = "F1", why = "FIRE1: chiede conferma" },
    { k = "wait", n = 20, why = "la domanda compare" },
    { k = "text", row = 22, col = 1, want = "THROW IT AWAY?", why = "la domanda" },
    { k = "tap", btn = "F2", why = "FIRE2: ripensiamoci" },
    { k = "wait", n = 30, why = "torna la griglia" },
    { k = "chk", why = "il DROP annullato non butta niente", fn = function()
        report(wpn(3,0) == 2, string.format("il coltellino c'e' ancora: $%02X", wpn(3,0)))
    end },
    { k = "tap", btn = "R", why = "destra: il martello" },
    { k = "tap", btn = "F1", why = "FIRE1: chiede conferma" },
    { k = "wait", n = 20, why = "la domanda compare" },
    { k = "tap", btn = "F1", why = "FIRE1: buttalo davvero" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "text", row = 22, col = 1, want = "GONE FOR GOOD", why = "l'esito e' scritto" },
    { k = "chk", why = "il DROP confermato butta", fn = function()
        report(wpn(3,1) == 0, string.format("il martello non c'e' piu': $%02X", wpn(3,1)))
    end },

    -- ---------- fuori, e poi ARMOR ----------
    { k = "tap", btn = "F2", why = "FIRE2: si torna al menu" },
    { k = "wait", n = 40, why = "il menu si ridisegna" },
    { k = "tap", btn = "4", why = "tastierino 4: ARMOR" },
    { k = "tap", btn = "F1", why = "FIRE1: si apre la griglia delle armature" },
    { k = "wait", n = 90, why = "sedici nomi dal banco 11" },
    { k = "screen", why = "la griglia delle armature", r0 = 1, r1 = 21 },
    { k = "shot", why = "ARMOR -- la stessa schermata, l'altra meta' delle caselle" },
    { k = "text", row = 1, col = 1, want = "ARMOR", why = "il titolo" },
    -- Anche "Cloth" e' un nome che basta a se stesso: nessuna icona, come il
    -- Rapier. Le due "Iron" e la "Silver" ce l'hanno, e sono proprio quelle che
    -- senza si leggerebbero uguali.
    { k = "slot", why = "la casacca addosso", sel = 0, star = true, name = "Cloth", icon = false },
    { k = "slot", why = "la corazza di ferro nello zaino", sel = 1, star = false, name = "Iron", icon = true },
    -- Silver e non Wooden: l'indice 18 della tabella delle armature e' lo scudo
    -- d'argento. I nomi nei commenti del file generato sono spostati -- quello
    -- che conta e' item_names.h, che e' anche quello che legge il gioco.
    { k = "slot", why = "e lo scudo", sel = 2, star = false, name = "Silver", icon = true },
    { k = "snapshot" },

    -- lo scudo CONVIVE con la casacca: posti diversi
    { k = "tap", btn = "D", why = "giu': lo scudo" },
    { k = "tap", btn = "F1", why = "FIRE1: imbraccialo" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "chk", why = "posti diversi, convivono", fn = function()
        report(arm(0,2) == (EQ|19), string.format("lo scudo e' imbracciato: $%02X", arm(0,2)))
        report(arm(0,0) == (EQ|1), string.format("e la casacca resta addosso: $%02X", arm(0,0)))
        report(chr(0, O_ABSORB) > SNAP.abs0,
            string.format("l'assorbimento e' salito: %d -> %d", SNAP.abs0, chr(0, O_ABSORB)))
    end },
    { k = "slot", why = "due asterischi", sel = 2, star = true, name = "Silver", icon = true },
    { k = "slot", why = "e il primo c'e' ancora", sel = 0, star = true, name = "Cloth", icon = false },

    -- la corazza di ferro SCALZA la casacca: stesso posto
    { k = "tap", btn = "U", why = "su: la casacca" },
    { k = "tap", btn = "R", why = "destra: la corazza di ferro" },
    { k = "cursor", why = "sulla corazza", sel = 1 },
    { k = "tap", btn = "F1", why = "FIRE1: indossala" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "chk", why = "stesso posto, una sola", fn = function()
        report(arm(0,1) == (EQ|4), string.format("la corazza e' addosso: $%02X", arm(0,1)))
        report(arm(0,0) == 1, string.format("la casacca si e' tolta da sola: $%02X", arm(0,0)))
        report(arm(0,2) == (EQ|19), string.format("e lo scudo NON si e' tolto: $%02X", arm(0,2)))
    end },
    { k = "shot", why = "ARMOR -- corazza e scudo insieme, la casacca via" },

    -- ---------- il buco, e la compattazione all'uscita ----------
    { k = "tap", btn = "3", why = "tastierino 3: modo DROP" },
    { k = "tap", btn = "L", why = "sinistra: la casacca" },
    { k = "tap", btn = "F1", why = "FIRE1: chiede conferma" },
    { k = "wait", n = 20, why = "la domanda compare" },
    { k = "tap", btn = "F1", why = "FIRE1: buttala" },
    { k = "wait", n = 40, why = "la griglia si ridisegna" },
    { k = "chk", why = "resta un buco in mezzo", fn = function()
        report(arm(0,0) == 0 and arm(0,1) == (EQ|4) and arm(0,2) == (EQ|19),
            string.format("caselle: %s", slots_str(0)))
    end },
    { k = "tap", btn = "F2", why = "FIRE2: esce, e qui si compatta" },
    { k = "wait", n = 60, why = "torna il menu principale" },
    { k = "chk", why = "all'uscita le caselle si compattano", fn = function()
        -- E' il presupposto del negozio: la merce va nella PRIMA casella
        -- libera, e con un buco davanti un acquisto ci finirebbe dentro
        -- lasciando la lista sparsa.
        report(arm(0,0) == (EQ|4), string.format("la prima casella e' la corazza: $%02X", arm(0,0)))
        report(arm(0,1) == (EQ|19), string.format("la seconda lo scudo: $%02X", arm(0,1)))
        report(arm(0,2) == 0 and arm(0,3) == 0, "e le altre due sono vuote")
    end },
    { k = "tap", btn = "F2", why = "FIRE2: si chiude il menu" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "chk", why = "il menu resta chiuso", fn = function()
        report(b("main_bank") == 0,
            string.format("banco mappato = %d (atteso 0: siamo nel ciclo della citta')", b("main_bank")))
    end },
    { k = "shot", why = "CONERIA -- si e' tornati al gioco" },
    { k = "dump", why = "alla fine" },
    { k = "done" },
}

-- =====================================================================
--  esecuzione
-- =====================================================================
local pi = 1
local phase = "idle"
local timer = 0

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
    elseif a.k == "snapshot" then
        SNAP.dmg0 = chr(0, O_DMG)
        SNAP.hit0 = chr(0, O_HIT)
        SNAP.abs0 = chr(0, O_ABSORB)
        print(string.format("   [istantanea] dmg1=%d mira1=%d abs1=%d", SNAP.dmg0, SNAP.hit0, SNAP.abs0))
        pi = pi + 1; return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn()
        pi = pi + 1; return
    elseif a.k == "cursor" then
        check_eq_cursor(a.why, a.sel, a.src)
        pi = pi + 1; return
    elseif a.k == "slot" then
        check_eq_slot(a.why, a.sel, a.star, a.name, a.icon)
        pi = pi + 1; return
    elseif a.k == "text" then
        check_text(a.why, a.row, a.col, a.want)
        pi = pi + 1; return
    elseif a.k == "screen" then
        dump_screen(a.why, a.r0 or 0, a.r1 or 23)
        pi = pi + 1; return
    end
    if a.k == "wait" then phase = "press"; timer = 0; return end
    if a.k == "tap" then
        print(string.format("f=%d  %s", frames, a.why))
        phase = "press"; timer = 0; return
    end
end

local function next_action()
    pi = pi + 1; phase = "settle"; timer = 0
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
        -- Premuto e RILASCIATO: il menu legge FRONTI.
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
        print("!! MAGIC DEL GRUPPO DIVERSO: il layout e' cambiato, i campi qui sotto non valgono")
    end
end)

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    -- SOLO FIRE1: da slice73 FIRE2 apre il menu, e una pulsazione cieca caduta
    -- nel ciclo della citta' aprirebbe e chiuderebbe il menu decine di volte.
    if frames >= 700 and frames < 2200 then
        local on = (frames % 16) < 5
        fire1(on)
    elseif frames == 2200 then
        fire1(false)
    end
    local fn = SEQ[frames]
    if fn then fn() end
    if frames > TOWN_READY then frame_action() end
end)
