# extract_story.ps1 -- il testo delle SCHERMATE DI STORIA di FF1 (slice78).
#
# PERCHE' ESISTE
#   La scena del ponte e quella finale non usano i dialoghi: hanno un testo
#   loro, `lut_StoryText` ($A800 del banco $0D), mostrato una PAGINA alla
#   volta. Le pagine $00-$03 sono il ponte, le $04-$18 il finale
#   (lut_Bridge_LastPage / lut_Ending_LastPage, bank_0D.asm:819).
#
#   La compressione e' la STESSA dei dialoghi -- il testo passa da
#   `DrawComplexString`, quindi byte $1A-$79 = coppie di lettere (DTE) -- e per
#   questo il decodificatore qui e' gemello di quello di extract_dialogue.ps1.
#   Non e' condiviso in un modulo perche' i due strumenti hanno sorgenti e
#   validazioni diverse, ma se uno dei due cambia va guardato anche l'altro.
#
# I DUE CODICI DI CONTROLLO CHE QUI CONTANO, e sono diversi dai dialoghi:
#   $01 = interruzione DOPPIA (bank_0F.asm, `LDX #$40` = due righe di 32)
#   $05 = interruzione singola (`LDX #$20`)
#   Nei dialoghi extract_dialogue.ps1 li appiattisce tutti a un a capo solo,
#   perche' li' il riquadro e' fitto. In una schermata di storia la riga vuota
#   e' l'impaginazione: appiattirla incolla i paragrafi.
#
# COSA PRODUCE
#   src/data/story_text.h -- offset per pagina + testo ASCII, terminatore 0,
#   0x01 = a capo. Stesso formato di dialogue.h, cosi' chi lo disegna e' la
#   stessa funzione.

param(
    [string]$Root    = (Split-Path -Parent $PSScriptRoot),
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    # Le pagine volute. Il ponte sono le prime quattro; il finale (4..24) non
    # serve finche' non c'e' un finale, e sarebbero ~1200 byte di testo morto.
    [int]$FirstPage  = 0,
    [int]$PageCount  = 4,
    [string]$OutHdr  = 'src\data\story_text.h',
    # Il riquadro della scena: se una riga sfora e' un ERRORE, non un
    # troncamento -- la name table e' un nastro, non una griglia (difetto #1
    # di slice73).
    [int]$MaxCols    = 20,
    [int]$MaxRows    = 10
)

$ErrorActionPreference = 'Stop'

function ReadBank([string]$n) { [System.IO.File]::ReadAllBytes((Join-Path $Disasm $n)) }
$b0D = ReadBank 'bank_0D.bin'
$b0F = ReadBank 'bank_0F.bin'

# bank_0F.bin e' l'ULTIMO banco, mappato a $C000; il banco $0D sta a $8000.
$DTE2 = 0xF050 - 0xC000
$DTE1 = $DTE2 + 80
$STORY_PTR = 0xA800 - 0x8000

# --- charset FF1 -> ASCII (identico a extract_dialogue.ps1) ------------------
$chr = @{}
foreach ($line in Get-Content (Join-Path $Disasm 'table_standard.tbl')) {
    if ($line -match '^([0-9A-F]{2})=(.*)$') {
        $chr[[Convert]::ToInt32($Matches[1], 16)] = $Matches[2]
    }
}
$chr[0xBE] = "'"
$chr[0xC3] = '.'
$chr[0xFF] = ' '

function Convert-Char([int]$c) {
    if ($chr.ContainsKey($c)) { return $chr[$c] }
    Write-Host ("  ATTENZIONE: carattere FF1 0x{0:X2} non mappato" -f $c) -ForegroundColor Yellow
    return '?'
}

function Get-StoryPage([int]$page) {
    $p = $b0D[$STORY_PTR + $page*2] + $b0D[$STORY_PTR + $page*2 + 1]*256 - 0x8000
    if ($p -lt 0 -or $p -ge $b0D.Length) { throw ("pagina {0}: puntatore fuori dal banco" -f $page) }
    $out = ''
    $guard = 0
    while ($true) {
        if ($guard++ -gt 512) { throw ("pagina {0}: nessun terminatore in 512 byte" -f $page) }
        $c = [int]$b0D[$p]; $p++
        if ($c -eq 0) { break }
        if ($c -eq 1)      { $out += "`n`n" }   # doppia: riga vuota fra i paragrafi
        elseif ($c -lt 0x1A) { $out += "`n" }   # $05 e compagni: singola
        elseif ($c -lt 0x7A) {
            $k = $c - 0x1A
            $out += (Convert-Char $b0F[$DTE1 + $k]) + (Convert-Char $b0F[$DTE2 + $k])
        } else {
            $out += (Convert-Char $c)
        }
    }
    return $out
}

# --- raccolta ----------------------------------------------------------------
$texts = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $PageCount; $i++) {
    $t = Get-StoryPage ($FirstPage + $i)
    # Le pagine cominciano con delle righe vuote (il NES le usa per centrare
    # verticalmente dentro il riquadro). Si tolgono in testa e in coda: qui il
    # riquadro lo impagina il gioco, e una riga vuota iniziale sposterebbe
    # tutto in basso di una riga senza che nessuno l'abbia chiesto.
    $t = $t.Trim("`n")
    [void]$texts.Add($t)
    $lines = $t -split "`n"
    Write-Host ("pagina {0}: {1} righe, larghezza max {2}" -f ($FirstPage + $i), $lines.Count,
                (($lines | Measure-Object -Property Length -Maximum).Maximum))
    foreach ($l in $lines) {
        if ($l.Length -gt $MaxCols) {
            throw ("pagina {0}: riga di {1} caratteri (max {2}): <{3}>" -f ($FirstPage+$i), $l.Length, $MaxCols, $l)
        }
    }
    if ($lines.Count -gt $MaxRows) {
        throw ("pagina {0}: {1} righe (max {2})" -f ($FirstPage+$i), $lines.Count, $MaxRows)
    }
}

# --- byte del testo ----------------------------------------------------------
$blob = New-Object System.Collections.Generic.List[byte]
$offsets = New-Object System.Collections.Generic.List[int]
foreach ($t in $texts) {
    [void]$offsets.Add($blob.Count)
    foreach ($ch in $t.ToCharArray()) {
        if ($ch -eq "`n") { [void]$blob.Add([byte]0x01) }
        else              { [void]$blob.Add([byte][int]$ch) }
    }
    [void]$blob.Add([byte]0)
}

function Format-ByteArray($arr) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $arr.Count; $i += 16) {
        $n = [Math]::Min(16, $arr.Count - $i)
        $row = @()
        for ($k = 0; $k -lt $n; $k++) { $row += ('0x{0:X2}' -f $arr[$i+$k]) }
        [void]$sb.AppendLine('    ' + ($row -join ',') + ',')
    }
    return $sb.ToString().TrimEnd()
}

$maxCols = 0
$maxRows = 0
foreach ($t in $texts) {
    $ls = $t -split "`n"
    if ($ls.Count -gt $maxRows) { $maxRows = $ls.Count }
    $w = ($ls | Measure-Object -Property Length -Maximum).Maximum
    if ($w -gt $maxCols) { $maxCols = $w }
}

$W = New-Object System.Collections.Generic.List[string]
function W($s) { [void]$W.Add($s) }
W '// AUTO-GENERATO da tools/extract_story.ps1 -- non modificare a mano.'
W '//'
W ("// Pagine di storia {0}-{1} (la scena del ponte)." -f $FirstPage, ($FirstPage+$PageCount-1))
W ("// Testo: {0} byte. Riga piu' lunga {1}, pagina piu' alta {2} righe." -f $blob.Count, $maxCols, $maxRows)
W '//'
W '// ASCII, terminatore 0, 0x01 = a capo -- stesso formato di dialogue.h,'
W '// cosi'' il disegno del testo e'' la stessa funzione.'
W '//'
W '// Header GATED: i dati escono solo con FF1_STORY_DEFINE_DATA definito.'
W ''
W '#ifndef FF1_STORY_TEXT_H'
W '#define FF1_STORY_TEXT_H'
W ''
W ("#define FF1_STORY_PAGES     {0}" -f $PageCount)
W ("#define FF1_STORY_TEXT_LEN  {0}" -f $blob.Count)
W ("#define FF1_STORY_MAX_COLS  {0}" -f $maxCols)
W ("#define FF1_STORY_MAX_ROWS  {0}" -f $maxRows)
W '#define FF1_STORY_NEWLINE   0x01'
W ''
W '#ifdef FF1_STORY_DEFINE_DATA'
W ''
W 'static const unsigned int ff1_story_offset[FF1_STORY_PAGES] = {'
W ('    ' + (($offsets | ForEach-Object { $_ }) -join ',') + ',')
W '};'
W ''
W 'static const unsigned char ff1_story_text[FF1_STORY_TEXT_LEN] = {'
W (Format-ByteArray $blob)
W '};'
W ''
W '#endif // FF1_STORY_DEFINE_DATA'
W '#endif // FF1_STORY_TEXT_H'

$outPath = Join-Path $Root $OutHdr
[System.IO.File]::WriteAllLines($outPath, $W)
Write-Host ("scritto {0} ({1} byte di testo, {2}x{3} max)" -f $outPath, $blob.Count, $maxCols, $maxRows)
