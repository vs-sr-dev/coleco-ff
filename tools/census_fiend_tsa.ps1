# census_fiend_tsa.ps1
#
# Costo in tile dei quattro Fiend e di Chaos.
#
# Questi non passano dagli slot grafici: PrepareEnemyFormation_Fiend usa il
# byte 1 della formazione come indice in lut_FiendTSAPtrs e disegna una TSA --
# una tabella di ASSEGNAZIONE tile, non una sequenza di tile. Percio' il costo
# non e' "quante celle occupa" (8x8 per i fiend, 14x12 per Chaos) ma "quanti
# indici DISTINTI compaiono nella TSA": la TSA esiste proprio per riusare la
# stessa tile in piu' punti, ed e' la ragione per cui Chaos, che copre 168
# celle, puo' costare molto meno di 168 tile.
#
# Vengono contate due cose diverse:
#   NES   = indici distinti nella TSA, cioe' quante tile diverse usa il NES.
#   TMS   = chiavi distinte dopo la nostra conversione (sagoma + dominante per
#           riga). Puo' essere MINORE: due tile NES diverse che differiscono
#           solo nei bit di colore collassano in una sola, perche' noi teniamo
#           la dominante per riga e non i 2 bit pieni.
#
# Layout (bank_0B.asm:95-112):
#   data_FiendTSA  4 blocchi da $50: $40 di TSA 8x8 + $10 di attributi
#   data_ChaosTSA  $C0: $A8 di TSA 14x12 + $10 di attributi + 8 di padding

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$Budget    = 92
)

$ErrorActionPreference = 'Stop'

$fiendTsa   = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_92E0_fiendtsa.bin'))
$chaosTsa   = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_9420_chaostsa.bin'))
$formations = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_8400_battleformations.bin'))
$chrLow     = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_07.dat'))
$chrHigh    = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_08.dat'))

function Get-TileKey([byte[]]$src, [int]$off) {
    $sil = New-Object byte[] 8
    $any = $false
    $px  = New-Object 'int[,]' 8, 8
    for ($r = 0; $r -lt 8; $r++) {
        $lo = $src[$off + $r]; $hi = $src[$off + 8 + $r]
        $sil[$r] = ($lo -bor $hi) -band 0xFF
        if ($sil[$r] -ne 0) { $any = $true }
        for ($c = 0; $c -lt 8; $c++) {
            $bit = 7 - $c
            $px[$r, $c] = (((($hi -shr $bit) -band 1) -shl 1) -bor (($lo -shr $bit) -band 1))
        }
    }
    if (-not $any) { return 'BLANK' }
    $tc = @(0,0,0)
    for ($r = 0; $r -lt 8; $r++) { for ($c = 0; $c -lt 8; $c++) { $v = $px[$r,$c]; if ($v -gt 0) { $tc[$v-1]++ } } }
    $tm = 0
    if ($tc[1] -gt $tc[$tm]) { $tm = 1 }
    if ($tc[2] -gt $tc[$tm]) { $tm = 2 }
    $fb = if ($tc[$tm] -gt 0) { $tm + 1 } else { 1 }
    $k = ''
    for ($r = 0; $r -lt 8; $r++) {
        $rc = @(0,0,0)
        for ($c = 0; $c -lt 8; $c++) { $v = $px[$r,$c]; if ($v -gt 0) { $rc[$v-1]++ } }
        $rm = 0
        if ($rc[1] -gt $rc[$rm]) { $rm = 1 }
        if ($rc[2] -gt $rc[$rm]) { $rm = 2 }
        $rv = if ($rc[$rm] -gt 0) { $rm + 1 } else { $fb }
        $k += $sil[$r].ToString('X2') + $rv.ToString('X')
    }
    return $k
}

function Get-PageBase([int]$page) {
    if ($page -lt 8) { return @{ Bytes = $chrLow;  Base = $page * 0x800 } }
    return @{ Bytes = $chrHigh; Base = ($page - 8) * 0x800 }
}

# Quale pagina CHR usa ciascuna formazione fiend/chaos, e quale indice TSA.
$rows = @()
for ($row = 0; $row -lt 128; $row++) {
    $t = $formations[$row * 16] -shr 4
    if ($t -lt 3) { continue }
    $rows += [pscustomobject]@{
        Row = $row; Type = $(if ($t -eq 3) { 'fiend' } else { 'chaos' })
        Page = $formations[$row * 16] -band 0x0F
        Gfx  = $formations[$row * 16 + 1]
        Pal  = $formations[$row * 16 + 0x0A]
    }
}

Write-Host ""
Write-Host "=== fiend / chaos: costo reale in tile ===" -ForegroundColor Cyan
Write-Host ("budget = {0} tile ($A4-$FF)" -f $Budget)
Write-Host ""

$maxCost = 0
foreach ($r in $rows) {
    if ($r.Type -eq 'fiend') {
        $off = $r.Gfx * 0x50
        $tsa = $fiendTsa[$off .. ($off + 0x3F)]
        $cells = '8x8 = 64'
    } else {
        $tsa = $chaosTsa[0 .. 0xA7]
        $cells = '14x12 = 168'
    }

    $nesIds = @{}
    foreach ($b in $tsa) { $nesIds[$b] = $true }

    $src = Get-PageBase $r.Page
    $tmsKeys = @{}
    $blank = 0
    foreach ($id in $nesIds.Keys) {
        # La TSA indicizza il pattern table della pagina caricata: tile n sta a
        # base + n*16. Fuori pagina (>= $80) non e' rappresentabile qui.
        if ($id -ge 0x80) { $tmsKeys["OOR$id"] = $true; continue }
        $k = Get-TileKey $src.Bytes ($src.Base + $id * 16)
        if ($k -eq 'BLANK') { $blank++; continue }
        $tmsKeys[$k] = $true
    }

    $cost = $tmsKeys.Count
    if ($cost -gt $maxCost) { $maxCost = $cost }
    $col = if ($cost -le $Budget) { 'Green' } else { 'Red' }
    Write-Host ("  riga {0} [{1,-5}] pag {2,-3} gfx {3}  celle {4,-12} tileNES {5,3}  tileTMS {6,3}  (vuote {7})" -f `
        $r.Row.ToString('X2'), $r.Type, $r.Page, $r.Gfx, $cells, $nesIds.Count, $cost, $blank) -ForegroundColor $col
}

Write-Host ""
$col = if ($maxCost -le $Budget) { 'Green' } else { 'Red' }
Write-Host ("massimo fiend/chaos = {0} tile su {1} disponibili" -f $maxCost, $Budget) -ForegroundColor $col
