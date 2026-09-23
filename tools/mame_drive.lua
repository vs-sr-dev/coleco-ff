-- mame_drive.lua -- guida una ROM ColecoFF fino alla overworld e cattura.
--
-- Usato da tools/build_all.ps1 -Snap. Serve perche' la schermata interessante
-- sta dietro legend + boot menu + class select: senza premere tasti si
-- cattura solo il testo del prologo.
--
-- DUE TRAPPOLE, entrambe costate un giro a vuoto:
--
-- 1. emu.add_machine_frame_notifier, NON emu.register_frame_done. Con
--    frame_done l'override arriva dopo che la macchina ha gia' campionato le
--    porte, e il gioco non vede mai il tasto. Il token del notifier va tenuto
--    in una variabile GLOBALE, o il garbage collector lo raccoglie.
--
-- 2. Su ColecoVision i due fire stanno in porte diverse: "P1 Button 1" in
--    :STD_JOY1 (lettura joystick) e "P1 Button 2" in :STD_KEYPAD1 (lettura
--    keypad). Quale sia MOVE_FIRE1 per z88dk non e' ovvio: si premono
--    entrambi.
--
-- Diagnostica se non risponde: port:read() deve cambiare premendo
-- (es. FF -> BF per mask $40; gli input Coleco sono attivi bassi).
--
-- Tempi in frame (NTSC, ~60/s):
--   0-700     BIOS ColecoVision
--   700-2200  pulsazione FIRE: attraversa legend, menu (NEW GAME e' il
--             default) e le 4 conferme della class select
--   2400      primo scatto: overworld allo spawn di Coneria
--   2450-2750 passi verso est: verifica che lo scroll tenga i colori
--   2850      secondo scatto, poi uscita

local frames = 0
local fields = {}

local function find_field(name)
    if fields[name] then return fields[name] end
    for _, port in pairs(manager.machine.ioport.ports) do
        for fname, field in pairs(port.fields) do
            if fname == name then fields[name] = field; return field end
        end
    end
    error("campo input non trovato: " .. name)
end

local function hold(name, on)
    find_field(name):set_value(on and 1 or 0)
end

sub = emu.add_machine_frame_notifier(function()
    frames = frames + 1

    if frames >= 700 and frames < 2200 then
        local on = (frames % 16) < 5      -- pulsare: servono i FRONTI, non il livello
        hold("P1 Button 1", on)
        hold("P1 Button 2", on)
    elseif frames == 2200 then
        hold("P1 Button 1", false)
        hold("P1 Button 2", false)
    end

    if frames == 2400 then
        manager.machine.video:snapshot()
    end

    if frames > 2450 and frames < 2750 then
        hold("P1 Right", (frames % 10) < 5)
    elseif frames == 2750 then
        hold("P1 Right", false)
    end

    if frames == 2850 then
        manager.machine.video:snapshot()
    elseif frames == 2860 then
        manager.machine:exit()
    end
end)
