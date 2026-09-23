# Converte JSON Hooktheory completo (notes + chords) in C arrays per slice16+.
#
# Output:
#   melody_period[N]: 16-bit period SN/AY se step inizia una nuova nota, 0 altrimenti
#   chord_change[N]:  chord_id 0..(M-1) se step inizia un nuovo accordo, 0xFF altrimenti
#
# Lo step base e' il 16esimo (= 0.25 beat). Per durate maggiori la nota
# continua a suonare (square wave latched, ri-write non necessario).
#
# La mappatura chord -> chord_id e' specifica del brano. Modificare la
# function Get-ChordId qui sotto per ogni nuovo brano (o passare un mapping).

param(
    [string]$jsonPath = "town_melody.json",
    [string]$outPath  = "town_song.c",
    [int]$octShift    = 0           # offset ottave applicato a tutte le note
)

$data = Get-Content $jsonPath -Raw | ConvertFrom-Json

# Tonic central (oct 0 = ottava 4)
$tonic_midi = @{
    "C"  = 60; "C#" = 61; "Db" = 61
    "D"  = 62; "D#" = 63; "Eb" = 63
    "E"  = 64
    "F"  = 65; "F#" = 66; "Gb" = 66
    "G"  = 67; "G#" = 68; "Ab" = 68
    "A"  = 69; "A#" = 70; "Bb" = 70
    "B"  = 71
}

# Scale degree -> semitone offset (natural + b/# accidentals)
$sd_offset = @{
    "1"  = 0;  "#1" = 1;  "b2" = 1;  "2"  = 2
    "#2" = 3;  "b3" = 3;  "3"  = 4;  "4"  = 5
    "#4" = 6;  "b5" = 6;  "5"  = 7;  "#5" = 8
    "b6" = 8;  "6"  = 9;  "#6" = 10; "b7" = 10
    "7"  = 11
}

# Town theme chord type mapping (in C major key).
# Ordine importante: piu' specifico prima.
function Get-ChordId($chord) {
    if ($chord.suspensions -and ($chord.suspensions -contains 4) -and $chord.root -eq 5) {
        return 9   # Gsus4
    }
    if ($chord.borrowed -eq "mixolydian" -and $chord.root -eq 7) {
        return 8   # Bb (bVII mixolydian borrow)
    }
    if ($chord.applied -eq 5 -and $chord.root -eq 6) {
        return 5   # E major (V/vi)
    }
    if ($chord.type -eq 7 -and $chord.root -eq 5) {
        return 7   # G7
    }
    if ($chord.type -eq 5) {
        if ($chord.root -eq 1)                           { return 0 }  # C major
        if ($chord.root -eq 5 -and $chord.inversion -eq 1) { return 1 }  # G/B
        if ($chord.root -eq 6)                           { return 2 }  # Am
        if ($chord.root -eq 5)                           { return 3 }  # G major
        if ($chord.root -eq 4)                           { return 4 }  # F major
        if ($chord.root -eq 2)                           { return 6 }  # Dm
    }
    return 255   # unknown
}

$tonic = $data.keys[0].tonic
$base = $tonic_midi[$tonic]

# Compute total steps from longest event (notes + chords)
$max_end = 1.0
foreach ($n in $data.notes) {
    $e = $n.beat + $n.duration
    if ($e -gt $max_end) { $max_end = $e }
}
foreach ($c in $data.chords) {
    $e = $c.beat + $c.duration
    if ($e -gt $max_end) { $max_end = $e }
}
$total_steps = [int](($max_end - 1) * 4)

Write-Host "Tonic: $tonic, key MIDI base: $base"
Write-Host "Total steps (16ths): $total_steps"
Write-Host "Notes:  $($data.notes.Count)"
Write-Host "Chords: $(if ($data.chords) { $data.chords.Count } else { 0 })"

# Build melody_period array
$melody = @(0) * $total_steps
$min_p = 99999; $max_p = 0
foreach ($n in $data.notes) {
    $start = [int](($n.beat - 1) * 4)
    if (-not $sd_offset.ContainsKey($n.sd)) {
        Write-Host "WARN: unknown sd '$($n.sd)' at beat $($n.beat)" -ForegroundColor Yellow
        continue
    }
    $off = $sd_offset[$n.sd]
    $midi = $base + $off + 12 * ($n.octave + $octShift)
    $hz = 440.0 * [Math]::Pow(2, ($midi - 69) / 12.0)
    $period = [Math]::Round(3579545.0 / (32.0 * $hz))
    $melody[$start] = $period
    if ($period -lt $min_p) { $min_p = $period }
    if ($period -gt $max_p) { $max_p = $period }
}
Write-Host "Period range: $min_p - $max_p (SN max usable = 1023)"
if ($max_p -gt 1023) {
    Write-Host "WARN: alcuni periodi superano il limite 10-bit di SN76489 (1023)." -ForegroundColor Yellow
}

# Build chord_change array
$chords = @(0xFF) * $total_steps
foreach ($c in $data.chords) {
    $start = [int](($c.beat - 1) * 4)
    $cid = Get-ChordId $c
    if ($cid -eq 255) {
        Write-Host "WARN: unknown chord at beat $($c.beat): root=$($c.root) type=$($c.type) inv=$($c.inversion) applied=$($c.applied) borrowed='$($c.borrowed)' sus='$($c.suspensions -join ",")'" -ForegroundColor Yellow
    }
    $chords[$start] = $cid
}

# Emit C
$o = "// Generated from $jsonPath`n"
$o += "// Total steps (16ths): $total_steps`n"
$o += "// Period range: $min_p..$max_p`n`n"

$o += "static const unsigned int melody_period[$total_steps] = {`n"
for ($i = 0; $i -lt $total_steps; $i += 16) {
    $end = [Math]::Min($i + 15, $total_steps - 1)
    $line = "    " + (($melody[$i..$end] | ForEach-Object { "{0,4}" -f $_ }) -join ", ") + ","
    $o += $line + "  // step $i`n"
}
$o += "};`n`n"

$o += "static const unsigned char chord_change[$total_steps] = {`n"
for ($i = 0; $i -lt $total_steps; $i += 16) {
    $end = [Math]::Min($i + 15, $total_steps - 1)
    $line = "    " + (($chords[$i..$end] | ForEach-Object {
        if ($_ -eq 0xFF) { "0xFF" } else { "{0,4}" -f $_ }
    }) -join ", ") + ","
    $o += $line + "  // step $i`n"
}
$o += "};`n"

$o | Out-File -Encoding utf8 $outPath
Write-Host "`nC arrays written to $outPath"
