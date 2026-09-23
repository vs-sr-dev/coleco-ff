# census_tile_budget.ps1
#
# Quante tile chiede DAVVERO una formazione di FF1, sulle 256 varianti (128
# righe x A/B). Serve a decidere *con i numeri* come far entrare i nemici
# grandi nelle 92 tile libere ($A4-$FF), invece di progettare sul caso peggiore
# teorico -- che e' 2*36 + 2*16 = 104 e potrebbe non esistere in tabella.
#
# La domanda non e' "quanti gruppi ha la formazione" ma "quanti SLOT GRAFICI
# DISTINTI": due gruppi possono condividere lo stesso disegno e differire solo
# per palette (IMP/GrIMP), e in quel caso le tile si caricano una volta sola.
# Lo slot e' la coppia di bit del byte 1: 0=piccoloA 1=grandeA 2=piccoloB
# 3=grandeB.
#
# Oltre al conteggio di formazione misura due sconti sulla grafica vera:
#   - tile completamente trasparenti (gli angoli delle sagome 6x6). Sull'arena
#     nera non vanno nemmeno scritte in nametable: costano zero.
#   - tile duplicate: stessa sagoma E stessa dominante per riga -> una sola
#     tile in VRAM. La chiave include la dominante perche' col TMS9918 il
#     colore vive nella tile, non nell'attributo.
#
# Sorgenti: bin/0B_8400_battleformations.bin per la tabella, bank_07/08.dat
# per la CHR. Offset dei grandi: $320 (gfx0) e $560 (gfx1) dentro la pagina da
# $800 -- 36 tile l'uno, contigui.

param(
    [string]$Disasm = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [int]$Budget    = 92,          # $A4-$FF
    [switch]$Verbose_
)

$ErrorActionPreference = 'Stop'

$formations = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_8400_battleformations.bin'))
$nameBytes  = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0B_94E0_enemynames.bin'))
$chrLow     = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_07.dat'))
$chrHigh    = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_08.dat'))

$SMALL_TILES = 16
$LARGE_TILES = 36
$SMALL_OFF   = @(0x120, 0x220)   # gfx0, gfx1 piccoli
$LARGE_OFF   = @(0x320, 0x560)   # gfx0, gfx1 grandi

$typeNames = @('9small', '4large', 'mix', 'fiend', 'chaos')

# --- nomi (per leggere l'esito) -------------------------------------------
function Decode-Name([byte[]]$src, [int]$off) {
    $s = ''
    for ($j = 0; $j -lt 8; $j++) {
        $b = $src[$off + $j]
        if ($b -eq 0) { break }
        if     ($b -ge 0x8A -and $b -le 0xA3) { $s += [char]([byte][char]'A' + $b - 0x8A) }
        elseif ($b -ge 0xA4 -and $b -le 0xBD) { $s += [char]([byte][char]'a' + $b - 0xA4) }
        elseif ($b -eq 0xC0) { $s += '.' }
        elseif ($b -eq 0xFF) { $s += ' ' }
        else { $s += '' }
    }
    return $s.Trim()
}
$enemyNames = New-Object string[] 128
for ($i = 0; $i -lt 128; $i++) {
    $addr = ([int]$nameBytes[$i*2+1] * 256) + [int]$nameBytes[$i*2]
    $off  = $addr - 0x94E0
    if ($off -ge 0 -and $off -lt $nameBytes.Length) { $enemyNames[$i] = Decode-Name $nameBytes $off }
    else { $enemyNames[$i] = '?' }
}

# ---------------------------------------------------------------------------
#  Analisi della CHR: per ogni (pagina, slot) quante tile servono davvero
# ---------------------------------------------------------------------------
function Get-PageSource([int]$page) {
    if ($page -lt 8) { return @{ Bytes = $chrLow;  Base = $page * 0x800 } }
    return @{ Bytes = $chrHigh; Base = ($page - 8) * 0x800 }
}

# Dominante per riga, identica a extract_monster_gfx.ps1: la chiave di dedup
# deve essere la stessa che finira' in VRAM, altrimenti il risparmio misurato
# qui non e' realizzabile nel codice.
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
    if (-not $any) { return @{ Blank = $true; Key = 'BLANK' } }

    $tc = @(0,0,0)
    for ($r = 0; $r -lt 8; $r++) { for ($c = 0; $c -lt 8; $c++) { $v = $px[$r,$c]; if ($v -gt 0) { $tc[$v-1]++ } } }
    $tm = 0
    if ($tc[1] -gt $tc[$tm]) { $tm = 1 }
    if ($tc[2] -gt $tc[$tm]) { $tm = 2 }
    $fallback = if ($tc[$tm] -gt 0) { $tm + 1 } else { 1 }

    $rv = New-Object byte[] 8
    for ($r = 0; $r -lt 8; $r++) {
        $rc = @(0,0,0)
        for ($c = 0; $c -lt 8; $c++) { $v = $px[$r,$c]; if ($v -gt 0) { $rc[$v-1]++ } }
        $rm = 0
        if ($rc[1] -gt $rc[$rm]) { $rm = 1 }
        if ($rc[2] -gt $rc[$rm]) { $rm = 2 }
        if ($rc[$rm] -gt 0) { $rv[$r] = [byte]($rm + 1) } else { $rv[$r] = [byte]$fallback }
    }

    $k = ''
    for ($r = 0; $r -lt 8; $r++) { $k += $sil[$r].ToString('X2') + $rv[$r].ToString('X') }
    return @{ Blank = $false; Key = $k }
}

# gfxSlot 0-3 -> chiavi delle tile di quello slot in quella pagina
$slotKeys = @{}
for ($page = 0; $page -lt 16; $page++) {
    $src = Get-PageSource $page
    for ($slot = 0; $slot -lt 4; $slot++) {
        $isLarge = ($slot -band 1)
        $which   = $slot -shr 1
        if ($isLarge) { $base = $src.Base + $LARGE_OFF[$which]; $n = $LARGE_TILES }
        else          { $base = $src.Base + $SMALL_OFF[$which]; $n = $SMALL_TILES }
        $keys = @()
        for ($t = 0; $t -lt $n; $t++) { $keys += (Get-TileKey $src.Bytes ($base + $t * 16)).Key }
        $slotKeys["$page/$slot"] = $keys
    }
}

# ---------------------------------------------------------------------------
#  Decodifica formazione (stessa logica di decode_formations.ps1)
# ---------------------------------------------------------------------------
function Decode-Formation([int]$id) {
    $isB = [bool]($id -band 0x80)
    $row = $id -band 0x7F
    $b = New-Object byte[] 16
    [Array]::Copy($formations, $row * 16, $b, 0, 16)
    if ($isB) { $b[6] = $b[0x0E]; $b[7] = $b[0x0F]; $b[8] = 0; $b[9] = 0 }

    $type = $b[0] -shr 4
    $groups = @()
    for ($g = 0; $g -lt 4; $g++) {
        $qty = $b[6 + $g]
        $max = $qty -band 0x0F
        $min = $qty -shr 4
        if ($max -eq 0 -and $min -eq 0) { continue }
        $slot = ($b[1] -shr (2 * $g)) -band 0x03
        $groups += [pscustomobject]@{
            G = $g; Slot = $slot; Large = [bool]($slot -band 1)
            Id = $b[2+$g]; Name = $enemyNames[$b[2+$g]]; Min = $min; Max = $max
        }
    }
    return [pscustomobject]@{
        Id = $id; IsB = $isB; Type = $type
        TypeStr = $(if ($type -lt 5) { $typeNames[$type] } else { "?$type" })
        ChrPage = $b[0] -band 0x0F
        Groups = $groups
    }
}

# ---------------------------------------------------------------------------
#  Censimento
# ---------------------------------------------------------------------------
$rows = @()
for ($id = 0; $id -lt 256; $id++) {
    $f = Decode-Formation $id
    if ($f.Groups.Count -eq 0) { continue }

    $slots = @($f.Groups | ForEach-Object { $_.Slot } | Sort-Object -Unique)
    $nLarge = @($slots | Where-Object { $_ -band 1 }).Count
    $nSmall = @($slots | Where-Object { -not ($_ -band 1) }).Count

    $naive = $nLarge * $LARGE_TILES + $nSmall * $SMALL_TILES

    # sconti misurati sulla CHR vera, solo per i tipi che usano le pagine
    $noBlank = 0; $dedup = 0
    if ($f.Type -le 2) {
        $seen = @{}
        foreach ($s in $slots) {
            foreach ($k in $slotKeys["$($f.ChrPage)/$s"]) {
                if ($k -eq 'BLANK') { continue }
                $noBlank++
                if (-not $seen.ContainsKey($k)) { $seen[$k] = $true }
            }
        }
        $dedup = $seen.Count
    }

    $rows += [pscustomobject]@{
        Id = $id; Type = $f.TypeStr; Page = $f.ChrPage
        NGroups = $f.Groups.Count; NSlots = $slots.Count
        NLarge = $nLarge; NSmall = $nSmall
        Naive = $naive; NoBlank = $noBlank; Dedup = $dedup
        Names = (($f.Groups | ForEach-Object { "$($_.Name)($($_.Slot))" }) -join ' ')
    }
}

Write-Host ""
Write-Host "=== combinazioni di slot esistenti in tabella ===" -ForegroundColor Cyan
$rows | Group-Object { "{0}L+{1}S" -f $_.NLarge, $_.NSmall } | Sort-Object Name | ForEach-Object {
    $ex = $_.Group[0]
    Write-Host ("  {0,-6} : {1,3} formazioni   naive {2,3} tile   (tipi: {3})" -f `
        $_.Name, $_.Count, $ex.Naive, (($_.Group | ForEach-Object { $_.Type } | Sort-Object -Unique) -join '/'))
}

Write-Host ""
Write-Host "=== caso peggiore, per strategia ===" -ForegroundColor Cyan
foreach ($m in @('Naive','NoBlank','Dedup')) {
    $sub = $rows | Where-Object { $_.$m -gt 0 }
    if (-not $sub) { continue }
    $mx = ($sub | Measure-Object -Property $m -Maximum).Maximum
    $over = @($sub | Where-Object { $_.$m -gt $Budget })
    $worst = @($sub | Where-Object { $_.$m -eq $mx })[0]
    $verdict = if ($over.Count -eq 0) { "ENTRA" } else { "$($over.Count) formazioni sopra budget" }
    Write-Host ("  {0,-8} max {1,3} tile  (budget {2})  -> {3}" -f $m, $mx, $Budget, $verdict) `
        -ForegroundColor $(if ($over.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host ("           peggiore: form {0} [{1}] pag {2}  {3}" -f `
        $worst.Id.ToString('X2'), $worst.Type, $worst.Page, $worst.Names)
}

Write-Host ""
Write-Host "=== le 12 formazioni piu' costose (dopo dedup) ===" -ForegroundColor Cyan
$rows | Where-Object { $_.Dedup -gt 0 } | Sort-Object -Property Dedup -Descending |
    Select-Object -First 12 | ForEach-Object {
        Write-Host ("  {0} [{1,-6}] pag{2,-3} slot {3}  naive {4,3} -> senzaVuote {5,3} -> dedup {6,3}   {7}" -f `
            $_.Id.ToString('X2'), $_.Type, $_.Page, $_.NSlots, $_.Naive, $_.NoBlank, $_.Dedup, $_.Names)
    }

Write-Host ""
Write-Host "=== tipi fiend/chaos: quanti gruppi ===" -ForegroundColor Cyan
$rows | Where-Object { $_.Type -eq 'fiend' -or $_.Type -eq 'chaos' } | ForEach-Object {
    Write-Host ("  {0} [{1,-5}] gruppi {2} slot {3}  {4}" -f $_.Id.ToString('X2'), $_.Type, $_.NGroups, $_.NSlots, $_.Names)
}

if ($Verbose_) {
    Write-Host ""
    Write-Host "=== tutte le formazioni con almeno un grande ===" -ForegroundColor Cyan
    $rows | Where-Object { $_.NLarge -gt 0 } | ForEach-Object {
        Write-Host ("  {0} [{1,-6}] pag{2,-3} {3}L+{4}S  naive {5,3} dedup {6,3}   {7}" -f `
            $_.Id.ToString('X2'), $_.Type, $_.Page, $_.NLarge, $_.NSmall, $_.Naive, $_.Dedup, $_.Names)
    }
}
