# extract_intro_text.ps1 -- il testo della LEGGENDA d'apertura di FF1.
#
# PERCHE' ESISTE
#   Fino a slice78 il testo della leggenda stava incollato a mano dentro
#   src/ovl_intro.c. E' testo del gioco originale: in un repository BYOA non
#   puo' stare nel sorgente, deve uscire dal ROM di chi compila. Questo
#   strumento lo rigenera byte per byte.
#
# LA FONTE
#   lut_IntroStoryText, bin/0D_BF20_introtext.bin (bank_0D.asm:3252), 224 byte.
#   Stessa compressione dei dialoghi e delle pagine di storia (DTE, byte
#   $1A-$79 = coppie di lettere): il decodificatore e' quello di
#   extract_story.ps1, e se uno dei due cambia va guardato anche l'altro.
#   Il NES centra ogni riga con degli spazi ($FF) in testa: qui si tolgono,
#   la leggenda si impagina da se' (ovl_intro.c::run_legend).
#   $01 = a capo; una riga fatta solo di spazi e' il vuoto fra i paragrafi.
#
# COSA PRODUCE
#   src/data/intro_text.h: txt_legend[] (righe separate da NUL, un NUL in piu'
#   chiude il gruppo -- il formato che str_at() si aspetta) e LEGEND_LINES.

param(
    [string]$Root    = (Split-Path -Parent $PSScriptRoot),
    [string]$Disasm  = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly",
    [string]$OutHdr  = 'src\data\intro_text.h',
    # La leggenda scorre su 32 colonne: una riga piu' larga e' un errore.
    [int]$MaxCols    = 30
)

$ErrorActionPreference = 'Stop'

$txt = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bin\0D_BF20_introtext.bin'))
$b0F = [System.IO.File]::ReadAllBytes((Join-Path $Disasm 'bank_0F.bin'))

# bank_0F.bin e' l'ULTIMO banco, mappato a $C000.
$DTE2 = 0xF050 - 0xC000
$DTE1 = $DTE2 + 80

# --- charset FF1 -> ASCII (identico a extract_story.ps1) ---------------------
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
    throw ("carattere FF1 0x{0:X2} non mappato" -f $c)
}

$out = ''
foreach ($c in $txt) {
    $c = [int]$c
    if ($c -eq 0) { break }
    if ($c -lt 0x1A)     { $out += "`n" }
    elseif ($c -lt 0x7A) { $k = $c - 0x1A; $out += (Convert-Char $b0F[$DTE1 + $k]) + (Convert-Char $b0F[$DTE2 + $k]) }
    else                 { $out += (Convert-Char $c) }
}

$lines = @($out -split "`n" | ForEach-Object { $_.Trim() })
# Via le righe vuote in testa e in coda: il NES le usa per centrare in verticale.
while ($lines.Count -gt 0 -and $lines[0] -eq '')  { $lines = @($lines | Select-Object -Skip 1) }
while ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }

foreach ($l in $lines) {
    if ($l.Length -gt $MaxCols) { throw ("riga di {0} caratteri (max {1}): <{2}>" -f $l.Length, $MaxCols, $l) }
    Write-Host ("  |{0}|" -f $l)
}

$W = New-Object System.Collections.Generic.List[string]
function W($s) { [void]$W.Add($s) }
W '// AUTO-GENERATO da tools/extract_intro_text.ps1 -- non modificare a mano.'
W '//'
W '// La leggenda d''apertura (lut_IntroStoryText, bank_0D). Righe separate da'
W '// NUL, un NUL in piu'' chiude il gruppo: il formato di str_at().'
W '// La include SOLO src/ovl_intro.c, nella sua rodata (banco 21).'
W ''
W '#ifndef FF1_INTRO_TEXT_H'
W '#define FF1_INTRO_TEXT_H'
W ''
W 'static const char txt_legend[] ='
for ($i = 0; $i -lt $lines.Count; $i++) {
    $esc = $lines[$i].Replace('\', '\\').Replace('"', '\"')
    $end = if ($i -eq $lines.Count - 1) { ';' } else { '' }
    W ('    "' + $esc + '\0"' + $end)
}
W ("#define LEGEND_LINES {0}" -f $lines.Count)
W ''
W '#endif // FF1_INTRO_TEXT_H'

$outPath = Join-Path $Root $OutHdr
[System.IO.File]::WriteAllLines($outPath, $W)
Write-Host ("scritto {0} ({1} righe)" -f $outPath, $lines.Count)
