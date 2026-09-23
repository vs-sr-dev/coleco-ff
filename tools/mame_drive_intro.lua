-- mame_drive_intro.lua -- guida e verifica le scene di APERTURA, che da
-- slice62 non stanno piu' nella finestra fissa ma nell'overlay del banco 21.
--
-- PERCHE' UNO SCRIPT SUO. mame_drive.lua attraversa l'intro a pulsantate
-- cieche e fotografa solo l'overworld: se la legenda uscisse vuota o le
-- classi arrivassero storte, arriverebbe lo stesso in overworld e lo scatto
-- sarebbe identico. Qui l'intro e' il soggetto, non l'ostacolo.
--
-- LE DUE COSE CHE NON SI VEDONO A SCHERMO, e che quindi si leggono in RAM:
--
--  1. main_bank durante la scena. Se vale 21, il codice che sta girando e'
--     davvero quello dell'overlay; se valesse 1, vorrebbe dire che il salto
--     non e' avvenuto e stiamo guardando la vecchia scena della finestra
--     fissa -- che a schermo e' IDENTICA, essendo lo stesso disegno.
--
--  2. Le classi scelte. La schermata di selezione le mostra, ma cio' che
--     conta e' che arrivino a PARTY ($6100) attraverso il valore di ritorno
--     impacchettato. Un impacchettamento sbagliato darebbe una schermata
--     giusta e un gruppo storto.
--
-- E una terza, a meta' strada: audio_enabled/audio_bank dicono se il Prelude
-- ha continuato a suonare per tutta la scena, cosa che con -sound none non si
-- puo' sentire.

local snapdir = os.getenv("INTRO_SNAPS")

local frames = 0
local fields = {}
local probe = dofile("build/probe_addrs.lua")

local cpu  = manager.machine.devices[":maincpu"]
local mem  = cpu.spaces["program"]
local function u8(a)  return mem:read_u8(a) end
local function u16(a) return mem:read_u16(a) end

local function find_port_field(port_name, field_name)
    local key = port_name .. "//" .. field_name
    if fields[key] then return fields[key] end
    -- Per PORTA e nome, mai per solo nome: "P1 Button 1" esiste in piu' porte
    -- e iterare con pairs() ha ordine imprevedibile. E' la trappola numero
    -- uno di mame_drive_battle.lua, ricopiata qui apposta.
    local port = manager.machine.ioport.ports[port_name]
    if not port then error("porta non trovata: " .. port_name) end
    local f = port.fields[field_name]
    if not f then error("campo non trovato: " .. port_name .. " " .. field_name) end
    fields[key] = f
    return f
end

-- FIRE1 del gioco = "P1 Button 2" di :STD_KEYPAD1 (sono invertiti rispetto ai
-- nomi MAME, verificato sul campo in slice52).
local function fire1(on) find_port_field(":STD_KEYPAD1", "P1 Button 2"):set_value(on and 1 or 0) end
local function dpad(name, on) find_port_field(":STD_JOY1", name):set_value(on and 1 or 0) end

local function shot(label)
    print(string.format("SNAP (%s) @frame %d", label, frames))
    manager.machine.video:snapshot()
end

local function banks()
    return string.format("main_bank=%d audio on=%d bank=%d",
        u8(probe.main_bank), u8(probe.audio_enabled), u8(probe.audio_bank))
end

local CLS = {[0]="FT","TH","BB","RM","WM","BM"}
local function dump_party()
    local PARTY_BASE, PARTY_MAGIC = 0x6100, 0x9A1A
    -- IL PASSO LO DICE IL GIOCO, non questo file. Era cablato a 44; con
    -- l'equipaggiamento di slice65 e' 79, e un numero cablato che cambia nel
    -- gioco e non qui e' la trappola numero 1 del catalogo. Il ripiego serve
    -- solo se la sonda manca, e si fa sentire.
    local CHR_SIZE = 79
    if probe.party_chr_size then
        local v = u8(probe.party_chr_size)
        if v ~= 0 then CHR_SIZE = v end
    else
        print("!! SONDA party_chr_size MANCANTE: uso il ripiego " .. CHR_SIZE)
    end
    local CHR0 = PARTY_BASE + 6
    local m = u16(PARTY_BASE)
    print(string.format("PARTY magic=%04X (atteso %04X)  n=%d  passo=%d", m, PARTY_MAGIC, u8(PARTY_BASE + 2), CHR_SIZE))
    if m ~= PARTY_MAGIC then print("  !! magic sbagliato: layout disallineato, i campi sotto non valgono") end
    for i = 0, 3 do
        local b = CHR0 + i * CHR_SIZE
        local cls = u8(b)
        local nm = ""
        for k = 0, 5 do
            local c = u8(b + 2 + k)
            if c == 0 then break end
            nm = nm .. string.char(c)
        end
        print(string.format("  CHR%d %-6s cls=%d(%s) HP=%3d STR=%2d INT=%2d",
              i + 1, nm, cls, CLS[cls] or "??", u16(b + 12), u8(b + 16), u8(b + 18)))
    end
end

-- COREOGRAFIA. La legenda sono 13 righe da ~30 frame = ~390 frame dopo il
-- boot, poi aspetta un fronte di FIRE1. Il menu parte su NEW GAME.
-- Nella selezione si cambiano DAVVERO le classi, invece di accettare le
-- predefinite: se si confermasse e basta, il gruppo in RAM sarebbe FT/TH/WM/BM
-- sia con l'impacchettamento giusto sia con `party_class[]` mai riscritto --
-- cioe' il test passerebbe anche se il valore di ritorno andasse perduto.
-- Scelta: CHR1 +1 (FT->TH), CHR2 +2 (TH->RM), CHR3 invariato (WM), CHR4 +1
-- (BM->FT, cioe' il giro completo).
local SEQ = {}
local function at(f, fn) SEQ[f] = fn end

at(200,  function() shot("legenda, prime righe") end)
at(560,  function() shot("legenda completa") end)
-- fronte di FIRE1 per uscire dalla legenda
at(600,  function() fire1(true) end)
at(606,  function() fire1(false) end)
at(640,  function() shot("menu di boot") print("  " .. banks()) end)
-- DOWN due volte: NEW GAME -> RESPOND RATE -> (wrap) CONTINUE
at(660,  function() dpad("P1 Down", true) end)
at(666,  function() dpad("P1 Down", false) end)
at(700,  function() shot("menu, cursore su RESPOND RATE") end)
-- FIRE1 sul respond rate: cicla 1 -> 2
at(720,  function() fire1(true) end)
at(726,  function() fire1(false) end)
at(760,  function() shot("respond rate a 2") end)
-- risalgo a NEW GAME e confermo
at(780,  function() dpad("P1 Up", true) end)
at(786,  function() dpad("P1 Up", false) end)
at(820,  function() fire1(true) end)
at(826,  function() fire1(false) end)
at(880,  function() shot("selezione personaggi") print("  " .. banks()) end)

-- CHR1: un giro di D-pad (FT -> TH), poi conferma
at(900,  function() dpad("P1 Right", true) end)
at(906,  function() dpad("P1 Right", false) end)
at(940,  function() fire1(true) end)
at(946,  function() fire1(false) end)
-- CHR2: due giri (TH -> BB -> RM), poi conferma
at(980,  function() dpad("P1 Right", true) end)
at(986,  function() dpad("P1 Right", false) end)
at(1010, function() dpad("P1 Right", true) end)
at(1016, function() dpad("P1 Right", false) end)
at(1050, function() shot("CHR1=THIEF CHR2=RED MAGE") end)
at(1070, function() fire1(true) end)
at(1076, function() fire1(false) end)
-- CHR3: invariato, conferma soltanto
at(1110, function() fire1(true) end)
at(1116, function() fire1(false) end)
-- CHR4: un giro (BM -> FT), poi la quarta conferma che chiude la scena
at(1150, function() dpad("P1 Right", true) end)
at(1156, function() dpad("P1 Right", false) end)
at(1190, function() shot("tutte e quattro scelte") print("  " .. banks()) end)
at(1210, function() fire1(true) end)
at(1216, function() fire1(false) end)

at(1400, function()
    shot("overworld dopo la consegna")
    print("  " .. banks())
    print("ATTESO: CHR1=TH CHR2=RM CHR3=WM CHR4=FT")
    dump_party()
end)
at(1450, function() manager.machine:exit() end)

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    local fn = SEQ[frames]
    if fn then fn() end
end)
