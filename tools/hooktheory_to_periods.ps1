# Converte JSON Hooktheory in array C di periodi SN76489 / AY-3-8910.
# Uso: powershell -File hooktheory_to_periods.ps1 prelude_melody.json
#
# Convention: tonic Bb -> sd 1 oct 0 = Bb4 (MIDI 70). Period = clock/(32*Hz).
# SN clock 3.579545 MHz e AY clock 1.789772 MHz danno lo stesso period per la
# stessa frequenza (formula equivalente).

param([string]$jsonPath = "prelude_melody.json")

$data = Get-Content $jsonPath -Raw | ConvertFrom-Json

# Mappa tonic -> MIDI (oct 0 = ottava 4 standard)
$tonic_midi = @{
    "C"  = 60; "C#" = 61; "Db" = 61
    "D"  = 62; "D#" = 63; "Eb" = 63
    "E"  = 64
    "F"  = 65; "F#" = 66; "Gb" = 66
    "G"  = 67; "G#" = 68; "Ab" = 68
    "A"  = 69; "A#" = 70; "Bb" = 70
    "B"  = 71
}

# Scale degree -> semitone offset (major scale + chromatic alterations)
$sd_offset = @{
    "1"  = 0;  "b2" = 1;  "2"  = 2;  "b3" = 3;  "3"  = 4
    "4"  = 5;  "b5" = 6;  "5"  = 7;  "b6" = 8;  "6"  = 9
    "b7" = 10; "7"  = 11
}

$tonic = $data.keys[0].tonic
$base = $tonic_midi[$tonic]
Write-Host "Tonic: $tonic (MIDI base oct 0 = $base)"
Write-Host "Total notes: $($data.notes.Count)"

$periods = @()
$midi_notes = @()

foreach ($n in $data.notes) {
    $off = $sd_offset[$n.sd]
    $midi = $base + $off + 12 * $n.octave
    $hz = 440.0 * [Math]::Pow(2, ($midi - 69) / 12.0)
    $period = [Math]::Round(3579545.0 / (32.0 * $hz))
    $periods += $period
    $midi_notes += $midi
}

# Statistiche range
$min_midi = ($midi_notes | Measure-Object -Minimum).Minimum
$max_midi = ($midi_notes | Measure-Object -Maximum).Maximum
$min_p = ($periods | Measure-Object -Minimum).Minimum
$max_p = ($periods | Measure-Object -Maximum).Maximum
Write-Host "MIDI range: $min_midi - $max_midi"
Write-Host "Period range: $min_p - $max_p (SN max usable = 1023)"

if ($max_p -gt 1023) {
    Write-Host "WARN: alcuni periodi superano il limite 10-bit di SN76489 (1023). Quelle note non suonano correttamente." -ForegroundColor Yellow
}

# Emit C array
$out = "static const unsigned int melody_periods[$($periods.Count)] = {`n"
for ($i = 0; $i -lt $periods.Count; $i += 16) {
    $end = [Math]::Min($i + 15, $periods.Count - 1)
    $line = "    " + (($periods[$i..$end] | ForEach-Object { "{0,4}" -f $_ }) -join ", ") + ","
    $out += $line + "  // step $i`n"
}
$out += "};"

$out | Out-File -Encoding utf8 "melody_periods.c"
Write-Host "`nC array written to melody_periods.c"
Write-Host "Preview:"
$out -split "`n" | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
