-- =====================================================================
--  mame_drive_buffs.lua -- slice70: le statistiche di battaglia
-- =====================================================================
-- Prova il blocco IB (`src/battle_ibstats.h`) e i sei effetti che ci vivono
-- sopra, nell'ordine in cui possono rompersi:
--   1. il blocco NASCE giusto -- copia di PARTY per il gruppo, copia della ROM
--      per i mostri. Se questo e' storto, tutto il resto lo e' per riflesso e
--      lo sarebbe in un modo che sembra un difetto delle formule;
--   2. FOG alza l'assorbimento di UN compagno (cursore sul gruppo);
--   3. RUSE alza l'evasione di CHI LANCIA (nessuna scelta, si impegna subito);
--   4. LOCK abbassa l'evasione di UN nemico (cursore sull'arena, banco 20);
--   5. i tre valori sono nel blocco IB e NON in PARTY: un potenziamento che
--      finisse su PARTY non scadrebbe mai, ed e' il difetto che questo blocco
--      esiste per rendere impossibile.
--
-- Le tre magie coprono i TRE modi di scegliere un bersaglio, che e' la parte
-- che si rompe piu' facilmente e la sola che il giocatore tocca con le mani.
--
-- PERCHE' SI LEGGE LA RAM. Otto punti di assorbimento non si vedono a schermo:
-- si vedono come "quel colpo ha fatto meno danno", che e' anche quello che fa
-- un tiro fortunato. Regola di sempre -- se un difetto e il funzionamento
-- corretto si somigliano a occhio, non guardare lo schermo.
--
-- ROM: build di prova con -DFORCE_BUFF (suffisso _t).
--   .\tools\build_all.ps1 -Slice slice70 -Overlays $O -Defines FORCE_BUFF
--   & mame.exe coleco -exp sgm -cart build\slice70_mc512_t.rom -rompath mame_roms `
--       -window -nofilter -skip_gameinfo -sound none -nothrottle -seconds_to_run 700 `
--       -autoboot_script tools\mame_drive_buffs.lua

local frames = 0
local fields = {}
local mem  = manager.machine.devices[":maincpu"].spaces["program"]
local vram = manager.machine.devices[":tms9928a"].spaces["vram"]

local function u8(a) return mem:read_u8(a) end
local function u16(a) return mem:read_u8(a) + mem:read_u8(a + 1) * 256 end

-- --- battle_state.h (slice70) ---------------------------------------------
local BATTLE_MAGIC  = 0xB47E
local OFF_TURN      = 0x600A
local OFF_CMD       = 0x600B
local OFF_ROUND     = 0x600C
local OFF_ENEMYTYPE = 0x6054
local OFF_ENEMYHP   = 0x605D
local OFF_PHASE     = 0x607F
local OFF_CHRCMD    = 0x6081
local OFF_CHRTGT    = 0x6085
local OFF_CHRCHOSEN = 0x6089
local OFF_CHRSPELL  = 0x60AF
local OFF_PCCAST    = 0x60B3
local OFF_ENEMYAIL  = 0x60B5
local OFF_AILSET    = 0x60BE
local OFF_BUFFSET   = 0x60C2
local OFF_BUFFLAST  = 0x60C3

local BPHASE_CMD, BPHASE_TARGET = 0, 1

-- --- battle_ibstats.h ------------------------------------------------------
-- magic (2) + chr[4] x 7 + en[9] x 7
local IB_BASE   = 0x6400
local IB_MAGIC  = 0x1B70
local IB_SIZE   = 7
local IB_CHR0   = IB_BASE + 2
local IB_EN0    = IB_CHR0 + 4 * IB_SIZE
local I_DMG, I_HITRATE, I_ABSORB, I_EVADE, I_RESIST, I_MULT, I_MORALE = 0,1,2,3,4,5,6
local function ibc(i, f) return u8(IB_CHR0 + i * IB_SIZE + f) end
local function ibe(s, f) return u8(IB_EN0  + s * IB_SIZE + f) end

-- --- party_state.h ---------------------------------------------------------
local PARTY_BASE  = 0x6100
local PARTY_MAGIC = 0x9A1A
local CHR_SIZE    = 79
local CHR0        = PARTY_BASE + 6
local O_NAME   = 2
local O_CURHP, O_MAXHP = 12, 14
local O_DMG, O_HITRATE, O_ABSORB, O_EVADE, O_RESIST = 21, 22, 23, 24, 25
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
local function in_battle() return u16(0x6000) == BATTLE_MAGIC end
local function first_live_enemy()
    for s = 0, 8 do
        if u8(OFF_ENEMYTYPE + s) ~= 0xFF and enemy_hp(s) > 0 then return s end
    end
    return -1
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

local function dump_ib(why)
    print(string.format("-- blocco IB %s (magic %04X)", why, u16(IB_BASE)))
    for i = 0, 3 do
        print(string.format("   chr%d %-6s dmg=%3d tiro=%3d abs=%3d eva=%3d res=%02X x%d   | PARTY dmg=%3d abs=%3d eva=%3d",
            i, name_of(i), ibc(i, I_DMG), ibc(i, I_HITRATE), ibc(i, I_ABSORB),
            ibc(i, I_EVADE), ibc(i, I_RESIST), ibc(i, I_MULT),
            chr(i, O_DMG), chr(i, O_ABSORB), chr(i, O_EVADE)))
    end
    for s = 0, 8 do
        if u8(OFF_ENEMYTYPE + s) ~= 0xFF then
            print(string.format("   en%d  dmg=%3d abs=%3d eva=%3d res=%02X mor=%3d x%d  hp=%d",
                s, ibe(s, I_DMG), ibe(s, I_ABSORB), ibe(s, I_EVADE),
                ibe(s, I_RESIST), ibe(s, I_MORALE), ibe(s, I_MULT), enemy_hp(s)))
        end
    end
end

-- =====================================================================
--  il piano
-- =====================================================================
local SNAP = {}

local PLAN = {
    { k = "wait_battle", why = "si entra in battaglia" },
    { k = "wait", n = 90, why = "la schermata si disegna" },
    { k = "shot", why = "BATTAGLIA -- prima di ogni potenziamento" },
    { k = "ib", why = "appena nato" },

    -- ---------- 1. il blocco nasce giusto ----------
    { k = "chk", why = "il blocco IB e' nato, e nasce da PARTY e dalla ROM", fn = function()
        report(u16(IB_BASE) == IB_MAGIC,
            string.format("magic del blocco = %04X (atteso %04X)", u16(IB_BASE), IB_MAGIC))
        -- Il confronto con PARTY vale doppio: dice che i valori sono giusti E
        -- che la disposizione dei campi che lo script assume e' quella vera.
        -- Un offset sbagliato darebbe numeri plausibili e nessun errore.
        for i = 0, 3 do
            report(ibc(i, I_DMG) == chr(i, O_DMG) and ibc(i, I_EVADE) == chr(i, O_EVADE),
                string.format("chr%d: IB dmg/eva = %d/%d, PARTY = %d/%d",
                    i, ibc(i, I_DMG), ibc(i, I_EVADE), chr(i, O_DMG), chr(i, O_EVADE)))
        end
        local s = first_live_enemy()
        report(s >= 0 and ibe(s, I_MORALE) > 0,
            string.format("il morale del mostro %d e' arrivato dalla ROM: %d", s, s >= 0 and ibe(s, I_MORALE) or -1))
        report(ibc(0, I_MULT) == 1 and (s < 0 or ibe(s, I_MULT) == 1),
            "il moltiplicatore dei colpi parte da 1 dalle due parti")
    end },
    { k = "snap", why = "prima del round 1" },
    { k = "reset_msgs", why = "messaggi del round 1" },

    -- ---------- 2. FOG su UN compagno ----------
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "tap", btn = "D", why = "mago bianco, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "vram", row = 17, col = 0, want = "L19/9 >FOG   RUSE  ----",
      why = "la riga del livello 1 del mago bianco" },
    { k = "shot", why = "SOTTOMENU MAGIA -- FOG e RUSE" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia FOG (chiede a chi)" },
    { k = "wait", n = 20, why = "compare il cursore sul gruppo" },
    { k = "tap", btn = "U", why = "cursore: al monaco" },
    { k = "tap", btn = "U", why = "cursore: al guerriero" },
    { k = "tap", btn = "F1", why = "FIRE1: FOG al guerriero" },
    { k = "wait", n = 30, why = "si torna nell'overlay di battaglia" },
    { k = "chk", why = "FOG e' impegnata sul guerriero", fn = function()
        report(in_battle(), "il blocco di battaglia c'e' ancora")
        report(u8(OFF_CHRSPELL + 2) == 2,
            string.format("incantesimo scelto = %d (atteso 2 = FOG)", u8(OFF_CHRSPELL + 2)))
        report(u8(OFF_CHRTGT + 2) == 0x80,
            string.format("bersaglio = $%02X (atteso $80 = il guerriero)", u8(OFF_CHRTGT + 2)))
    end },

    -- ---------- 4. LOCK su UN nemico ----------
    { k = "tap", btn = "D", why = "mago nero, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "vram", row = 17, col = 0, want = "L19/9 >LOCK  ----  ----",
      why = "la riga del livello 1 del mago nero" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia LOCK" },
    { k = "wait", n = 25, why = "si torna alla battaglia per scegliere il nemico" },
    { k = "chk", why = "LOCK vuole UN nemico, e a sceglierlo e' la battaglia", fn = function()
        report(u8(OFF_PHASE) == BPHASE_TARGET,
            string.format("fase = %d (atteso TARGET)", u8(OFF_PHASE)))
        report(u8(OFF_CHRSPELL + 3) == 6,
            string.format("incantesimo scelto = %d (atteso 6 = LOCK)", u8(OFF_CHRSPELL + 3)))
        SNAP.lock_slot = u8(0x6080)   -- cursor_tgt
        SNAP.lock_eva  = ibe(SNAP.lock_slot, I_EVADE)
        print(string.format("   [istantanea] LOCK punta lo slot %d, evasione %d",
            SNAP.lock_slot, SNAP.lock_eva))
    end },
    { k = "tap", btn = "F1", why = "FIRE1: conferma il nemico -- e il round parte" },
    { k = "wait_round", why = "il round 1 si risolve" },
    { k = "ib", why = "dopo il round 1" },
    { k = "msgs", why = "il round 1" },

    { k = "chk", why = "FOG e LOCK hanno mosso il blocco IB", fn = function()
        -- FOG: effectivity 8, assorbimento del guerriero da 0 a 8.
        report(ibc(0, I_ABSORB) == SNAP.abs0 + 8,
            string.format("assorbimento del guerriero = %d (era %d, FOG ne da' 8)",
                ibc(0, I_ABSORB), SNAP.abs0))
        -- E NON in PARTY: e' tutto il senso del blocco.
        report(chr(0, O_ABSORB) == SNAP.abs0,
            string.format("in PARTY invece e' rimasto %d: il potenziamento MUORE con la battaglia",
                chr(0, O_ABSORB)))
        report(saw("CASTS FOG") ~= nil, "messaggio di FOG: " .. (saw("CASTS FOG") or "MAI COMPARSO"))
        -- LOCK: effectivity 20 sull'evasione di un IMP, che ne ha 6 -> a zero.
        -- Si cerca su TUTTI gli slot: vedi la nota sull'istantanea.
        local hit_slot, hit_from, hit_to = -1, 0, 0
        for s = 0, 8 do
            if ibe(s, I_EVADE) < SNAP.eva_en[s] then
                hit_slot = s; hit_from = SNAP.eva_en[s]; hit_to = ibe(s, I_EVADE)
            end
        end
        report(hit_slot >= 0,
            string.format("un mostro ha l'evasione abbassata: slot %d, da %d a %d (LOCK ne toglie 20, l'IMP ne ha 6)",
                hit_slot, hit_from, hit_to))
        report(saw("CASTS LOCK") ~= nil, "messaggio di LOCK: " .. (saw("CASTS LOCK") or "MAI COMPARSO"))
        report(u8(OFF_BUFFSET) >= 2,
            string.format("effetti sulle statistiche andati a segno = %d (attesi almeno 2)", u8(OFF_BUFFSET)))
    end },
    { k = "shot", why = "BATTAGLIA -- dopo il round 1" },

    -- ---------- 3. RUSE su CHI LANCIA ----------
    { k = "wait_cmd", why = "il round 2 comincia" },
    { k = "snap2", why = "prima del round 2" },
    { k = "reset_msgs", why = "messaggi del round 2" },
    { k = "tap", btn = "F1", why = "guerriero: FIGHT" },
    { k = "tap", btn = "F1", why = "guerriero: conferma il bersaglio" },
    { k = "tap", btn = "F1", why = "monaco: FIGHT" },
    { k = "tap", btn = "F1", why = "monaco: conferma il bersaglio" },
    { k = "tap", btn = "D", why = "mago bianco, cursore comandi: MAGIC" },
    { k = "tap", btn = "F1", why = "FIRE1: sottomenu" },
    { k = "wait", n = 20, why = "il sottomenu si disegna" },
    { k = "tap", btn = "R", why = "cursore: seconda casella, RUSE" },
    { k = "tap", btn = "F1", why = "FIRE1: lancia RUSE -- bersaglia CHI LANCIA, nessuna scelta" },
    { k = "wait", n = 30, why = "si torna alla battaglia" },
    { k = "chk", why = "RUSE si impegna da sola, senza cursore", fn = function()
        report(u8(OFF_CHRSPELL + 2) == 3,
            string.format("incantesimo scelto = %d (atteso 3 = RUSE)", u8(OFF_CHRSPELL + 2)))
        report(u8(OFF_CHRTGT + 2) == 0x82,
            string.format("bersaglio = $%02X (atteso $82 = chi lancia, il mago bianco)", u8(OFF_CHRTGT + 2)))
        report(u8(OFF_PHASE) == BPHASE_CMD,
            string.format("fase = %d (atteso CMD: il turno e' gia' passato)", u8(OFF_PHASE)))
    end },
    { k = "tap", btn = "F1", why = "mago nero: FIGHT" },
    { k = "tap", btn = "F1", why = "mago nero: conferma -- il round parte" },
    { k = "wait_round", why = "il round 2 si risolve" },
    { k = "ib", why = "dopo il round 2" },
    { k = "msgs", why = "il round 2" },
    { k = "chk", why = "RUSE ha alzato l'evasione di chi l'ha lanciata", fn = function()
        -- RUSE: effectivity $50 = 80. Il mago bianco parte da 53.
        report(ibc(2, I_EVADE) == SNAP.eva2 + 80,
            string.format("evasione del mago bianco = %d (era %d, RUSE ne da' 80)",
                ibc(2, I_EVADE), SNAP.eva2))
        report(chr(2, O_EVADE) == SNAP.eva2,
            string.format("in PARTY invece e' rimasta %d", chr(2, O_EVADE)))
        report(saw("CASTS RUSE") ~= nil, "messaggio di RUSE: " .. (saw("CASTS RUSE") or "MAI COMPARSO"))
        -- Il guerriero ha ancora la sua FOG: i potenziamenti si accumulano
        -- lungo la battaglia, ed e' l'altra meta' del motivo per cui servono.
        report(ibc(0, I_ABSORB) == SNAP.abs0 + 8,
            string.format("il FOG del round scorso c'e' ancora: assorbimento %d", ibc(0, I_ABSORB)))
    end },
    { k = "shot", why = "BATTAGLIA -- dopo il round 2" },
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
    elseif a.k == "ib" then dump_ib(a.why); advance(); return
    elseif a.k == "msgs" then dump_messages(a.why); advance(); return
    elseif a.k == "reset_msgs" then reset_messages(); advance(); return
    elseif a.k == "done" then
        print(string.format("RIEPILOGO: %d ok, %d falliti", ok_count, fail_count))
        manager.machine:exit(); return
    elseif a.k == "snap" then
        SNAP.abs0 = ibc(0, I_ABSORB)
        SNAP.eva2 = ibc(2, I_EVADE)
        -- L'evasione di TUTTI gli slot, non solo di quello puntato: il mostro
        -- scelto puo' morire sotto i colpi di un compagno prima che il mago
        -- arrivi al proprio turno, e allora il bersaglio si sposta sul primo
        -- vivo (regola di slice68, e giusta). Fissare uno slot vorrebbe dire
        -- una prova che fallisce quando il gioco funziona -- ed e' esattamente
        -- quello che ha fatto al primo giro.
        SNAP.eva_en = {}
        for s = 0, 8 do SNAP.eva_en[s] = ibe(s, I_EVADE) end
        print(string.format("   [istantanea %s] assorbimento guerriero=%d  evasione mago bianco=%d",
            a.why, SNAP.abs0, SNAP.eva2))
        advance(); return
    elseif a.k == "snap2" then
        print(string.format("   [istantanea %s] assorbimento guerriero=%d  evasione mago bianco=%d",
            a.why, ibc(0, I_ABSORB), ibc(2, I_EVADE)))
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
