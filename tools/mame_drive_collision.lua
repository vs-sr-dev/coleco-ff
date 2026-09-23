-- mame_drive_collision.lua -- verifica la collisione in overworld (slice58)
--
-- Coneria sta su una penisola: sud, ovest ed est sono mare, nord e' terra.
-- Il test e' in due tempi, e servono entrambi:
--   1. cammina verso il MARE  -> lo schermo NON deve cambiare
--   2. cammina verso la TERRA -> lo schermo DEVE cambiare
-- Senza il secondo, un controllo di collisione che blocca TUTTO passerebbe la
-- prima meta' e nessuno se ne accorgerebbe.
--
-- PERCHE' SI CONFRONTANO LE IMMAGINI E NON LA POSIZIONE
-- world_player_mx/my sono variabili LOCALI di main(), quindi non hanno un
-- simbolo nella .map e non si possono sondare. Il confronto avviene allora fra
-- due PNG, ed e' valido a una condizione: la baseline va presa DOPO che il
-- personaggio si e' gia' girato verso la direzione di prova. Se la si prendesse
-- prima, i due scatti differirebbero per il verso della sprite anche a
-- posizione ferma, e il test direbbe "si e' mosso" quando non e' vero.
-- Per questo i confronti non partono mai dal frame zero della pressione.
--
-- Il confronto vero e proprio lo fa lo script PowerShell chiamante, sugli hash
-- dei file: qui si producono solo gli scatti nell'ordine giusto.

local DIR_SEA     = os.getenv("DIR_SEA")   or "P1 Down"
local DIR_LAND    = os.getenv("DIR_LAND")  or "P1 Up"
local BOOT        = tonumber(os.getenv("BOOT_FRAMES")) or 2300
local WALK_LEN    = tonumber(os.getenv("WALK_LEN"))    or 700
-- I due scatti della prova sul MARE sono ENTRAMBI tardivi, e non uno all'inizio
-- e uno alla fine. Dallo spawn di Coneria verso sud c'e' della terra prima
-- della costa: il personaggio si muove e POI si ferma, quindi confrontando
-- inizio e fine si vedrebbe una differenza e si concluderebbe "non blocca"
-- anche quando blocca benissimo. Confrontando due istanti dopo l'arrivo alla
-- riva, invece, l'uguaglianza dimostra che si e' fermato.
local SEA_BASE    = tonumber(os.getenv("SEA_BASE"))    or 400
-- Sulla TERRA la domanda e' opposta -- si DEVE muovere -- quindi li' il
-- confronto giusto e' presto contro tardi.
local LAND_BASE   = tonumber(os.getenv("LAND_BASE"))   or 40

local frames = 0
local fields = {}
local shots  = 0
local phase  = "boot"
local t0     = 0

local function find_field(port, name)
    local key = port .. "|" .. name
    if fields[key] ~= nil then return fields[key] end
    local p = manager.machine.ioport.ports[port]
    local f = p and p.fields[name] or nil
    fields[key] = f or false
    return f
end
-- Le porte si cercano per PORTA e nome, mai per solo nome: nel driver coleco
-- "P1 Down"/"P1 Right" esistono sia in :STD_JOY1 sia in :SAC_JOY1, e iterare
-- con pairs() ha ordine imprevedibile -- meta' dei comandi finirebbe su un
-- controller che la ROM non legge.
local function hold(port, name, down)
    local f = find_field(port, name)
    if f then f:set_value(down and 1 or 0) end
end
local function joy(name, down) hold(":STD_JOY1", name, down) end
-- ATTENZIONE, i pulsanti sono INVERTITI rispetto ai nomi MAME:
--   ":STD_KEYPAD1 :: P1 Button 2" -> z88dk MOVE_FIRE1  (lettura a tastierino)
--   ":STD_JOY1    :: P1 Button 1" -> z88dk MOVE_FIRE2  (lettura a joystick)
-- Un primo tentativo usava "P1 Button 1" per confermare e restava incastrato
-- sull'introduzione: premeva FIRE2, che li' non fa niente.
local function fire1(down) hold(":STD_KEYPAD1", "P1 Button 2", down) end

local function snap(tag)
    shots = shots + 1
    manager.machine.video:snapshot()
    print(string.format("SNAP %d (%s) @frame %d", shots, tag, frames))
end

-- `sub` DEVE essere globale. Se la sottoscrizione finisce in una variabile
-- locale, il chunk termina subito, la locale esce di scope e il garbage
-- collector porta via il notifier: la ROM parte, nessun input arriva mai e si
-- resta fermi sull'introduzione. Non da' errore -- semplicemente non succede
-- niente, che e' il modo peggiore in cui puo' rompersi.
sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1

    if phase == "boot" then
        -- Sequenza copiata TALE E QUALE da mame_drive_battle.lua, dove e' gia'
        -- validata: fronti di FIRE1 solo fra il frame 700 e il 2200. Prima del
        -- 700 la legenda scorre e non va toccata -- un primo tentativo che
        -- premeva subito restava incastrato proprio li'.
        if frames >= 700 and frames < BOOT then
            fire1((frames % 16) < 5)
            return
        elseif frames >= BOOT then
            fire1(false)
            phase = "sea"; t0 = frames
            print(string.format("-- verso il MARE (%s)", DIR_SEA))
        end
        return
    end

    if phase == "sea" then
        local dt = frames - t0
        -- Direzione PULSATA e non tenuta premuta, come nello script di
        -- battaglia: e' la forma di input su cui il movimento a passi discreti
        -- e' stato validato.
        joy(DIR_SEA, (dt % 10) < 5)
        if dt == SEA_BASE then snap("mare: gia' alla riva") end
        if dt >= WALK_LEN then
            snap("mare: ancora piu' tardi (deve essere identico)")
            joy(DIR_SEA, false)
            phase = "gap"; t0 = frames
        end
        return
    end

    -- Una pausa fra le due prove: senza, la pressione della seconda direzione
    -- comincerebbe mentre e' ancora attiva la prima e il primo passo a terra
    -- verrebbe mangiato dal cooldown.
    if phase == "gap" then
        if frames - t0 > 20 then
            phase = "land"; t0 = frames
            print(string.format("-- verso la TERRA (%s)", DIR_LAND))
        end
        return
    end

    if phase == "land" then
        local dt = frames - t0
        joy(DIR_LAND, (dt % 10) < 5)
        if dt == LAND_BASE then snap("terra: presto") end
        if dt >= WALK_LEN then
            snap("terra: dopo la camminata")
            joy(DIR_LAND, false)
            phase = "done"; t0 = frames
        end
        return
    end

    if phase == "done" and frames - t0 > 30 then manager.machine:exit() end
end)
