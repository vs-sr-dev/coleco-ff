-- mame_drive_shop.lua -- si compra davvero: permessi, caselle, oro, locanda,
-- clinica.  (slice66)
--
-- PERCHE' NON BASTAVA mame_drive_town.lua
-- Quello script arriva alla porta e scatta una foto del listino: dimostra che
-- i DATI arrivano a schermo. Qui il soggetto e' cio' che l'acquisto CAMBIA, e
-- non sta a schermo se non come tre cifre: oro, danno, assorbimento. Si legge
-- la RAM SGM del gruppo, come per la battaglia.
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_SHOP (ROM col suffisso _t):
--   * le classi sono fisse -- FT, BB, WM, BM. I permessi si provano solo con
--     classi NOTE: la selezione dei personaggi la guidano pressioni cieche, e
--     con un gruppo diverso a ogni corsa "lo stocco e' stato negato" non si
--     distingue da "lo stocco e' stato negato a chi poteva portarlo";
--   * il gruppo e' malconcio (un ferito, un caduto, zero cariche di magia),
--     perche' locanda e clinica su un gruppo intero non hanno niente da fare.
--
-- LE PROVE, e perche' quelle:
--   1. bastone al GUERRIERO  -> casella con bit 7 acceso, danno +6, -5 GP
--   2. stocco al MAGO BIANCO -> permesso NEGATO: la casella si riempie ma il
--      bit 7 resta spento e il danno NON cambia. E' la prova che i permessi
--      contano, ed e' l'unica in cui l'oro scende senza che niente migliori
--   3. nunchaku al MONACO    -> permesso concesso, e il danno NON e'
--      base+arma ma forza/2+arma: la regola speciale di ReadjustBBEquipStats,
--      che qui viene esercitata per la prima volta da un acquisto vero
--   4. locanda                -> -30 GP, il ferito torna pieno, il CADUTO NO
--   5. clinica                -> -40 GP, il caduto si rialza con UN HP
--
-- I CAMMINI NON SONO SCRITTI A MANO. Li calcola tools/plan_town_route.ps1
-- sugli stessi byte che legge il gioco: una rotta indovinata finisce dentro un
-- muro, e nel log un passo bloccato per rotta sbagliata e un passo bloccato
-- per collisione rotta si scrivono nello stesso modo.
--
-- USO
--   .\tools\build_all.ps1 -Slice slice66 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22' -Defines FORCE_SHOP
--   & mame.exe coleco -exp sgm -cart build\slice66_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 400 `
--       -autoboot_script tools\mame_drive_shop.lua

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
                     "party_chr_size", "world_player_mx", "world_player_my" }) do has(n) end
local function b(n) if has(n) then return u8(probe[n]) else return -1 end end

-- --- il gruppo in RAM SGM (party_state.h) ----------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6          -- magic(2) n(1) gp(3)
local O_CLS, O_AIL, O_NAME      = 0, 1, 2
local O_CURHP, O_MAXHP          = 12, 14
local O_STR                     = 16
local O_DMG, O_HIT, O_ABSORB    = 21, 22, 23
local O_LEVEL                   = 27
local O_CURMP0, O_MAXMP0        = 28, 36
local O_DMG_B                   = 44
local O_WEAPON, O_ARMOR         = 47, 51

-- Il passo si LEGGE dal gioco (party_chr_size): e' la trappola numero 1 del
-- catalogo, gia' costata una corsa intera quando la voce e' passata da 44 a 79.
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
local function dump_party(why)
    print(string.format("-- %s   oro=%d", why, gold()))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s %s lv%d HP %d/%d  dmg %d (base %d) hit %d abs %d  arma[%02X %02X %02X %02X] arm[%02X %02X %02X %02X]%s",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??", chr(i, O_LEVEL),
            chr16(i, O_CURHP), chr16(i, O_MAXHP),
            chr(i, O_DMG), chr(i, O_DMG_B), chr(i, O_HIT), chr(i, O_ABSORB),
            chr(i, O_WEAPON), chr(i, O_WEAPON+1), chr(i, O_WEAPON+2), chr(i, O_WEAPON+3),
            chr(i, O_ARMOR), chr(i, O_ARMOR+1), chr(i, O_ARMOR+2), chr(i, O_ARMOR+3),
            (chr(i, O_AIL) == 1) and "  CADUTO" or ""))
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
-- "P1 Button 2" del keypad, FIRE2 e' "P1 Button 1" del joystick. Verificato in
-- slice52; un pulsante premuto sulla porta sbagliata non da' errore, da' un
-- gioco fermo.
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

-- CIO' CHE E' DAVVERO IN VRAM, non cio' che il gioco crede di aver scritto.
-- Serve a separare due difetti che nel PNG si somigliano: "ha scritto il byte
-- sbagliato" e "il byte non e' mai arrivato". La name table del modo 2 sta a
-- $1800 e il tile e' il codice ASCII (il font del BIOS parte dalla tile $20).
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]
local function vram_row(row)
    local s = ""
    for c = 0, 31 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
    end
    return s
end
-- IL CURSORE E' UNA PROVA, non un dettaglio estetico: la prima stesura di
-- draw_cursor lo metteva su tutte le righe PRIMA di quella scelta (un `&&`
-- dentro un `?:`, che sccz80 compila sbagliato). A schermo sembrava un
-- problema di cancellazione, e nessun controllo di RAM lo avrebbe visto --
-- gli acquisti finivano lo stesso sulla voce e sul personaggio giusti.
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

-- =====================================================================
--  il piano
-- =====================================================================
-- I tratti di cammino escono da:
--   .\tools\plan_town_route.ps1 -ToShop 1
--   .\tools\plan_town_route.ps1 -FromX 11 -FromY 10 -ToShop 51
--   .\tools\plan_town_route.ps1 -FromX 11 -FromY 18 -ToShop 41
-- Copiati, non riscritti.
local SNAP = {}   -- valori catturati prima di un acquisto, per il confronto

local PLAN = {
    -- ---------- l'armeria (shop_id 1), porta a (11,10) ----------
    -- ROTTA RICALCOLATA IN slice76: da (15,12) non si passa piu', ci sta
    -- Arylon la ballerina. Le rotte le calcola tools/plan_town_route.ps1, che
    -- da slice76 conosce anche gli abitanti -- a mano un abitante e un muro
    -- danno lo stesso "passo bloccato" nel log.
    { k = "step", dir = "U", n = 10, why = "fino a (16,13)" },
    { k = "step", dir = "L", n = 2,  why = "fino a (14,13)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (14,12)" },
    { k = "step", dir = "L", n = 2,  why = "fino a (12,12)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (12,11)" },
    { k = "step", dir = "L", n = 1,  why = "fino a (11,11)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (11,10): la porta apre il negozio" },
    { k = "wait", n = 120, why = "l'armeria si disegna" },
    { k = "check_shop", want = 1, why = "shop_id dell'armeria" },
    { k = "shot", why = "ARMERIA -- listino, oro e gruppo" },
    { k = "cursor", why = "appena aperta, il cursore sta sulla voce 1", row0 = 3, step = 2, n = 5, sel = 0 },

    -- ---------- prova 1: bastone al guerriero ----------
    { k = "snap", why = "prima dell'acquisto" },
    { k = "tap", btn = "F1", why = "FIRE1: compra la voce 1 (Wooden staff, 5 GP)" },
    { k = "wait", n = 20, why = "compare la domanda 'a chi'" },
    { k = "shot", why = "ARMERIA -- a chi la do? (il divieto e' gia' a schermo)" },
    { k = "cursor", why = "scelta del personaggio", row0 = 17, step = 1, n = 4, sel = 0 },
    { k = "tap", btn = "F1", why = "FIRE1: al personaggio 1, il guerriero" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "bastone al guerriero", fn = function()
        local w  = chr(0, O_WEAPON)
        local dm = chr(0, O_DMG)
        local okw = (w == 0x83)     -- indice 2 (WoodenStaff) -> casella 3, indossata
        local okd = (dm == SNAP.dmg0 + 6)
        local okg = (gold() == SNAP.gold - 5)
        report(okw, string.format("casella arma = $%02X (atteso $83: indossato, indice 2)", w))
        report(okd, string.format("danno = %d (era %d, il bastone vale +6)", dm, SNAP.dmg0))
        report(okg, string.format("oro = %d (era %d, il bastone costa 5)", gold(), SNAP.gold))
    end },
    { k = "shot", why = "ARMERIA -- comprato: il danno del guerriero e' salito" },

    -- ---------- prova 2: stocco al mago bianco (VIETATO) ----------
    { k = "snap", why = "prima dell'acquisto" },
    { k = "tap", btn = "D", why = "cursore: voce 2" },
    { k = "cursor", why = "un giu' sul listino", row0 = 3, step = 2, n = 5, sel = 1 },
    { k = "tap", btn = "D", why = "cursore: voce 3" },
    { k = "cursor", why = "due giu' sul listino", row0 = 3, step = 2, n = 5, sel = 2 },
    { k = "tap", btn = "D", why = "cursore: voce 4 (Rapier, 10 GP)" },
    { k = "tap", btn = "F1", why = "FIRE1: compra lo stocco" },
    { k = "wait", n = 20, why = "compare la domanda 'a chi'" },
    { k = "tap", btn = "D", why = "cursore: personaggio 2" },
    { k = "cursor", why = "un giu' sui personaggi", row0 = 17, step = 1, n = 4, sel = 1 },
    { k = "tap", btn = "D", why = "cursore: personaggio 3, il mago bianco" },
    { k = "shot", why = "ARMERIA -- il mago bianco e' marcato NO sullo stocco" },
    { k = "cursor", why = "due giu' sui personaggi: il mago bianco", row0 = 17, step = 1, n = 4, sel = 2 },
    { k = "tap", btn = "F1", why = "FIRE1: dallo al mago bianco" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "stocco al mago bianco: permesso negato", fn = function()
        local w  = chr(2, O_WEAPON)
        local dm = chr(2, O_DMG)
        report(w == 0x04, string.format("casella arma = $%02X (atteso $04: indice 3 nello zaino, bit 7 SPENTO)", w))
        report(dm == SNAP.dmg2, string.format("danno = %d (invariato, era %d)", dm, SNAP.dmg2))
        report(gold() == SNAP.gold - 10, string.format("oro = %d (era %d, lo stocco costa 10)", gold(), SNAP.gold))
    end },

    -- ---------- prova 3: nunchaku al monaco (formula speciale) ----------
    { k = "snap", why = "prima dell'acquisto" },
    { k = "tap", btn = "U", why = "cursore: voce 3 (Wooden nunchucks, 10 GP)" },
    { k = "tap", btn = "F1", why = "FIRE1: compra il nunchaku" },
    { k = "wait", n = 20, why = "compare la domanda 'a chi'" },
    { k = "tap", btn = "U", why = "cursore: personaggio 2, il monaco" },
    { k = "tap", btn = "F1", why = "FIRE1: dallo al monaco" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "nunchaku al monaco", fn = function()
        local w    = chr(1, O_WEAPON)
        local dm   = chr(1, O_DMG)
        local want = math.floor(chr(1, O_STR) / 2) + 12   -- forza/2 + arma, NON base+arma
        report(w == 0x81, string.format("casella arma = $%02X (atteso $81: indossato, indice 0)", w))
        report(dm == want, string.format("danno = %d (atteso %d = forza %d / 2 + 12)", dm, want, chr(1, O_STR)))
        -- ONESTA' DELLA PROVA: al livello 1 il monaco ha forza 5 e danno base
        -- 2, e 5/2 fa proprio 2 -- le due formule danno lo stesso numero e
        -- questa corsa NON le distingue. A distinguerle e' gia' stata slice65
        -- con -DFORCE_EQUIP (stocco al monaco: 11 contro 13). Scritto qui
        -- perche' un "ok" che non discrimina, letto fra un anno, sembra una
        -- prova che non e'.
        if SNAP.dmg1 + 12 == want then
            print("       (nota: a questo livello base+arma darebbe lo stesso numero: la prova non discrimina)")
        end
        report(gold() == SNAP.gold - 10, string.format("oro = %d (era %d)", gold(), SNAP.gold))
    end },
    { k = "shot", why = "ARMERIA -- tre acquisti, tre esiti diversi" },
    { k = "tap", btn = "F2", why = "FIRE2: si esce dall'armeria" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "dump", why = "dopo l'armeria" },

    -- ---------- la locanda (shop_id 51), porta a (11,18) ----------
    { k = "step", dir = "D", n = 4, why = "fino a (11,14)" },
    { k = "step", dir = "R", n = 3, why = "fino a (14,14)" },
    { k = "step", dir = "D", n = 5, why = "fino a (14,19)" },
    { k = "step", dir = "L", n = 3, why = "fino a (11,19)" },
    { k = "step", dir = "U", n = 1, why = "fino a (11,18): la locanda" },
    { k = "wait", n = 120, why = "la locanda si disegna" },
    { k = "check_shop", want = 51, why = "shop_id della locanda" },
    { k = "shot", why = "LOCANDA -- 30 GP, e il gruppo e' malconcio" },
    { k = "snap", why = "prima di dormire" },
    { k = "tap", btn = "F1", why = "FIRE1: si dorme" },
    { k = "wait", n = 30, why = "la notte passa" },
    { k = "chk", why = "la locanda", fn = function()
        report(gold() == SNAP.gold - 30, string.format("oro = %d (era %d, la notte costa 30)", gold(), SNAP.gold))
        report(chr16(0, O_CURHP) == chr16(0, O_MAXHP),
            string.format("il ferito e' pieno: %d/%d", chr16(0, O_CURHP), chr16(0, O_MAXHP)))
        report(chr(2, O_AIL) == 1 and chr16(2, O_CURHP) == 0,
            string.format("il CADUTO e' rimasto tale: mal=%d HP=%d (MenuFillPartyHP lo salta)",
                chr(2, O_AIL), chr16(2, O_CURHP)))
        report(chr(3, O_CURMP0) == chr(3, O_MAXMP0),
            string.format("le cariche di magia sono tornate: %d/%d", chr(3, O_CURMP0), chr(3, O_MAXMP0)))
    end },
    { k = "shot", why = "LOCANDA -- dopo la notte" },
    { k = "tap", btn = "F2", why = "FIRE2: si esce dalla locanda" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },

    -- ---------- la clinica (shop_id 41), porta a (24,4) ----------
    { k = "step", dir = "D", n = 1,  why = "fino a (11,19)" },
    { k = "step", dir = "R", n = 3,  why = "fino a (14,19)" },
    { k = "step", dir = "U", n = 11, why = "fino a (14,8)" },
    { k = "step", dir = "R", n = 2,  why = "fino a (16,8)" },
    { k = "step", dir = "U", n = 3,  why = "fino a (16,5)" },
    { k = "step", dir = "R", n = 8,  why = "fino a (24,5)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (24,4): la clinica" },
    { k = "wait", n = 120, why = "la clinica si disegna" },
    { k = "check_shop", want = 41, why = "shop_id della clinica" },
    { k = "shot", why = "CLINICA -- 40 GP, e c'e' un caduto" },
    { k = "snap", why = "prima della cura" },
    { k = "tap", btn = "D", why = "cursore: personaggio 2" },
    { k = "tap", btn = "D", why = "cursore: personaggio 3, il caduto" },
    { k = "tap", btn = "F1", why = "FIRE1: rialzalo" },
    { k = "wait", n = 30, why = "la cura si compie" },
    { k = "chk", why = "la clinica", fn = function()
        report(gold() == SNAP.gold - 40, string.format("oro = %d (era %d, la cura costa 40)", gold(), SNAP.gold))
        report(chr(2, O_AIL) == 0, string.format("il caduto non e' piu' tale: mal=%d", chr(2, O_AIL)))
        report(chr16(2, O_CURHP) == 1, string.format("si rialza con UN HP: %d (come il NES, non pieno)", chr16(2, O_CURHP)))
    end },
    { k = "shot", why = "CLINICA -- rialzato" },
    { k = "tap", btn = "F2", why = "FIRE2: si esce dalla clinica" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
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

local STEP_LIMIT = 240   -- se un passo non arriva entro questi frame, e' un difetto
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
        -- La fotografia dei numeri PRIMA di toccare qualcosa. Serve perche' le
        -- attese sono differenze (-5 GP, +6 danno), non valori assoluti: i
        -- valori assoluti dipendono dalle statistiche iniziali, che una
        -- revisione della tabella delle classi cambierebbe.
        SNAP.gold = gold()
        SNAP.dmg0 = chr(0, O_DMG); SNAP.dmg1 = chr(1, O_DMG)
        SNAP.dmg2 = chr(2, O_DMG); SNAP.dmg3 = chr(3, O_DMG)
        print(string.format("   [istantanea %s] oro=%d danni=%d/%d/%d/%d",
            a.why, SNAP.gold, SNAP.dmg0, SNAP.dmg1, SNAP.dmg2, SNAP.dmg3))
        pi = pi + 1; return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn()
        pi = pi + 1; return
    elseif a.k == "cursor" then
        check_cursor(a.why, a.row0, a.step, a.n, a.sel)
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
        -- Premuto e RILASCIATO: dentro il negozio si comanda a fronti, non a
        -- livelli. Entrando si tiene ancora premuta la direzione che ha
        -- calpestato la porta, e senza il rilascio il primo comando sarebbe
        -- quello -- il negozio si chiuderebbe da solo prima di essere visto.
        if timer <= TAP_PRESS then press(a.btn, true)
        elseif timer <= TAP_PRESS + TAP_REST then press(a.btn, false)
        else release_all(); next_action() end
        return
    end

    -- a.k == "step": si tiene premuto FINCHE' la posizione non cambia, e non
    -- per N frame. STEP_COOLDOWN_FRAMES vale 1 e il redraw della citta' si
    -- mangia un numero variabile di vblank: a tempo fisso lo stesso cammino
    -- esce diverso a ogni corsa.
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
-- Identico a mame_drive_town.lua: qui l'intro non e' il soggetto.
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

-- expand_town espande 4096 macrotile in 16384 celle: ~140 frame. Uno scatto
-- prima di allora cade IN MEZZO all'espansione e mostra la overworld.
local TOWN_READY = t + 300
at(TOWN_READY, function()
    refresh_chr_size()
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d",
        u16(PARTY_BASE), PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE))
    if u16(PARTY_BASE) ~= PARTY_MAGIC then
        print("!! MAGIC DEL GRUPPO DIVERSO: il layout e' cambiato, i campi qui sotto non valgono")
    end
    dump_party("CONERIA -- ingresso")
    shot("CONERIA -- ingresso")
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
