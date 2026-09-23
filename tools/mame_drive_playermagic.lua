-- mame_drive_playermagic.lua -- il gruppo lancia incantesimi.  (slice68)
--
-- COSA PROVA, e perche' proprio quello
--   1. il comando MAGIC apre un SOTTOMENU, e quel sottomenu gira in un altro
--      banco: e' il primo overlay annidato del progetto (banco 23 dentro il
--      banco 20). Se l'annidamento non tornasse a posto, il sintomo non
--      sarebbe una magia sbagliata -- sarebbe la battaglia che smette di
--      esistere. Per questo il primo controllo e' "si e' tornati indietro".
--   2. CURE cura UNO: il sottomenu chiede a chi, e il guerriero ferito
--      guarisce. Bersaglio dalla parte del gruppo.
--   3. FIRE colpisce UN nemico: il sottomenu NON chiede a chi, perche' il
--      cursore sull'arena e' dell'altro overlay -- si torna indietro con un
--      "scegli un nemico" e la scelta la fa la battaglia. Bersaglio dalla
--      parte dei nemici, e strada diversa dalla 2.
--   4. HARM non morde gli IMP: e' danno ai NON-MORTI e gli IMP non lo sono.
--      La carica si spende, il messaggio dice INEFFECTIVE, e nessun nemico
--      perde HP. Un incantesimo che non fa niente PERCHE' NON DEVE e uno che
--      non fa niente perche' e' rotto sono la stessa cosa a occhio: e' il
--      motivo per cui questo controllo esiste.
--
-- COME SI GUARDA. Due strade insieme, e nessuna delle due basta da sola:
--   * la RAM -- cariche di magia, HP, e le due sonde nuove `pc_cast_count` /
--     `pc_last_spell` in BST, gemelle di quelle del lato nemico;
--   * i MESSAGGI a schermo, raccolti dalla VRAM riga 23 a ogni frame del
--     round. Un lancio dura una manciata di frame e poi non lascia traccia:
--     senza il raccoglitore, "MERLIN CASTS CURE" o c'e' o non c'e' e non si
--     puo' sapere. E' la stessa lezione del cursore di slice66 -- cio' che
--     vale come prova a schermo va ASSERITO, non fotografato.
--
-- LA CORSA VUOLE -DFORCE_SPELLS (ROM col suffisso _t): classi fisse FT BB WM
-- BM, quattro magie gia' apprese, nove cariche, e il guerriero a 12 HP. Il
-- negozio di magia ha la SUA corsa (mame_drive_magicshop.lua): far comprare
-- le magie anche a questa vorrebbe dire che un difetto del lancio e uno
-- dell'acquisto fanno fallire lo stesso controllo.
--
-- USO
--   .\tools\build_all.ps1 -Slice slice68 `
--       -Overlays 'ovl_battle:20','ovl_intro:21','ovl_shop:22','ovl_btlmagic:23' `
--       -Defines FORCE_SPELLS
--   & mame.exe coleco -exp sgm -cart build\slice68_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 700 `
--       -autoboot_script tools\mame_drive_playermagic.lua

local frames = 0
local fields = {}
local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end

-- --- battle_state.h, offset calcolati sulla struct (slice68) ---------------
local BATTLE_MAGIC  = 0xB47E
local OFF_TURN      = 0x600A
local OFF_CMD       = 0x600B
local OFF_ROUND     = 0x600C
local OFF_NTYPES    = 0x601E
local OFF_TYPEENEMY = 0x6027
local OFF_NENEMIES  = 0x6053
local OFF_ENEMYTYPE = 0x6054   -- 9
local OFF_ENEMYHP   = 0x605D   -- 9 x 2
local OFF_PHASE     = 0x607F
local OFF_CHRCMD    = 0x6081   -- 4
local OFF_CHRTGT    = 0x6085   -- 4
local OFF_CHRCHOSEN = 0x6089   -- 4
local OFF_CASTCNT   = 0x60AD   -- lato NEMICO
local OFF_LASTSPELL = 0x60AE
-- slice68, in coda come sempre: chr_spell[4], poi le due sonde del gruppo.
local OFF_CHRSPELL  = 0x60AF   -- 4
local OFF_PCCAST    = 0x60B3
local OFF_PCLAST    = 0x60B4

local BPHASE_CMD, BPHASE_TARGET = 0, 1

-- --- party_state.h ---------------------------------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_CLS, O_NAME = 0, 2
local O_CURHP, O_MAXHP = 12, 14
local O_CURMP0 = 28
local O_SPELLS = 55

local probe = dofile("build/probe_addrs.lua")
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
local function name_of(i)
    local s = ""
    for k = 0, 5 do
        local c = chr(i, O_NAME + k)
        if c == 0 then break end
        s = s .. string.char(c)
    end
    return s
end
local function enemy_hp(s) return u16(OFF_ENEMYHP + s * 2) end
local function enemy_hp_total()
    local t = 0
    for s = 0, 8 do t = t + enemy_hp(s) end
    return t
end
local function in_battle() return u16(0x6000) == BATTLE_MAGIC end

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
local function dpad(n, on) find_port_field(":STD_JOY1", DPAD[n]):set_value(on and 1 or 0) end
local function release_all()
    for k, _ in pairs(DPAD) do dpad(k, false) end
    fire1(false); fire2(false)
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

-- --- il raccoglitore di messaggi -------------------------------------------
-- La riga 23 e' la riga dei messaggi di battaglia. Si legge a OGNI frame e si
-- tiene l'elenco di quelli distinti visti: un lancio dura 30 frame e poi
-- sparisce, e ricontrollarlo "al momento giusto" vorrebbe dire indovinare il
-- momento. Cosi' invece si guarda dopo, sull'elenco.
local seen_msgs = {}
local seen_list = {}
local function collect_message()
    local s = ""
    for c = 0, 23 do
        local t = vram:read_u8(0x1800 + 23 * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or " ")
    end
    s = s:gsub("%s+$", "")
    if s ~= "" and not seen_msgs[s] then
        seen_msgs[s] = true
        seen_list[#seen_list + 1] = s
    end
end
local function saw(pattern)
    for _, s in ipairs(seen_list) do
        if s:find(pattern, 1, true) then return s end
    end
    return nil
end
local function dump_messages(why)
    print(string.format("   [messaggi visti -- %s]", why))
    for _, s in ipairs(seen_list) do print("     |" .. s .. "|") end
end
local function reset_messages()
    seen_msgs = {}; seen_list = {}
end

local function dump_party(why)
    print(string.format("-- %s", why))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s HP %3d/%3d  cariche L1 %d  magie L1 [%d,%d,%d]",
            i + 1, name_of(i), chr16(i, O_CURHP), chr16(i, O_MAXHP), chr(i, O_CURMP0),
            chr(i, O_SPELLS), chr(i, O_SPELLS + 1), chr(i, O_SPELLS + 2)))
    end
end
local function dump_enemies(why)
    local s = {}
    for k = 0, 8 do
        if u8(OFF_ENEMYTYPE + k) ~= 0xFF then
            s[#s + 1] = string.format("s%d:%d", k, enemy_hp(k))
        end
    end
    print(string.format("   [nemici %s] %s  (totale %d)", why, table.concat(s, " "), enemy_hp_total()))
end

-- =====================================================================
--  il piano, guidato dallo STATO e non dal cronometro
-- =====================================================================
-- Ogni passo dice quale condizione aspetta prima di premere. Due schermate
-- uguali si distinguono da un contatore che si muove, non dal tempo passato
-- ([[mame-drive-closed-loop]]): qui la condizione e' sempre un campo di BST.
local SNAP = {}

local PLAN = {
    -- ---------- round 1: CURE dal mago bianco, FIRE dal mago nero ----------
    { k = "wait_battle", why = "si entra in battaglia" },
    { k = "wait", n = 90, why = "la schermata si disegna" },
    { k = "shot", why = "BATTAGLIA -- il menu comandi" },
    { k = "chk", why = "il gruppo e' quello della build di prova", fn = function()
        report(chr(2, O_SPELLS) == 1 and chr(3, O_SPELLS) == 5,
            string.format("magie L1: mago bianco [%d,%d] mago nero [%d,%d] (attesi CURE=1 HARM=2, FIRE=5 LIT=8)",
                chr(2, O_SPELLS), chr(2, O_SPELLS + 1), chr(3, O_SPELLS), chr(3, O_SPELLS + 1)))
        report(u8(OFF_PCCAST) == 0, string.format("nessun lancio del gruppo ancora: %d", u8(OFF_PCCAST)))
    end },
    { k = "snap", why = "prima del round 1" },

    -- chr 1 e 2 picchiano: FIRE1 apre il bersaglio, FIRE1 conferma.
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "chk", why = "il turno e' passato al mago bianco", fn = function()
        report(u8(OFF_TURN) == 2, string.format("turn_chr = %d (atteso 2)", u8(OFF_TURN)))
        report(u8(OFF_PHASE) == BPHASE_CMD, string.format("fase = %d (atteso CMD)", u8(OFF_PHASE)))
    end },

    -- ---- il mago bianco: MAGIC -> CURE -> a chi ----
    { k = "tap", btn = "D", why = "cursore comandi: MAGIC" },
    { k = "chk", why = "il comando puntato", fn = function()
        report(u8(OFF_CMD) == 1, string.format("command_idx = %d (atteso 1 = MAGIC)", u8(OFF_CMD)))
    end },
    { k = "tap", btn = "F1", why = "FIRE1: si entra nel sottomenu (banco 23)" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "shot", why = "SOTTOMENU MAGIA -- livelli, cariche, incantesimi" },
    { k = "vram", row = 17, col = 0, want = "L19/9 >CURE  HARM  ----",
      why = "la riga del livello 1 del mago bianco" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia CURE (chiede a chi)" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "U", why = "cursore: dal mago al monaco" },
    { k = "tap", btn = "U", why = "cursore: al guerriero, che e' ferito" },
    { k = "shot", why = "SOTTOMENU MAGIA -- a chi la si lancia" },
    { k = "tap", btn = "F1", why = "FIRE1: al guerriero" },
    { k = "wait", n = 30, why = "si torna nell'overlay di battaglia" },
    { k = "chk", why = "la scelta e' impegnata, e si e' tornati indietro", fn = function()
        -- Il primo controllo e' che la battaglia ESISTA ancora: se
        -- l'annidamento dei banchi non tornasse a posto, di qui in poi non ci
        -- sarebbe piu' niente da leggere.
        report(in_battle(), "il blocco di battaglia c'e' ancora (l'annidamento e' tornato a posto)")
        report(u8(OFF_CHRCMD + 2) == 1, string.format("comando del mago bianco = %d (atteso 1 = MAGIC)", u8(OFF_CHRCMD + 2)))
        report(u8(OFF_CHRSPELL + 2) == 0, string.format("incantesimo scelto = %d (atteso 0 = CURE)", u8(OFF_CHRSPELL + 2)))
        report(u8(OFF_CHRTGT + 2) == 0x80, string.format("bersaglio = $%02X (atteso $80 = personaggio 0, il guerriero)", u8(OFF_CHRTGT + 2)))
        report(u8(OFF_TURN) == 3, string.format("turn_chr = %d (atteso 3, il mago nero)", u8(OFF_TURN)))
    end },
    { k = "vram", row = 17, col = 10, want = "|", why = "il riquadro dei comandi e' tornato" },

    -- ---- il mago nero: MAGIC -> FIRE -> il bersaglio lo sceglie la battaglia ----
    { k = "reset_msgs", why = "da qui in poi si raccolgono i messaggi del round" },
    { k = "tap", btn = "D", why = "cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: si entra nel sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "vram", row = 17, col = 0, want = "L19/9 >FIRE  LIT   ----",
      why = "la riga del livello 1 del mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia FIRE" },
    { k = "wait", n = 25, why = "si torna alla battaglia per scegliere il nemico" },
    { k = "chk", why = "FIRE vuole UN nemico, e a sceglierlo e' la battaglia", fn = function()
        report(u8(OFF_PHASE) == BPHASE_TARGET,
            string.format("fase = %d (atteso TARGET: il sottomenu ha restituito 'scegli un nemico')", u8(OFF_PHASE)))
        report(u8(OFF_CHRSPELL + 3) == 4, string.format("incantesimo scelto = %d (atteso 4 = FIRE)", u8(OFF_CHRSPELL + 3)))
    end },
    { k = "shot", why = "BATTAGLIA -- il cursore sceglie il nemico per FIRE" },
    { k = "enemies", why = "prima del round" },
    { k = "tap", btn = "F1", why = "FIRE1: conferma il nemico -- e il round parte" },
    { k = "wait_round", why = "il round si risolve" },

    { k = "chk", why = "il round 1", fn = function()
        report(u8(OFF_PCCAST) == 2, string.format("lanci del gruppo = %d (attesi 2: CURE e FIRE)", u8(OFF_PCCAST)))
        report(chr(2, O_CURMP0) == SNAP.mp2 - 1,
            string.format("cariche del mago bianco = %d (erano %d)", chr(2, O_CURMP0), SNAP.mp2))
        report(chr(3, O_CURMP0) == SNAP.mp3 - 1,
            string.format("cariche del mago nero = %d (erano %d)", chr(3, O_CURMP0), SNAP.mp3))
        -- La cura si guarda in salita e non a un valore preciso: nello stesso
        -- round i nemici picchiano, e un numero esatto qui sarebbe un
        -- controllo che fallisce quando il gioco funziona.
        report(chr16(0, O_CURHP) > SNAP.hp0,
            string.format("il guerriero e' salito: %d HP (era %d, CURE ne da' 16-32)",
                chr16(0, O_CURHP), SNAP.hp0))
    end },
    { k = "msgs", why = "il round 1" },
    { k = "chk", why = "i due lanci si sono visti a schermo", fn = function()
        local a = saw("CASTS CURE")
        local b = saw("CASTS FIRE")
        report(a ~= nil, "messaggio di CURE: " .. (a or "MAI COMPARSO"))
        report(b ~= nil, "messaggio di FIRE: " .. (b or "MAI COMPARSO"))
    end },
    { k = "shot", why = "BATTAGLIA -- dopo il round 1" },
    { k = "dump", why = "dopo il round 1" },

    -- ---------- round 2: HARM sugli IMP, che non sono non-morti ----------
    { k = "wait_cmd", why = "il round 2 comincia" },
    { k = "snap", why = "prima del round 2" },
    { k = "reset_msgs", why = "messaggi del round 2" },
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "tap", btn = "D", why = "mago bianco, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "tap", btn = "R", why = "cursore: seconda casella, HARM" },
    { k = "shot", why = "SOTTOMENU MAGIA -- HARM puntata" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia HARM (colpisce TUTTI i nemici, non chiede a chi)" },
    { k = "wait", n = 30, why = "si torna alla battaglia" },
    { k = "chk", why = "HARM colpisce tutti: nessuna scelta di bersaglio", fn = function()
        report(u8(OFF_CHRSPELL + 2) == 1, string.format("incantesimo scelto = %d (atteso 1 = HARM)", u8(OFF_CHRSPELL + 2)))
        report(u8(OFF_CHRTGT + 2) == 0xFF,
            string.format("bersaglio = $%02X (atteso $FF = tutti i nemici, impegnato senza passare dal cursore)", u8(OFF_CHRTGT + 2)))
        report(u8(OFF_PHASE) == BPHASE_CMD, string.format("fase = %d (atteso CMD: il turno e' gia' passato)", u8(OFF_PHASE)))
    end },
    { k = "tap", btn = "F1", why = "mago nero: FIGHT" },
    { k = "tap", btn = "F1", why = "mago nero: conferma il bersaglio -- il round parte" },
    { k = "wait_round", why = "il round si risolve" },
    { k = "msgs", why = "il round 2" },
    { k = "chk", why = "HARM contro chi non e' non-morto", fn = function()
        report(u8(OFF_PCCAST) == 3, string.format("lanci del gruppo = %d (atteso 3)", u8(OFF_PCCAST)))
        report(u8(OFF_PCLAST) == 1 or u8(OFF_PCLAST) == 1,
            string.format("ultimo incantesimo = %d (atteso 1 = HARM)", u8(OFF_PCLAST)))
        report(chr(2, O_CURMP0) == SNAP.mp2 - 1,
            string.format("la carica si spende lo stesso: %d (era %d)", chr(2, O_CURMP0), SNAP.mp2))
        local m = saw("INEFFECTIVE")
        report(m ~= nil, "messaggio INEFFECTIVE: " .. (m or "MAI COMPARSO -- HARM avrebbe morso un vivo"))
    end },
    { k = "shot", why = "BATTAGLIA -- dopo il round 2" },
    { k = "dump", why = "alla fine" },
    { k = "done" },
}

-- =====================================================================
--  esecuzione
-- =====================================================================
local pi = 1
local phase = "boot"
local timer = 0
-- Il numero del round LETTO quando l'attesa comincia. Non un valore atteso:
-- `round_num` comincia da 1, non da zero, e aspettare "che arrivi a 1" e'
-- un'attesa gia' finita -- il primo giro di questo script leggeva i numeri 30
-- frame dopo aver premuto, cioe' prima che il round esistesse, e riportava
-- zero lanci mentre la magia funzionava benissimo. La condizione giusta e'
-- che il contatore SI MUOVA ([[mame-drive-closed-loop]]).
local wait_round_from = nil
local TAP_PRESS, TAP_REST = 10, 22   -- il menu legge FRONTI

local function advance() pi = pi + 1; timer = 0 end

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); advance(); return
    elseif a.k == "dump" then dump_party(a.why); advance(); return
    elseif a.k == "enemies" then dump_enemies(a.why); advance(); return
    elseif a.k == "msgs" then dump_messages(a.why); advance(); return
    elseif a.k == "reset_msgs" then reset_messages(); advance(); return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "snap" then
        SNAP.hp0 = chr16(0, O_CURHP)
        SNAP.mp2 = chr(2, O_CURMP0)
        SNAP.mp3 = chr(3, O_CURMP0)
        SNAP.ehp = enemy_hp_total()
        print(string.format("   [istantanea %s] HP guerriero=%d  cariche %d/%d  HP nemici=%d",
            a.why, SNAP.hp0, SNAP.mp2, SNAP.mp3, SNAP.ehp))
        advance(); return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn(); advance(); return
    elseif a.k == "vram" then
        local s = ""
        for c = a.col, a.col + #a.want - 1 do
            local t = vram:read_u8(0x1800 + a.row * 32 + c)
            s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
        end
        report(s == a.want, string.format("%s: '%s' (atteso '%s')", a.why, s, a.want))
        advance(); return
    end
    print(string.format("f=%d  %s", frames, a.why))
    if a.k == "wait_round" then wait_round_from = u16(OFF_ROUND) end
end

local function frame_action()
    local a = PLAN[pi]
    if not a then return end
    if timer == 0 and a.k ~= "tap" and a.k ~= "wait" and a.k ~= "wait_battle"
       and a.k ~= "wait_round" and a.k ~= "wait_cmd" then
        begin_action(); return
    end
    if timer == 0 then begin_action() end
    timer = timer + 1

    if a.k == "wait" then
        if timer >= a.n then advance() end
    elseif a.k == "wait_battle" then
        if in_battle() then
            print(string.format("   in battaglia @frame %d", frames))
            advance()
        elseif timer > 20000 then
            print("NESSUN ENCOUNTER ENTRO IL LIMITE"); manager.machine:exit()
        end
    elseif a.k == "wait_round" then
        -- Il round e' finito quando il contatore si e' mosso. Aspettare "tanti
        -- frame" invece funzionerebbe finche' il round non dura di piu' --
        -- cioe' finche' non si aggiunge qualcosa, che e' proprio quello che si
        -- sta facendo.
        -- Round mosso E menu tornato: la seconda meta' conta, perche' fra
        -- l'incremento del contatore e il ritorno del menu ci sono ancora
        -- disegni e attese.
        if u16(OFF_ROUND) > wait_round_from and u8(OFF_PHASE) == BPHASE_CMD then
            print(string.format("   round %d concluso @frame %d", u16(OFF_ROUND), frames))
            advance()
        elseif not in_battle() then
            report(false, "la battaglia e' finita prima del round: la prova non puo' proseguire")
            print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
            manager.machine:exit()
        elseif timer > 3000 then
            report(false, "il round non si e' concluso entro il limite")
            advance()
        end
    elseif a.k == "wait_cmd" then
        if u8(OFF_PHASE) == BPHASE_CMD and u8(OFF_CHRCHOSEN) == 0 then advance()
        elseif timer > 3000 then report(false, "il menu comandi non e' tornato"); advance() end
    elseif a.k == "tap" then
        local on = (timer <= TAP_PRESS)
        if a.btn == "F1" then fire1(on)
        elseif a.btn == "F2" then fire2(on)
        else dpad(a.btn, on) end
        if timer > TAP_PRESS + TAP_REST then release_all(); advance() end
    end
end

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if in_battle() then collect_message() end

    -- Legend + boot menu + selezione classi: fronti di FIRE1 ripetuti. Le
    -- classi le forza la build, quindi qui non si sceglie niente.
    if frames >= 700 and frames < 2200 then
        fire1((frames % 16) < 5)
        return
    elseif frames == 2200 then
        fire1(false)
        refresh_chr_size()
        print(string.format("PARTY magic=%04X (atteso %04X)  passo=%d",
            u16(PARTY_BASE), PARTY_MAGIC, CHR_SIZE))
        dump_party("all'uscita dall'intro")
        phase = "walk"
        return
    end
    if phase ~= "walk" and phase ~= "plan" then return end

    -- Si cammina finche' non parte un incontro. Fuori dalla strada, dove il
    -- bit FIGHT e' acceso, e con gambe LUNGHE: sulla strada il tiro non si fa
    -- ([[mame-drive-battle-traps]]).
    if phase == "walk" then
        if in_battle() then
            dpad("R", false); dpad("L", false)
            phase = "plan"
            print(string.format("BATTAGLIA @frame %d", frames))
            return
        end
        local cycle = 24 * 10
        local dir = ((frames % cycle) < 12 * 10) and "R" or "L"
        dpad("R", dir == "R" and (frames % 10) < 5)
        dpad("L", dir == "L" and (frames % 10) < 5)
        if frames > 20000 then
            print("NESSUN ENCOUNTER ENTRO IL LIMITE"); manager.machine:exit()
        end
        return
    end

    frame_action()
end)
