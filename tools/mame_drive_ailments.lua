-- =====================================================================
--  mame_drive_ailments.lua -- slice69: le alterazioni di stato
-- =====================================================================
-- Prova le cinque cose che slice69 aggiunge, e le prova nell'ordine in cui
-- possono rompersi:
--   1. le alterazioni SEMINATE arrivano in battaglia e si VEDONO nella
--      striscia di stato (veleno al guerriero, cecita' al monaco);
--   2. un incantesimo ne TOGLIE una -- LAMP sul monaco;
--   3. un incantesimo ne METTE una -- SLEP sui mostri, che e' il primo caso in
--      cui la magia del gruppo fa qualcosa di diverso dal danno;
--   4. chi dorme PERDE il turno e tira per svegliarsi;
--   5. il VELENO gratta due HP a fine di ogni round.
--
-- PERCHE' TRE DI QUESTE CINQUE SI LEGGONO DALLA RAM E NON DALLO SCHERMO
-- Un mostro che si addormenta e si sveglia nel proprio turno dello stesso
-- round non lascia niente dietro di se': a fine round `enemy_ail` e' zero
-- tanto se SLEP ha preso quanto se non e' mai partita. E due HP in meno a fine
-- round sono anche quello che fa un colpo andato a segno. Percio' il gioco
-- pubblica quattro contatori (`ail_set`, `ail_last`, `ail_turns`,
-- `ail_poison`) e qui si affermano quelli -- [[vram-readback-probe]] e la
-- regola "se un difetto e il funzionamento corretto si somigliano a occhio,
-- non guardare lo schermo".
-- Cio' che invece SI GUARDA a schermo e' la striscia di stato, perche' li' la
-- prova E' la posizione: [[slice66-shop-buying]] insegna che una parola giusta
-- scritta nella riga sbagliata e' un difetto che nessun controllo di RAM vede.
--
-- ROM: build di prova con -DFORCE_AIL (suffisso _t).
--   .\tools\build_all.ps1 -Slice slice69 -Overlays $O -Defines FORCE_AIL
--   & mame.exe coleco -exp sgm -cart build\slice69_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 700 `
--       -autoboot_script tools\mame_drive_ailments.lua

local frames = 0
local fields = {}
local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end

-- --- battle_state.h, offset calcolati sulla struct (slice69) ---------------
local BATTLE_MAGIC  = 0xB47E
local OFF_TURN      = 0x600A
local OFF_CMD       = 0x600B
local OFF_ROUND     = 0x600C
local OFF_NENEMIES  = 0x6053
local OFF_ENEMYTYPE = 0x6054   -- 9
local OFF_ENEMYHP   = 0x605D   -- 9 x 2
local OFF_PHASE     = 0x607F
local OFF_CHRCMD    = 0x6081   -- 4
local OFF_CHRTGT    = 0x6085   -- 4
local OFF_CHRCHOSEN = 0x6089   -- 4
local OFF_CHRSPELL  = 0x60AF   -- 4
local OFF_PCCAST    = 0x60B3
local OFF_PCLAST    = 0x60B4
-- slice69, in coda: enemy_ail[9] e le quattro sonde.
local OFF_ENEMYAIL  = 0x60B5   -- 9
local OFF_AILSET    = 0x60BE
local OFF_AILLAST   = 0x60BF
local OFF_AILTURNS  = 0x60C0
local OFF_AILPOISON = 0x60C1

local BPHASE_CMD, BPHASE_TARGET = 0, 1

-- --- party_state.h ---------------------------------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_CLS, O_AIL, O_NAME = 0, 1, 2
local O_CURHP, O_MAXHP = 12, 14
local O_CURMP0 = 28
local O_SPELLS = 55

-- Le maschere di party_state.h.
local AIL_DEAD, AIL_STONE, AIL_POISON = 0x01, 0x02, 0x04
local AIL_DARK, AIL_STUN, AIL_SLEEP   = 0x08, 0x10, 0x20

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
local function in_battle() return u16(0x6000) == BATTLE_MAGIC end

-- Quanti mostri portano ADESSO una certa alterazione.
local function enemies_with(mask)
    local n = 0
    for s = 0, 8 do
        if u8(OFF_ENEMYTYPE + s) ~= 0xFF and enemy_hp(s) > 0 then
            local a = u8(OFF_ENEMYAIL + s)
            if (a % (mask * 2)) >= mask then n = n + 1 end
        end
    end
    return n
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
local seen_msgs, seen_list = {}, {}
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
local function reset_messages() seen_msgs = {}; seen_list = {} end

local function vram_str(row, col, n)
    local s = ""
    for c = col, col + n - 1 do
        local t = vram:read_u8(0x1800 + row * 32 + c)
        s = s .. ((t >= 0x20 and t < 0x7F) and string.char(t) or ".")
    end
    return s
end

local function dump_party(why)
    print(string.format("-- %s", why))
    for i = 0, u8(PARTY_BASE + 2) - 1 do
        print(string.format("   %d %-6s HP %3d/%3d  ail=$%02X  striscia='%s'",
            i + 1, name_of(i), chr16(i, O_CURHP), chr16(i, O_MAXHP),
            chr(i, O_AIL), vram_str(i * 4 + 3, 25, 7)))
    end
end
local function dump_sondes(why)
    local e = {}
    for s = 0, 8 do
        if u8(OFF_ENEMYTYPE + s) ~= 0xFF then
            e[#e + 1] = string.format("s%d:hp%d/ail$%02X", s, enemy_hp(s), u8(OFF_ENEMYAIL + s))
        end
    end
    print(string.format("   [sonde %s] ail_set=%d ail_last=$%02X ail_turns=%d ail_poison=%d | %s",
        why, u8(OFF_AILSET), u8(OFF_AILLAST), u8(OFF_AILTURNS), u8(OFF_AILPOISON),
        table.concat(e, " ")))
end

-- =====================================================================
--  il piano
-- =====================================================================
local SNAP = {}

local PLAN = {
    { k = "wait_battle", why = "si entra in battaglia" },
    { k = "wait", n = 90, why = "la schermata si disegna" },
    { k = "shot", why = "BATTAGLIA -- il gruppo entra avvelenato e cieco" },

    -- ---------- 1. le alterazioni seminate ci sono e SI VEDONO ----------
    { k = "chk", why = "il gruppo della build di prova", fn = function()
        report(chr(0, O_AIL) == AIL_POISON,
            string.format("guerriero: ail=$%02X (atteso $04 = veleno)", chr(0, O_AIL)))
        report(chr(1, O_AIL) == AIL_DARK,
            string.format("monaco: ail=$%02X (atteso $08 = cecita')", chr(1, O_AIL)))
        report(chr(3, O_SPELLS) == 6,
            string.format("magia L1 del mago nero = %d (atteso 6 = SLEP)", chr(3, O_SPELLS)))
        report(chr(2, O_SPELLS + 3) == 1,
            string.format("magia L2 del mago bianco = %d (atteso 1 = LAMP)", chr(2, O_SPELLS + 3)))
    end },
    -- La striscia si AFFERMA, non si fotografa: una parola giusta sulla riga
    -- sbagliata e' un difetto che nessuna lettura di RAM vede.
    { k = "vram", row = 3, col = 25, want = "POISON ", why = "riga 4 del blocco del guerriero" },
    { k = "vram", row = 7, col = 25, want = "DARK   ", why = "riga 4 del blocco del monaco" },
    { k = "vram", row = 11, col = 25, want = "       ", why = "il mago bianco non ha niente addosso" },
    -- I due riquadri in basso da slice69 sono DISEGNATI e non piu' scritti come
    -- stringhe letterali. La prima versione ne riempiva tre colonne invece di
    -- tredici -- `ov_fill_row` vuole la colonna FINALE, non un conteggio -- e la
    -- cosa era invisibile nel riquadro di sinistra, che parte da colonna 0 e
    -- quindi vede i due numeri coincidere. Da qui in poi si afferma la cornice.
    { k = "vram", row = 16, col = 0,  want = "+--------++-------------+",
      why = "il bordo superiore dei due riquadri" },
    { k = "vram", row = 21, col = 0,  want = "+--------++-------------+",
      why = "il bordo inferiore dei due riquadri" },
    { k = "snap", why = "prima del round 1" },
    { k = "reset_msgs", why = "messaggi del round 1" },

    -- ---------- 2. LAMP toglie la cecita' al monaco ----------
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "tap", btn = "D", why = "mago bianco, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "tap", btn = "D", why = "cursore: dal livello 1 al livello 2" },
    { k = "wait", n = 15, why = "la pagina si ridisegna" },
    { k = "vram", row = 18, col = 0, want = "L29/9 >LAMP  ----  ----",
      why = "la riga del livello 2 del mago bianco" },
    { k = "shot", why = "SOTTOMENU MAGIA -- LAMP al livello 2" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia LAMP (chiede a chi)" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "U", why = "cursore: dal mago bianco al monaco, che e' cieco" },
    { k = "tap", btn = "F1", why = "FIRE1: al monaco" },
    { k = "wait", n = 30, why = "si torna nell'overlay di battaglia" },
    { k = "chk", why = "la scelta di LAMP e' impegnata", fn = function()
        report(in_battle(), "il blocco di battaglia c'e' ancora (l'annidamento e' tornato a posto)")
        report(u8(OFF_CHRSPELL + 2) == 8,
            string.format("incantesimo scelto = %d (atteso 8 = LAMP: livello 2, prima casella)", u8(OFF_CHRSPELL + 2)))
        report(u8(OFF_CHRTGT + 2) == 0x81,
            string.format("bersaglio = $%02X (atteso $81 = personaggio 1, il monaco)", u8(OFF_CHRTGT + 2)))
    end },

    -- ---------- 3. SLEP mette il sonno addosso ai mostri ----------
    { k = "tap", btn = "D", why = "mago nero, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "vram", row = 17, col = 0, want = "L19/9 >SLEP  ----  ----",
      why = "la riga del livello 1 del mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia SLEP -- colpisce TUTTI, non chiede a chi" },
    { k = "wait", n = 30, why = "si torna alla battaglia" },
    { k = "chk", why = "SLEP non passa dal cursore: bersaglio gia' deciso", fn = function()
        report(u8(OFF_CHRSPELL + 3) == 5,
            string.format("incantesimo scelto = %d (atteso 5 = SLEP)", u8(OFF_CHRSPELL + 3)))
        report(u8(OFF_CHRTGT + 3) == 0xFF,
            string.format("bersaglio = $%02X (atteso $FF = tutti i mostri)", u8(OFF_CHRTGT + 3)))
    end },
    { k = "wait_round", why = "il round 1 si risolve" },
    { k = "sonde", why = "dopo il round 1" },
    { k = "msgs", why = "il round 1" },

    { k = "chk", why = "il primo round: cura, sonno, veleno", fn = function()
        -- 2. LAMP
        report(chr(1, O_AIL) == 0,
            string.format("il monaco ci vede di nuovo: ail=$%02X (atteso $00)", chr(1, O_AIL)))
        report(saw("CASTS LAMP") ~= nil, "messaggio di LAMP: " .. (saw("CASTS LAMP") or "MAI COMPARSO"))
        -- 3. SLEP. Si guarda il CONTATORE, non lo stato: chi si e' addormentato
        -- puo' essersi gia' svegliato nel proprio turno dello stesso round.
        report(u8(OFF_AILSET) >= 1,
            string.format("alterazioni andate a segno = %d (attesa almeno 1: SLEP su 148+64+5-16 = quasi sempre)", u8(OFF_AILSET)))
        report(u8(OFF_AILLAST) == AIL_SLEEP,
            string.format("ultima maschera applicata = $%02X (attesa $20 = sonno)", u8(OFF_AILLAST)))
        report(saw("CASTS SLEP") ~= nil, "messaggio di SLEP: " .. (saw("CASTS SLEP") or "MAI COMPARSO"))
        -- I turni persi NON si controllano qui, ed e' una lezione della prima
        -- corsa: il mago nero e' l'ULTIMO a scegliere, quindi SLEP parte in
        -- fondo alla coda del round e i mostri hanno gia' agito. Chiedere qui
        -- "qualcuno ha perso il turno" fallisce mentre il gioco funziona --
        -- l'effetto comincia nel round DOPO, ed e' li' che va guardato.
        -- 5. veleno
        report(u8(OFF_AILPOISON) == 2,
            string.format("HP tolti dal veleno = %d (attesi 2: un avvelenato, un round)", u8(OFF_AILPOISON)))
    end },
    { k = "vram", row = 7, col = 25, want = "       ", why = "la striscia del monaco si e' ripulita" },
    { k = "vram", row = 3, col = 25, want = "POISON ", why = "il veleno del guerriero e' ancora li'" },
    { k = "shot", why = "BATTAGLIA -- dopo il round 1" },
    { k = "dump", why = "dopo il round 1" },

    -- ---------- il round 2: il veleno gratta di nuovo ----------
    { k = "wait_cmd", why = "il round 2 comincia" },
    { k = "reset_msgs", why = "messaggi del round 2" },
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "mago bianco: FIGHT" },
    { k = "tap", btn = "F1", why = "mago bianco: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "mago nero: FIGHT" },
    { k = "tap", btn = "F1", why = "mago nero: conferma -- il round parte" },
    { k = "wait_round", why = "il round 2 si risolve" },
    { k = "sonde", why = "dopo il round 2" },
    { k = "chk", why = "il round 2: chi dorme non agisce, e il veleno gratta ancora", fn = function()
        -- 4. IL SONNO COSTA IL TURNO. Il contatore si muove adesso perche' e'
        -- adesso che i dormienti hanno il loro turno: SLEP era partita in fondo
        -- al round 1.
        report(u8(OFF_AILTURNS) >= 1,
            string.format("turni persi per sonno = %d (atteso almeno 1: i mostri addormentati nel round 1)", u8(OFF_AILTURNS)))
        local m = saw("SLEEPING") or saw("WOKE UP")
        report(m ~= nil, "messaggio del dormiente: " .. (m or "MAI COMPARSO"))
        -- FIX #14 OSSERVATO. Sul NES un mostro addormentato si sveglia SEMPRE
        -- al primo turno, per un ramo rotto in tre punti (bank_0C.asm:6710).
        -- Qui vale il tiro dei personaggi -- si sveglia se maxHP > rand[0,80] --
        -- e un IMP ha 8 HP massimi, cioe' meno di una possibilita' su dieci per
        -- turno. Se il difetto del NES fosse stato ricopiato, a questo punto
        -- dormirebbero ZERO mostri.
        report(enemies_with(AIL_SLEEP) >= 1,
            string.format("mostri ancora addormentati = %d (con 8 HP massimi il risveglio e' ~1 su 10: col difetto NES sarebbero 0)",
                enemies_with(AIL_SLEEP)))
        -- 5. veleno
        report(u8(OFF_AILPOISON) == 4,
            string.format("HP tolti dal veleno = %d (attesi 4: due round di fila)", u8(OFF_AILPOISON)))
        report(chr(0, O_AIL) == AIL_POISON or chr(0, O_AIL) == (AIL_POISON + AIL_DEAD),
            string.format("il veleno non se ne va da solo: ail=$%02X", chr(0, O_AIL)))
    end },
    { k = "shot", why = "BATTAGLIA -- dopo il round 2" },
    { k = "dump", why = "alla fine" },
    { k = "msgs", why = "il round 2" },
    { k = "done" },
}

-- =====================================================================
--  esecuzione
-- =====================================================================
local pi = 1
local phase = "boot"
local timer = 0
local wait_round_from = nil
local TAP_PRESS, TAP_REST = 10, 22

local function advance() pi = pi + 1; timer = 0 end

local function begin_action()
    local a = PLAN[pi]
    if not a then return end
    if a.k == "shot" then shot(a.why); advance(); return
    elseif a.k == "dump" then dump_party(a.why); advance(); return
    elseif a.k == "sonde" then dump_sondes(a.why); advance(); return
    elseif a.k == "msgs" then dump_messages(a.why); advance(); return
    elseif a.k == "reset_msgs" then reset_messages(); advance(); return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "snap" then
        SNAP.hp0 = chr16(0, O_CURHP)
        SNAP.ehp = 0
        for s = 0, 8 do SNAP.ehp = SNAP.ehp + enemy_hp(s) end
        print(string.format("   [istantanea %s] HP guerriero=%d  HP mostri=%d  mostri=%d",
            a.why, SNAP.hp0, SNAP.ehp, u8(OFF_NENEMIES)))
        advance(); return
    elseif a.k == "chk" then
        print(string.format("f=%d  PROVA: %s", frames, a.why))
        a.fn(); advance(); return
    elseif a.k == "vram" then
        local s = vram_str(a.row, a.col, #a.want)
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
        if u16(OFF_ROUND) > wait_round_from and u8(OFF_PHASE) == BPHASE_CMD then
            print(string.format("   round %d concluso @frame %d", u16(OFF_ROUND), frames))
            advance()
        elseif not in_battle() then
            report(false, "la battaglia e' finita prima del round: la prova non puo' proseguire")
            print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
            manager.machine:exit()
        elseif timer > 4000 then
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
