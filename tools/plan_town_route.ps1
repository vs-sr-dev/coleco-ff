# plan_town_route.ps1 -- il cammino piu' corto dentro una mappa standard,
# scritto nella forma che serve al piano di uno script MAME.
#
# PERCHE' ESISTE (slice66)
#   Il piano di mame_drive_town.lua era stato ricavato a mano leggendo il
#   ritaglio 21x13 attorno all'ingresso, e per la locanda bastava. La clinica
#   di Coneria pero' sta a (24,4), cioe' fuori da quel ritaglio e dall'altra
#   parte della citta': una rotta indovinata a mano finisce dentro un muro, e
#   nel log un passo bloccato per errore di rotta e un passo bloccato per
#   difetto del gioco si scrivono nello stesso modo. La rotta la calcola
#   questo file dagli STESSI byte che legge il gioco.
#
#   Il costo di sbagliarla e' asimmetrico: una rotta giusta si vede subito, una
#   rotta sbagliata sembra una collisione rotta.
#
# LA REGOLA DEL BLOCCO E' QUELLA DEL NES, non `byte0 & TP_NOMOVE`:
#     (byte0 & (TP_SPEC_MASK | TP_NOMOVE)) == TP_NOMOVE
# NOMOVE blocca solo se i bit di specialita' sono spenti -- le porte dei
# negozi hanno NOMOVE acceso INSIEME a TP_SPEC_DOOR e si calpestano.
# Vedi slice64 e memory/slice64_town_collisions.md.
#
# LA DESTINAZIONE E' UNA PORTA, e la porta e' l'ULTIMO passo: ci si arriva e il
# negozio si apre. Quindi la ricerca attraversa solo caselle libere e ammette
# la porta soltanto come arrivo.
#
# ATTENZIONE: le caselle di WARP (il prato attorno alla citta') sono
# "libere" ma calpestarle ESCE dalla citta'. La ricerca le esclude, o la rotta
# piu' corta passerebbe allegramente per l'overworld.
#
# USO
#   .\tools\plan_town_route.ps1 -ToShop 41
#   .\tools\plan_town_route.ps1 -FromX 11 -FromY 10 -ToShop 51
#   -> stampa le righe gia' pronte per il PLAN del Lua:
#      { k = "step", dir = "D", n = 4, why = "..." },

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$MapId = 0,
    # L'ingresso NON e' indicizzato per mappa ma per ID DI TELETRASPORTO: le
    # due tabelle a $2C00 (X) e $2C20 (Y) hanno alla voce 1 la coppia (16,23),
    # che e' l'ingresso di Coneria, e Coneria e' proprio il teleport id 1 del
    # macrotile $49 in overworld. Indicizzarle col numero di mappa da' (30,18),
    # che sta dentro una casa: la ricerca fallisce subito e sembra che la
    # citta' non sia percorribile.
    [int]$TeleId = 1,
    # Partenza: se non data, l'ingresso della mappa.
    [int]$FromX = -1,
    [int]$FromY = -1,
    # Arrivo: o uno shop_id, o coordinate esplicite.
    [int]$ToShop = 0,
    [int]$ToX = -1,
    [int]$ToY = -1
)

$ErrorActionPreference = 'Stop'
function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }

$b00 = ReadBank 'bank_00.dat'
$tileset = [int]$b00[0x2CC0 + $MapId]
$PROP_BASE = 0x0800 + $tileset * 256

# --- mappa: stessa decompressione di analyze_town_props.ps1 -----------------
$sm = New-Object byte[] (16384 * 4)
$i = 0
foreach ($n in 'bank_04.dat','bank_05.dat','bank_06.dat','bank_07.dat') {
    [Array]::Copy((ReadBank $n), 0, $sm, $i, 16384); $i += 16384
}
$lo = [int]$sm[$MapId*2]; $hi = [int]$sm[$MapId*2+1]
$srcp = (($hi -shr 6) -band 3) * 16384 + (((($hi -band 0x3F) -bor 0x80) -shl 8) -bor $lo) - 0x8000

$map = New-Object byte[] 4096
$n = 0
while ($n -lt 4096) {
    $v = $sm[$srcp]; $srcp++
    if ($v -eq 0xFF) { break }
    if ($v -lt 0x80) { $map[$n] = $v; $n++ }
    else {
        $t = [byte]($v -band 0x7F); $len = [int]$sm[$srcp]; $srcp++
        if ($len -eq 0) { $len = 256 }
        for ($k = 0; $k -lt $len -and $n -lt 4096; $k++) { $map[$n] = $t; $n++ }
    }
}
if ($n -ne 4096) { throw "mappa $MapId decompressa a $n macrotile, attesi 4096" }

function Prop0([int]$x, [int]$y) { [int]$b00[$PROP_BASE + [int]$map[$y*64 + $x]*2] }
function Prop1([int]$x, [int]$y) { [int]$b00[$PROP_BASE + [int]$map[$y*64 + $x]*2 + 1] }

# Gli ABITANTI sono ostacoli quanto i muri (slice76). Sul NES si spingono e si
# spostano; qui stanno fermi, quindi bloccano -- e una rotta calcolata senza di
# loro finisce addosso a qualcuno. E' esattamente quello che e' successo alla
# prima corsa dopo slice76: tre script camminavano da mesi sulla casella (15,12)
# di Coneria, dove adesso c'e' Arylon la ballerina, e nel log un abitante e un
# muro si scrivono nello stesso modo -- "passo bloccato".
$OBJ_BASE = 0x3400 + $MapId * 48
$npcHere = @{}
for ($s = 0; $s -lt 15; $s++) {
    $oid = [int]$b00[$OBJ_BASE + $s*3]
    if ($oid -eq 0) { continue }
    # Un oggetto che comincia INVISIBILE non blocca: la sua casella e' libera
    # finche' la storia non lo fa comparire. Il bit 0 di lut_InitGameFlags.
    if (([int]$b00[0x2F00 + $oid] -band 1) -eq 0) { continue }
    $nx = [int]$b00[$OBJ_BASE + $s*3 + 1] -band 0x3F
    $ny = [int]$b00[$OBJ_BASE + $s*3 + 2] -band 0x3F
    $npcHere["$nx,$ny"] = $oid
}
if ($npcHere.Count -gt 0) {
    Write-Host ("abitanti che bloccano: " + (($npcHere.GetEnumerator() |
        ForEach-Object { "({0}) `${1:X2}" -f $_.Key, $_.Value }) -join '  '))
}

# Libera = si puo' ATTRAVERSARE senza che succeda niente.
function IsFree([int]$x, [int]$y) {
    $p0 = Prop0 $x $y
    if (($p0 -band 0x1F) -eq 0x01) { return $false }   # muro (NOMOVE senza spec)
    if (($p0 -band 0xC0) -ne 0)    { return $false }   # warp: uscirebbe dalla citta'
    if ($npcHere.ContainsKey("$x,$y")) { return $false }
    $true
}
function IsShopDoor([int]$x, [int]$y, [int]$sid) {
    (((Prop0 $x $y) -band 0x1E) -eq 0x02) -and ((Prop1 $x $y) -eq $sid)
}

if ($FromX -lt 0) { $FromX = [int]$b00[0x2C00 + $TeleId] }
if ($FromY -lt 0) { $FromY = [int]$b00[0x2C20 + $TeleId] }

if ($ToShop -gt 0) {
    $found = $false
    for ($y = 0; $y -lt 64 -and -not $found; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            if (IsShopDoor $x $y $ToShop) { $ToX = $x; $ToY = $y; $found = $true; break }
        }
    }
    if (-not $found) { throw "shop_id $ToShop non trovato sulla mappa $MapId" }
}
if ($ToX -lt 0) { throw 'serve -ToShop oppure -ToX/-ToY' }

Write-Host ("mappa {0}: da ({1},{2}) a ({3},{4}){5}" -f `
    $MapId, $FromX, $FromY, $ToX, $ToY, $(if ($ToShop) { " -- porta del negozio $ToShop" } else { '' }))

# --- BFS. Il mondo e' toroidale (& 63), come in gioco. ---------------------
$prev = New-Object int[] 4096
for ($k = 0; $k -lt 4096; $k++) { $prev[$k] = -1 }
$start = $FromY*64 + $FromX
$goal  = $ToY*64 + $ToX
$prev[$start] = $start
$queue = New-Object System.Collections.Queue
$queue.Enqueue($start)
# L'ordine delle direzioni decide QUALE cammino minimo esce, a parita' di
# lunghezza. Su/giu' prima di sinistra/destra da rotte che si leggono meglio
# nel log (lunghi tratti verticali, poi orizzontali).
$DIRS = @(
    @{ n = 'U'; dx =  0; dy = -1 },
    @{ n = 'D'; dx =  0; dy =  1 },
    @{ n = 'L'; dx = -1; dy =  0 },
    @{ n = 'R'; dx =  1; dy =  0 }
)
$dirOf = New-Object string[] 4096

while ($queue.Count -gt 0) {
    $cur = [int]$queue.Dequeue()
    if ($cur -eq $goal) { break }
    $cx = $cur % 64; $cy = [int][Math]::Floor($cur / 64)
    foreach ($d in $DIRS) {
        $nx = ($cx + $d.dx) -band 63
        $ny = ($cy + $d.dy) -band 63
        $ni = $ny*64 + $nx
        if ($prev[$ni] -ne -1) { continue }
        # L'arrivo si accetta anche se e' una porta (invalicabile per tutti
        # gli altri scopi): e' proprio quello il punto d'arrivo.
        if ($ni -ne $goal -and -not (IsFree $nx $ny)) { continue }
        $prev[$ni] = $cur
        $dirOf[$ni] = $d.n
        $queue.Enqueue($ni)
    }
}

if ($prev[$goal] -eq -1) { throw "nessun cammino da ($FromX,$FromY) a ($ToX,$ToY)" }

# --- ricostruzione e compattamento in tratti dritti ------------------------
$path = @()
$cur = $goal
while ($cur -ne $start) {
    $path = ,@{ dir = $dirOf[$cur]; x = ($cur % 64); y = [int][Math]::Floor($cur / 64) } + $path
    $cur = $prev[$cur]
}

Write-Host ("passi: {0}" -f $path.Count)
Write-Host ''
$runDir = ''; $runN = 0; $runX = 0; $runY = 0
$lines = @()
function FlushRun() {
    if ($script:runN -gt 0) {
        $script:lines += ('    {{ k = "step", dir = "{0}", n = {1}, why = "fino a ({2},{3})" }},' -f `
            $script:runDir, $script:runN, $script:runX, $script:runY)
    }
    $script:runN = 0
}
foreach ($p in $path) {
    if ($p.dir -ne $runDir) { FlushRun; $runDir = $p.dir }
    $runN++; $runX = $p.x; $runY = $p.y
}
FlushRun
$lines | ForEach-Object { Write-Host $_ }
