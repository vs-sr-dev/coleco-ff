-- mame_drive_magicshop.lua -- si imparano le magie: permessi, "la sa gia'",
-- livello pieno, oro.  (slice67)
--
-- PERCHE' UNO SCRIPT NUOVO E NON UN PEZZO IN PIU' IN mame_drive_shop.lua
-- Quello prova cio' che l'acquisto di un OGGETTO cambia, e finisce con 320 GP
-- spesi. Qui ogni magia costa 100 su 400 di partenza: le due corse non ci
-- stanno nello stesso portafoglio, e il quarto acquisto di questa fallirebbe
-- per mancanza d'oro invece che per la ragione che si vuole provare -- cioe'
-- un "ok" che non significa niente.
--
-- LA CORSA VUOLE LA BUILD DI PROVA -DFORCE_SHOP (ROM col suffisso _t): le
-- classi sono FISSE -- FT, BB, WM, BM -- e senza di quelle "il guerriero non
-- ha imparato CURE" non si distingue da "non l'ha imparata chi poteva".
-- Quella build lascia anche il gruppo malconcio (un ferito, un caduto): qui
-- non conta e non e' una svista. Ne' sul NES ne' qui un caduto e' impedito a
-- imparare -- MagicShop_AssertLearn le alterazioni non le guarda proprio.
--
-- LE PROVE, e perche' quelle. Sono i TRE rifiuti di MagicShop_AssertLearn
-- (bank_0E.asm:5705) piu' l'oro, ciascuno preso da solo:
--   1. CURE al MAGO BIANCO      -> imparata: casella = 1, -100 GP
--   2. CURE ANCORA al mago      -> "la sa gia'": niente casella, niente oro
--   3. CURE al GUERRIERO        -> permesso NEGATO (FT ha $FF su tutti e 8 i
--                                  livelli): niente casella, niente oro
--   4. HARM e FOG al mago       -> il livello 1 arriva a 3 su 3
--   5. RUSE al mago             -> "livello pieno". E' la prova che il tetto
--                                  e' TRE e non otto: al livello 1 di magia
--                                  bianca gli incantesimi sono quattro, i
--                                  posti tre, e sceglierne tre e' il gioco
--   6. RUSE al MAGO NERO        -> permesso negato al contrario: BM ha $F0,
--                                  cioe' vietata la META' BIANCA del livello.
--                                  Con la 3 dice che il bit non e' un
--                                  interruttore per classe ma per CASELLA
--   7. FIRE al mago nero (altro negozio) -> imparata, e la casella vale 5,
--                                  non 1: il valore e' QUALE degli otto
--   8. SLEP a zero oro          -> il prezzo si prova prima di chiedere a chi
--
-- CHE COSA SI GUARDA. Le caselle di `ch_spells` in RAM SGM e l'oro, piu' le
-- etichette a schermo lette dalla VRAM: NO / KNOWN / FULL compaiono PRIMA di
-- premere, e sono la parte che il giocatore vede. Un'etichetta e' una prova
-- come un byte -- e' la lezione di slice66, dove un cursore sbagliato non
-- lasciava traccia in RAM.
--
-- USO
--   .\tools\build_all.ps1 -Slice slice67 -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22' -Defines FORCE_SHOP
--   & mame.exe coleco -exp sgm -cart build\slice67_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 400 `
--       -autoboot_script tools\mame_drive_magicshop.lua

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
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6          -- magic(2) n(1) gp(3)
local O_CLS, O_AIL, O_NAME  = 0, 1, 2
local O_CURHP, O_MAXHP      = 12, 14
local O_LEVEL               = 27
local O_CURMP0              = 28
-- Le magie apprese stanno IN CODA alla voce, dopo le 4+4 caselle di
-- equipaggiamento: cls(1) ail(1) nome(7) exp(3) hp(4) stat(5) sub(6) lv(1)
-- mp(16) base(3) armi(4) armature(4) = 55.
local O_SPELLS              = 55
local SPELLS_PER_LEVEL      = 3

-- --- il listino composto (shop_state.h) ------------------------------------
local SHOP_BASE  = 0x6300
local SHOP_MAGIC = 0x5703

-- Il passo si LEGGE dal gioco: trappola numero 1 del catalogo.
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
local function spell(i, lvl, slot) return chr(i, O_SPELLS + lvl * SPELLS_PER_LEVEL + slot) end
local function spells_str(i, lvl)
    local s = {}
    for k = 0, SPELLS_PER_LEVEL - 1 do s[#s + 1] = string.format("%d", spell(i, lvl, k)) end
    return table.concat(s, ",")
end
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
        print(string.format("   %d %-6s %s lv%d HP %d/%d  MP-L1 %d  magie L1 [%s] L2 [%s]",
            i + 1, name_of(i), CLSNAME[chr(i, O_CLS)] or "??", chr(i, O_LEVEL),
            chr16(i, O_CURHP), chr16(i, O_MAXHP), chr(i, O_CURMP0),
            spells_str(i, 0), spells_str(i, 1)))
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

-- CIO' CHE E' DAVVERO IN VRAM. Le etichette del negozio di magia non lasciano
-- traccia in RAM: sono l'unica prova che il giudizio mostrato PRIMA
-- dell'acquisto e' lo stesso che l'acquisto poi applica.
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

-- =====================================================================
--  il piano
-- =====================================================================
-- I tratti di cammino escono da:
--   .\tools\plan_town_route.ps1 -ToShop 21
--   .\tools\plan_town_route.ps1 -FromX 7 -FromY 4 -ToShop 31
-- Copiati, non riscritti. Nota per chi cerca le porte a memoria: il negozio 21
-- (magia BIANCA) sta a (7,4) e il 31 (NERA) a (3,4) -- l'appunto di sessione 18
-- li aveva scambiati, e questi vengono dagli stessi byte che legge il gioco.
local SNAP = {}
local ROW_CHR0 = 17     -- le quattro righe del gruppo, come in ovl_shop.c
local COL_TAG  = 18     -- la colonna dove compaiono NO / KNOWN / FULL

local PLAN = {
    -- ---------- il negozio di magia BIANCA (shop_id 21), porta a (7,4) -----
    -- ROTTA RICALCOLATA IN slice76: da (15,12) non si passa piu', ci sta
    -- Arylon la ballerina. Le rotte le calcola tools/plan_town_route.ps1, che
    -- da slice76 conosce anche gli abitanti -- a mano un abitante e un muro
    -- danno lo stesso "passo bloccato" nel log.
    { k = "step", dir = "U", n = 10, why = "fino a (16,13)" },
    { k = "step", dir = "L", n = 2,  why = "fino a (14,13)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (14,12)" },
    { k = "step", dir = "L", n = 2,  why = "fino a (12,12)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (12,11)" },
    { k = "step", dir = "L", n = 4,  why = "fino a (8,11)" },
    { k = "step", dir = "U", n = 6,  why = "fino a (8,5)" },
    { k = "step", dir = "L", n = 1,  why = "fino a (7,5)" },
    { k = "step", dir = "U", n = 1,  why = "fino a (7,4): la porta apre il negozio" },
    { k = "wait", n = 120, why = "il negozio di magia bianca si disegna" },
    { k = "check_shop", want = 21, why = "shop_id della magia bianca" },
    { k = "chk", why = "il blocco condiviso", fn = function()
        report(u16(SHOP_BASE) == SHOP_MAGIC,
            string.format("magic del listino = $%04X (atteso $%04X)", u16(SHOP_BASE), SHOP_MAGIC))
        report(u8(SHOP_BASE + 4) == 4,
            string.format("voci = %d (attese 4: CURE HARM FOG RUSE)", u8(SHOP_BASE + 4)))
    end },
    { k = "screen", why = "magia bianca appena aperta", r0 = 1, r1 = 21 },
    { k = "shot", why = "MAGIA BIANCA -- listino, oro e gruppo" },
    { k = "cursor", why = "appena aperto, il cursore sta sulla voce 1", row0 = 3, step = 2, n = 4, sel = 0 },

    -- I quattro giudizi a schermo, PRIMA di comprare qualunque cosa. Sono
    -- l'unica prova che i permessi arrivano davvero dal banco 11: se la
    -- tabella non fosse stata trasferita, `magperm` sarebbe zero e NESSUNO
    -- risulterebbe impedito -- cioe' uno schermo che sembra a posto.
    { k = "label", who = 0, want = "NO", why = "CURE: il guerriero non puo'" },
    { k = "label", who = 1, want = "NO", why = "CURE: il monaco non puo'" },
    { k = "label", who = 2, want = "  ", why = "CURE: il mago bianco puo'" },
    { k = "label", who = 3, want = "NO", why = "CURE: il mago nero non puo' (meta' bianca vietata)" },

    -- ---------- prova 1: CURE al mago bianco ----------
    { k = "snap", why = "prima di CURE" },
    { k = "tap", btn = "F1", why = "FIRE1: compra CURE (100 GP)" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "cursor", why = "scelta del personaggio", row0 = 17, step = 1, n = 4, sel = 0 },
    { k = "tap", btn = "3", why = "tastierino 3: dritti al mago bianco" },
    { k = "cursor", why = "il tastierino ha spostato il cursore", row0 = 17, step = 1, n = 4, sel = 2 },
    { k = "tap", btn = "F1", why = "FIRE1: la impara il mago bianco" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "CURE al mago bianco", fn = function()
        report(spell(2, 0, 0) == 1,
            string.format("casella L1 = [%s] (atteso 1 nel primo posto: CURE e' la magia 1 delle 8 del livello)", spells_str(2, 0)))
        report(gold() == SNAP.gold - 100, string.format("oro = %d (era %d, CURE costa 100)", gold(), SNAP.gold))
    end },
    { k = "label", who = 2, want = "KN", why = "adesso il mago bianco la sa" },
    { k = "shot", why = "MAGIA BIANCA -- CURE imparata" },

    -- ---------- prova 2: CURE di nuovo, allo stesso ----------
    { k = "snap", why = "prima del doppione" },
    { k = "tap", btn = "F1", why = "FIRE1: compra CURE un'altra volta" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "3", why = "tastierino 3: di nuovo il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "chk", why = "CURE due volte: la sa gia'", fn = function()
        report(gold() == SNAP.gold, string.format("oro = %d: NON e' stato speso niente", gold()))
        report(spell(2, 0, 1) == 0,
            string.format("il secondo posto e' rimasto vuoto: [%s]", spells_str(2, 0)))
    end },
    { k = "text", row = 22, col = 1, want = "THAT ONE KNOWS IT ALREADY", why = "il messaggio del rifiuto" },

    -- ---------- prova 3: CURE al guerriero (permesso negato) ----------
    { k = "snap", why = "prima del divieto" },
    { k = "tap", btn = "F1", why = "FIRE1: compra CURE" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "1", why = "tastierino 1: il guerriero" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "chk", why = "CURE al guerriero: permesso negato", fn = function()
        report(gold() == SNAP.gold, string.format("oro = %d: niente speso", gold()))
        report(spell(0, 0, 0) == 0,
            string.format("il guerriero non ha niente al livello 1: [%s]", spells_str(0, 0)))
    end },
    { k = "text", row = 22, col = 1, want = "THAT ONE CAN'T LEARN IT", why = "il messaggio del divieto" },

    -- ---------- prova 4: HARM e FOG, fino a riempire il livello ----------
    { k = "snap", why = "prima di HARM" },
    { k = "tap", btn = "2", why = "tastierino 2: la voce HARM" },
    { k = "cursor", why = "il tastierino sceglie la voce", row0 = 3, step = 2, n = 4, sel = 1 },
    { k = "tap", btn = "F1", why = "FIRE1: compra HARM" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "tap", btn = "3", why = "tastierino 3: la voce FOG" },
    { k = "tap", btn = "F1", why = "FIRE1: compra FOG" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "il livello 1 e' pieno", fn = function()
        report(spell(2, 0, 1) == 2 and spell(2, 0, 2) == 3,
            string.format("caselle L1 = [%s] (attese 1,2,3 = CURE HARM FOG)", spells_str(2, 0)))
        report(gold() == SNAP.gold - 200, string.format("oro = %d (era %d: due magie, 200)", gold(), SNAP.gold))
    end },
    { k = "shot", why = "MAGIA BIANCA -- tre magie, il livello 1 e' pieno" },

    -- ---------- prova 5: RUSE, che non ci sta piu' ----------
    { k = "snap", why = "prima di RUSE" },
    { k = "tap", btn = "4", why = "tastierino 4: la voce RUSE" },
    { k = "label", who = 2, want = "FU", why = "il mago bianco e' segnato FULL prima di premere" },
    { k = "label", who = 3, want = "NO", why = "il mago nero resta NO: e' il permesso, non il posto" },
    { k = "tap", btn = "F1", why = "FIRE1: compra RUSE" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "3", why = "tastierino 3: il mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "chk", why = "RUSE a livello pieno", fn = function()
        report(gold() == SNAP.gold, string.format("oro = %d: niente speso", gold()))
        report(spells_str(2, 0) == "1,2,3", string.format("caselle L1 invariate: [%s]", spells_str(2, 0)))
    end },
    { k = "text", row = 22, col = 1, want = "THAT SPELL LEVEL IS FULL", why = "il messaggio del livello pieno" },

    -- ---------- prova 6: RUSE al mago nero ----------
    { k = "tap", btn = "F1", why = "FIRE1: compra RUSE" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "4", why = "tastierino 4: il mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "chk", why = "RUSE al mago nero: meta' bianca vietata", fn = function()
        report(spells_str(3, 0) == "0,0,0",
            string.format("il mago nero non ha niente al livello 1: [%s]", spells_str(3, 0)))
        report(gold() == SNAP.gold, string.format("oro = %d: niente speso", gold()))
    end },
    { k = "text", row = 22, col = 1, want = "THAT ONE CAN'T LEARN IT", why = "il messaggio del divieto" },
    { k = "dump", why = "uscendo dalla magia bianca" },
    { k = "tap", btn = "F2", why = "FIRE2: si esce" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },

    -- ---------- il negozio di magia NERA (shop_id 31), porta a (3,4) -------
    { k = "step", dir = "D", n = 1, why = "fino a (7,5)" },
    { k = "step", dir = "L", n = 4, why = "fino a (3,5)" },
    { k = "step", dir = "U", n = 1, why = "fino a (3,4): la magia nera" },
    { k = "wait", n = 120, why = "il negozio di magia nera si disegna" },
    { k = "check_shop", want = 31, why = "shop_id della magia nera" },
    { k = "shot", why = "MAGIA NERA -- listino" },
    -- Il rovescio esatto della prima schermata: qui il mago NERO puo' e il
    -- BIANCO no. Sono gli stessi 96 byte letti con un bit diverso.
    { k = "label", who = 2, want = "NO", why = "FIRE: il mago bianco non puo'" },
    { k = "label", who = 3, want = "  ", why = "FIRE: il mago nero puo'" },

    -- ---------- prova 7: FIRE al mago nero ----------
    { k = "snap", why = "prima di FIRE" },
    { k = "tap", btn = "F1", why = "FIRE1: compra FIRE (100 GP)" },
    { k = "wait", n = 20, why = "compare la domanda 'chi la impara'" },
    { k = "tap", btn = "4", why = "tastierino 4: il mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: dagliela" },
    { k = "wait", n = 20, why = "l'acquisto si compie" },
    { k = "chk", why = "FIRE al mago nero", fn = function()
        -- CINQUE, non uno. FIRE e' la magia $B4, cioe' l'id 4 del livello 1, e
        -- la casella tiene QUALE delle otto (1-8) -- non il posto in cui sta.
        -- Se qui uscisse 1 il negozio avrebbe insegnato CURE col nome di FIRE,
        -- e in battaglia si vedrebbe solo dall'effetto.
        report(spell(3, 0, 0) == 5,
            string.format("casella L1 = [%s] (atteso 5: FIRE e' la 5a delle otto del livello)", spells_str(3, 0)))
        report(gold() == SNAP.gold - 100, string.format("oro = %d (era %d)", gold(), SNAP.gold))
    end },
    { k = "shot", why = "MAGIA NERA -- FIRE imparata, e l'oro e' finito" },

    -- ---------- prova 8: senza piu' oro ----------
    { k = "chk", why = "l'oro e' a zero", fn = function()
        report(gold() == 0, string.format("oro = %d", gold()))
    end },
    { k = "tap", btn = "2", why = "tastierino 2: la voce SLEP" },
    { k = "tap", btn = "F1", why = "FIRE1: prova a comprare SLEP" },
    { k = "wait", n = 20, why = "il rifiuto compare" },
    { k = "text", row = 22, col = 1, want = "YOU CAN'T AFFORD IT", why = "il prezzo si prova prima di chiedere a chi" },
    { k = "chk", why = "senza oro non si arriva nemmeno a scegliere", fn = function()
        -- Il cursore e' ancora sul LISTINO: se la domanda "chi la impara"
        -- fosse comparsa, la riga 15 direbbe altro e il cursore starebbe sui
        -- personaggi. E' la stessa scelta del negozio d'equipaggiamento --
        -- chiedere e poi rifiutare farebbe sembrare colpa della scelta.
        local prompt = vram_text(15, 1, 16)
        report(prompt:sub(1, 16) == "WHAT WILL IT BE?",
            string.format("la domanda e' ancora quella della merce: '%s'", prompt))
    end },
    { k = "dump", why = "alla fine" },
    { k = "tap", btn = "F2", why = "FIRE2: si esce" },
    { k = "wait", n = 150, why = "la citta' rimette la sua grafica" },
    { k = "shot", why = "CONERIA -- si torna in citta'" },
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

-- Il tastierino, che qui fa la maggior parte del lavoro: scegliere voce e
-- personaggio con un tasto invece che contando i passi del cursore. E' il
-- vantaggio del Coleco sul NES (memory/design_input.md), e in una prova conta
-- doppio -- una direzione di troppo sposta la scelta senza dirlo, un tasto no.
--
-- IL NOME DEL CAMPO NON SI INDOVINA. Nessuno script di questo progetto aveva
-- ancora premuto una CIFRA del tastierino (i pulsanti si', le cifre no), e un
-- nome sbagliato non da' errore: da' un tasto che non arriva, cioe' una prova
-- che fallisce per il motivo sbagliato. Si scorrono i campi della porta una
-- volta sola e si prende quello che finisce con la cifra.
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
        -- I campi si chiamano "3 (pad 1)", non "P1 Keypad 3": la cifra sta in
        -- TESTA. Cercarla in coda -- che era la prima stesura -- trova zero
        -- campi e non da' errore di sintassi, da' tasti che non arrivano: nel
        -- log si legge come un negozio che ignora il tastierino.
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
    for ch, f in pairs(KEYPAD) do f:set_value(0) end
end

local function check_label(why, who, want)
    local got = vram_text(ROW_CHR0 + who, COL_TAG, #want)
    report(got == want, string.format("%s: colonna %d della riga %d = '%s' (atteso '%s')",
        why, COL_TAG, ROW_CHR0 + who, got, want))
end
local function check_text(why, row, col, want)
    local got = vram_text(row, col, #want)
    report(got == want, string.format("%s: riga %d = '%s' (atteso '%s')", why, row, got, want))
end

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
    elseif a.k == "label" then
        check_label(a.why, a.who, a.want)
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
        if timer <= TAP_PRESS then press_any(a.btn, true)
        elseif timer <= TAP_PRESS + TAP_REST then press_any(a.btn, false)
        else release_everything(); next_action() end
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
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d",
        u16(PARTY_BASE), PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE))
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
