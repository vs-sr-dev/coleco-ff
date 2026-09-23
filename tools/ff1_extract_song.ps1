# ff1_extract_song.ps1 - Estrae un brano FF1 NES dal disassembly Disch.
#
# Decodifica i byte stream a 3 canali (sq1, sq2, tri) di una song FF1
# e produce un C array di note_event_t {period, frames} per ciascuno.
#
# I valori period sono presi tale-quale da lut_NoteFreqs (NES). Sono
# direttamente compatibili con SN76489 e AY-3-8910 perche' tutti e tre
# i chip usano la formula: period = clock/(16*f) (o equivalente per SN
# con divisore /32 ma clock 2x).
#
# Uso: powershell -File ff1_extract_song.ps1 -trackId 0x50 -outName battle
#   trackId: il valore scritto in music_track. $50=Battle, $44=OW, $46=Airship, etc.
#   outName: nome file output (-> "<outName>_song.c") e prefisso array.

param(
    [int]$trackId = 0x50,
    [string]$outName = "battle",
    [string]$dataPath = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bin\0D_8000_scoredata.bin",
    # Le due tabelle del motore audio (frequenze e durate) si leggono dal
    # banco $0D, non si copiano qui: in un repo BYOA restano nel ROM di chi
    # compila.
    [string]$bank0DPath = "$PSScriptRoot\..\FF1Disassembly-master\Final Fantasy Disassembly\bank_0D.bin",
    # Dove scrivere <outName>_song.c. Vuoto = la cartella corrente (come prima).
    [string]$outDir = ''
)

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $dataPath))
Write-Host "Loaded scoredata.bin: $($bytes.Length) bytes"

# Convert track ID to song table offset
# Engine: AND #$3F (isolate low 6 bits), SBC #1 (1-based -> 0-based), ASL*3 (*8)
$songIdx = ($trackId -band 0x3F) - 1
$tableOff = $songIdx * 8
Write-Host "Track ID `$$([Convert]::ToString($trackId,16).ToUpper()) -> song idx $songIdx -> table offset $tableOff"

# Read 3 channel pointers (little-endian 16-bit, NES addresses)
$LUT_BASE = 0x8000
$sq1_ptr = [int]$bytes[$tableOff+0] + 256 * [int]$bytes[$tableOff+1]
$sq2_ptr = [int]$bytes[$tableOff+2] + 256 * [int]$bytes[$tableOff+3]
$tri_ptr = [int]$bytes[$tableOff+4] + 256 * [int]$bytes[$tableOff+5]
$sq1_off = $sq1_ptr - $LUT_BASE
$sq2_off = $sq2_ptr - $LUT_BASE
$tri_off = $tri_ptr - $LUT_BASE
Write-Host ("Pointers (NES): SQ1=`${0:X4} SQ2=`${1:X4} TRI=`${2:X4}" -f $sq1_ptr, $sq2_ptr, $tri_ptr)
Write-Host ("File offsets:   SQ1=$sq1_off SQ2=$sq2_off TRI=$tri_off")

# lut_NoteFreqs (4 octaves x 12 notes, .WORD) a $B2F9 e lut_NoteLengths
# (6 tempos x 16 length codes, frame) a $B359 -- bank_0D.asm:2033/2048.
$b0D = [System.IO.File]::ReadAllBytes((Resolve-Path $bank0DPath))
$NOTEFREQS_OFF = 0xB2F9 - 0x8000
$NOTELENS_OFF  = 0xB359 - 0x8000
$noteFreq = @(for ($i = 0; $i -lt 48; $i++) { [int]$b0D[$NOTEFREQS_OFF + 2*$i] + 256 * [int]$b0D[$NOTEFREQS_OFF + 2*$i + 1] })
$noteLen  = @(for ($i = 0; $i -lt 96; $i++) { [int]$b0D[$NOTELENS_OFF + $i] })
# Controllo di sanita': se il banco non e' quello giusto, meglio fermarsi qui
# che scrivere un brano stonato che compila lo stesso.
if ($noteFreq[0] -ne 0x0357 -or $noteLen[0] -ne 0xC0) {
    throw "bank_0D.bin non riconosciuto: lut_NoteFreqs/lut_NoteLengths non sono dove li aspetto"
}

# Note name display
$noteName = @("C","C#","D","D#","E","F","F#","G","G#","A","A#","B")

function Decode-Channel($startOff, $name) {
    $events = New-Object System.Collections.Generic.List[object]
    $eventOffsets = New-Object System.Collections.Generic.List[int]
    $pos = $startOff
    $octave = 0
    $tempo = 0
    $loopCounter = 0           # state: 0 = no counted loop active
    $loopTargetOff = -1
    $maxIters = 20000          # higher limit since we now unroll loops
    $iter = 0

    while ($iter -lt $maxIters) {
        $iter++
        $eventStart = $pos
        $b = $bytes[$pos]
        $pos++

        if ($b -lt 0xC0) {
            $pitch = ($b -shr 4) -band 0x0F
            $lenCode = $b -band 0x0F
            if ($pitch -ge 12) { continue }
            $period = $noteFreq[$octave * 12 + $pitch]
            $frames = $noteLen[$tempo * 16 + $lenCode]
            $events.Add(@{ Period = $period; Frames = $frames })
            $eventOffsets.Add($eventStart)
        }
        elseif ($b -lt 0xD0) {
            $lenCode = $b -band 0x0F
            $frames = $noteLen[$tempo * 16 + $lenCode]
            $events.Add(@{ Period = 0; Frames = $frames })   # 0 period = rest
            $eventOffsets.Add($eventStart)
        }
        elseif ($b -eq 0xD0) {
            $loopPtr = [int]$bytes[$pos] + 256 * [int]$bytes[$pos+1]
            $pos += 2
            $loopTargetOff = $loopPtr - $LUT_BASE
            Write-Host ("  $name : D0 infinite loop -> back to offset $loopTargetOff")
            break
        }
        elseif ($b -lt 0xD8) {
            # Counted loop D1-D7. Engine: body plays (count+1) times total.
            $count = $b -band 0x07
            $loopPtr = [int]$bytes[$pos] + 256 * [int]$bytes[$pos+1]
            $pos += 2
            $loopOff = $loopPtr - $LUT_BASE

            if ($loopCounter -eq 0) {
                # First encounter: set counter, jump back to body start
                $loopCounter = $count
                $pos = $loopOff
            } else {
                $loopCounter--
                if ($loopCounter -gt 0) {
                    $pos = $loopOff   # still iterating
                }
                # else: fall through past directive (counter exhausted)
            }
        }
        elseif ($b -lt 0xDC) {
            $octave = $b - 0xD8
        }
        elseif ($b -lt 0xE0) { }
        elseif ($b -lt 0xF0) { }
        elseif ($b -lt 0xF8) { }
        elseif ($b -eq 0xF8) {
            $pos++
        }
        elseif ($b -lt 0xFF) {
            $tempo = $b - 0xF9
            if ($tempo -gt 5) { $tempo = 5 }
        }
        elseif ($b -eq 0xFF) {
            Write-Host ("  $name : end of song")
            break
        }
    }

    # Find loop_idx = first event whose source offset >= loopTargetOff.
    # Default 0 = wrap to start (works for one-shot songs without D0).
    $loopIdx = 0
    if ($loopTargetOff -ge 0) {
        for ($i = 0; $i -lt $eventOffsets.Count; $i++) {
            if ($eventOffsets[$i] -ge $loopTargetOff) {
                $loopIdx = $i
                break
            }
        }
    }
    Write-Host ("  $name : loop_idx = $loopIdx of $($events.Count) events")

    return @{ Events = $events; LoopIdx = $loopIdx }
}

Write-Host "`n--- Decoding SQ1 ---"
$sq1 = Decode-Channel $sq1_off "SQ1"
Write-Host "`n--- Decoding SQ2 ---"
$sq2 = Decode-Channel $sq2_off "SQ2"
Write-Host "`n--- Decoding TRI ---"
$tri = Decode-Channel $tri_off "TRI"

function Total-Frames($evs) {
    $t = 0
    foreach ($e in $evs) { $t += $e.Frames }
    return $t
}
$len1 = Total-Frames $sq1.Events
$len2 = Total-Frames $sq2.Events
$len3 = Total-Frames $tri.Events
Write-Host ""
Write-Host "SQ1: $($sq1.Events.Count) events, $len1 frames, loop_idx=$($sq1.LoopIdx)"
Write-Host "SQ2: $($sq2.Events.Count) events, $len2 frames, loop_idx=$($sq2.LoopIdx)"
Write-Host "TRI: $($tri.Events.Count) events, $len3 frames, loop_idx=$($tri.LoopIdx)"

function Emit-Channel($chData, $arrName) {
    $evs = $chData.Events
    $o = "static const note_event_t ${arrName}[] = {`n"
    foreach ($e in $evs) {
        $o += ("    {{ 0x{0:X4}, {1,3} }},`n" -f $e.Period, $e.Frames)
    }
    $o += "};`n"
    $o += "#define $($arrName.ToUpper())_LEN $($evs.Count)`n"
    $o += "#define $($arrName.ToUpper())_LOOP $($chData.LoopIdx)`n`n"
    return $o
}

$out = "// FF1 song extracted from disassembly via ff1_extract_song.ps1`n"
$out += "// Track ID `$$([Convert]::ToString($trackId,16).ToUpper()), song idx $songIdx`n"
$out += "// Requires note_event_t typedef in including file.`n`n"
$out += Emit-Channel $sq1 "${outName}_sq1"
$out += Emit-Channel $sq2 "${outName}_sq2"
$out += Emit-Channel $tri "${outName}_tri"

$outFile = "${outName}_song.c"
if ($outDir) { $outFile = Join-Path $outDir $outFile }
$out | Out-File -Encoding utf8 $outFile
Write-Host "`nWritten to $outFile"
