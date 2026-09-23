# decode_formations.ps1
#
# Decodifica i 16 byte di lut_BattleFormations e stampa la composizione in
# chiaro. Serve a due cose:
#   1. verificare il formato PRIMA di scrivere il rendering (il commento in
#      extract_encounter_data.ps1 aveva i nibble min/max invertiti);
#   2. sapere quali nemici, quali pagine CHR e quali palette servono davvero
#      per i domini che si raggiungono a piedi da Coneria.
#
# Fonte del formato: bank_0B.asm PrepareEnemyFormation_SmallLarge ($A17E) e
# bank_0F.asm LoadBattleBGCHRAndPalettes (il nibble basso del byte 0 e' la
# PAGINA CHR dei nemici, non un generico "pattern").
#
# Layout dei 16 byte:
#   0   hi nibble = tipo (0=9small 1=4large 2=mix 3=fiend 4=chaos)
#       lo nibble = pagina CHR dei nemici (0-15)
#   1   assegnazione grafica, 2 bit per gruppo: gruppo i = bit (2i+1, 2i).
#       Il bit BASSO della coppia = grande/piccolo (1 = grande).
#   2-5 ID nemico dei gruppi 0-3
#   6-9 quantita' dei gruppi 0-3, formazione A:
#       hi nibble = MIN, lo nibble = MAX   <-- l'ordine e' questo, verificato
#                                              su PrepareEnemyFormation
#   A   ID palette 0        B   ID palette 1
#   C   tasso di sorpresa
#   D   hi nibble = assegnazione palette: il gruppo i usa il bit (7-i);
#       0 -> palette del byte A, 1 -> palette del byte B.
#       bit 0 = "non si puo' fuggire"
#   E-F quantita' dei gruppi 0-1, formazione B (la B usa solo 2 gruppi)

param(
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int[]]$Domains  = @(0x2C),
    [switch]$AllPages
)

$ErrorActionPreference = 'Stop'

$formations = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_8400_battleformations.bin'))
$domainTbl  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_8000_battledomains.bin'))
$nameBytes  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_94E0_enemynames.bin'))

# --- nomi nemici (charset custom $8A-$BD) ---------------------------------
function Decode-Name([byte[]]$src, [int]$off) {
    $s = ''
    for ($j = 0; $j -lt 8; $j++) {
        $b = $src[$off + $j]
        if ($b -eq 0) { break }
        if     ($b -ge 0x8A -and $b -le 0xA3) { $s += [char]([byte][char]'A' + $b - 0x8A) }
        elseif ($b -ge 0xA4 -and $b -le 0xBD) { $s += [char]([byte][char]'a' + $b - 0xA4) }
        elseif ($b -eq 0xBE) { $s += ';' }
        elseif ($b -eq 0xBF) { $s += ',' }
        elseif ($b -eq 0xC0) { $s += '.' }
        elseif ($b -eq 0xFF) { $s += ' ' }
        else { $s += '?' }
    }
    return $s
}
$enemyNames = New-Object string[] 128
for ($i = 0; $i -lt 128; $i++) {
    $addr = ([int]$nameBytes[$i*2+1] * 256) + [int]$nameBytes[$i*2]
    $off  = $addr - 0x94E0
    if ($off -ge 0 -and $off -lt $nameBytes.Length) { $enemyNames[$i] = Decode-Name $nameBytes $off }
    else { $enemyNames[$i] = '?' }
}

$typeNames = @('9small', '4large', 'mix', 'fiend', 'chaos')

# Il bit 7 dell'ID selezione la variante "B" della stessa riga di tabella:
# l'indice vero e' id & $7F, e le quantita' vengono dai byte E,F (solo gruppi
# 0 e 1; i gruppi 2 e 3 non esistono nella B). Vedi PrepareEnemyFormation.
function Decode-Formation([int]$id) {
    $isB = [bool]($id -band 0x80)
    $row = $id -band 0x7F
    $b = New-Object byte[] 16
    [Array]::Copy($formations, $row * 16, $b, 0, 16)
    if ($isB) {
        $b[6] = $b[0x0E]
        $b[7] = $b[0x0F]
        $b[8] = 0; $b[9] = 0
        $b[4] = 0; $b[5] = 0
    }

    $type    = $b[0] -shr 4
    $chrPage = $b[0] -band 0x0F
    $typeStr = if ($type -lt 5) { $typeNames[$type] } else { "?$type" }

    $groups = @()
    for ($g = 0; $g -lt 4; $g++) {
        $gfxPair = ($b[1] -shr (2 * $g)) -band 0x03
        $isLarge = ($gfxPair -band 0x01)          # bit basso della coppia
        $enemyId = $b[2 + $g]
        $qty     = $b[6 + $g]
        $qmin    = $qty -shr 4                     # hi nibble = MIN
        $qmax    = $qty -band 0x0F                 # lo nibble = MAX
        $pltBit  = ($b[0x0D] -shr (7 - $g)) -band 0x01
        $pltId   = if ($pltBit) { $b[0x0B] } else { $b[0x0A] }
        $groups += [pscustomobject]@{
            Group   = $g
            EnemyId = $enemyId
            Name    = $enemyNames[$enemyId]
            Min     = $qmin
            Max     = $qmax
            GfxSlot = $gfxPair
            Large   = [bool]$isLarge
            PalId   = $pltId
        }
    }

    return [pscustomobject]@{
        Id      = $id
        IsB     = $isB
        Type    = $typeStr
        ChrPage = $chrPage
        NoRun   = [bool]($b[0x0D] -band 0x01)
        Surprise= $b[0x0C]
        Groups  = $groups
        Raw     = ($b | ForEach-Object { $_.ToString('X2') }) -join ' '
    }
}

function Show-Formation($f) {
    $flags = ''
    if ($f.NoRun) { $flags += ' NORUN' }
    if ($f.IsB) { $flags += ' (variante B)' }
    Write-Host ("  form {0} [{1}] pagCHR {2} sorpresa {3}{4}" -f `
        $f.Id.ToString('X2'), $f.Type, $f.ChrPage, $f.Surprise, $flags)
    foreach ($g in $f.Groups) {
        if ($g.Max -eq 0 -and $g.Min -eq 0) { continue }
        $sz = if ($g.Large) { 'GRANDE' } else { 'piccolo' }
        Write-Host ("      gr{0}  {1,-9} x{2}-{3}  gfx{4} {5,-7} pal {6}" -f `
            $g.Group, $g.Name, $g.Min, $g.Max, $g.GfxSlot, $sz, $g.PalId)
    }
}

# --- domini richiesti ------------------------------------------------------
$usedPages    = @{}
$usedPalettes = @{}
$usedTypes    = @{}

foreach ($d in $Domains) {
    Write-Host ""
    Write-Host ("=== dominio 0x{0} ===" -f $d.ToString('X2')) -ForegroundColor Cyan
    $seen = @{}
    for ($slot = 0; $slot -lt 8; $slot++) {
        $fid = $domainTbl[$d * 8 + $slot]
        if ($seen.ContainsKey($fid)) { continue }
        $seen[$fid] = $true
        $f = Decode-Formation $fid
        Show-Formation $f
        $usedTypes[$f.Type] = $true
        if ($f.Type -eq '9small' -or $f.Type -eq '4large' -or $f.Type -eq 'mix') {
            $usedPages[$f.ChrPage] = $true
        }
        foreach ($g in $f.Groups) { if ($g.Max -gt 0) { $usedPalettes[$g.PalId] = $true } }
    }
}

Write-Host ""
Write-Host "--- riepilogo ---" -ForegroundColor Yellow
Write-Host ("tipi      : {0}" -f (($usedTypes.Keys | Sort-Object) -join ', '))
Write-Host ("pagine CHR: {0}" -f (($usedPages.Keys | Sort-Object) -join ', '))
Write-Host ("palette   : {0}" -f (($usedPalettes.Keys | Sort-Object) -join ', '))

# --- censimento globale, per dimensionare i dati ---------------------------
if ($AllPages) {
    Write-Host ""
    Write-Host "--- censimento su tutte le 128 formazioni ---" -ForegroundColor Yellow
    $typeCount = @{}
    $pageCount = @{}
    for ($i = 0; $i -lt 128; $i++) {
        $f = Decode-Formation $i
        if (-not $typeCount.ContainsKey($f.Type)) { $typeCount[$f.Type] = 0 }
        $typeCount[$f.Type]++
        if ($f.Type -ne 'fiend' -and $f.Type -ne 'chaos') {
            if (-not $pageCount.ContainsKey($f.ChrPage)) { $pageCount[$f.ChrPage] = 0 }
            $pageCount[$f.ChrPage]++
        }
    }
    foreach ($k in ($typeCount.Keys | Sort-Object)) {
        Write-Host ("  tipo {0,-7} : {1} formazioni" -f $k, $typeCount[$k])
    }
    Write-Host ("  pagine CHR usate: {0}" -f (($pageCount.Keys | Sort-Object) -join ', '))
}
