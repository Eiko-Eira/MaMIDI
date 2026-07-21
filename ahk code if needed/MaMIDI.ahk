#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True

SetWorkingDir A_ScriptDir

; --- Global State Variables ---
global CurrentMode := "TXT" 
global Sheets := []
global SheetNames := []
global ActiveKeys := Map()
global OldestKeyQueue := [] 
global NoteTimestamps := [] 
global KeyStates := Map()
global SustainIsDown := false

; AutoPlayer (MIDI) Variables
global PlaybackTimeline := []
global IsAutoPlaying := false
global AutoIndex := 1
global AutoPauseOffset := 0
global AutoStartTime := 0
global LastGuiUpdate := 0
global AvailableTracks := ["All Tracks"]
global AutoSpeedMultiplier := 1.0 

; Force Windows into High-Resolution Timer mode (1ms)
DllCall("Winmm\timeBeginPeriod", "UInt", 1)
OnExit((*) => DllCall("Winmm\timeEndPeriod", "UInt", 1))

; --- Virtual Piano MIDI Translation Map (61 Keys) ---
global MIDIMap := Map(
    36, "1", 37, "!", 38, "2", 39, "@", 40, "3", 41, "4", 42, "$", 43, "5", 44, "%", 45, "6", 46, "^", 47, "7", 48, "8", 49, "*", 50, "9", 51, "(", 52, "0",
    53, "q", 54, "Q", 55, "w", 56, "W", 57, "e", 58, "E", 59, "r", 60, "t", 61, "T", 62, "y", 63, "Y", 64, "u", 65, "i", 66, "I", 67, "o", 68, "O", 69, "p", 70, "P",
    71, "a", 72, "s", 73, "S", 74, "d", 75, "D", 76, "f", 77, "g", 78, "G", 79, "h", 80, "H", 81, "j", 82, "J", 83, "k", 84, "l", 85, "L",
    86, "z", 87, "Z", 88, "x", 89, "c", 90, "C", 91, "v", 92, "V", 93, "b", 94, "B", 95, "n", 96, "m"
)

; --- GUI Setup ---
MyGui := Gui("+AlwaysOnTop", "MaMIDI Player v2.4.2")
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.BackColor := "FFFFFF"
MyGui.SetFont("s10 Bold", "Calibri")

MyGui.AddText("w550 Center c000000", "------------------------------------------MODE SELECT------------------------------------------")
MyGui.SetFont("s10 Norm", "Calibri")

ModeRadios := MyGui.AddRadio("xm y+10 Checked vModeTXT", "Manual Mode (Plays .txt files)")
ModeRadios.OnEvent("Click", ChangeMode)
AutoModeRadio := MyGui.AddRadio("x+20 yp vModeMIDI", "AutoPlayer Mode (Plays .mid files)")
AutoModeRadio.OnEvent("Click", ChangeMode)

MyGui.SetFont("s10 Bold", "Calibri")
MyGui.AddText("xm w550 Center c000000", "----------------------------------------SELECT SHEET-----------------------------------------")
MyGui.SetFont("s10 Norm", "Calibri")

DDL := MyGui.AddDropDownList("xm w460")
DDL.OnEvent("Change", LoadSheetWrapper)
RefreshBtn := MyGui.AddButton("x+10 yp-1 w80 h26", "Refresh")
RefreshBtn.OnEvent("Click", RefreshFolder)

MyGui.SetFont("s10 Bold", "Calibri")
MyGui.AddText("xm w550 Center c000000", "-----------------------------------CURRENT SHEET / NEXT NOTES-----------------------------------")
MyGui.SetFont("s9 Italic", "Calibri")
global SkipHint := MyGui.AddText("xm y+2 w550 Center c555555", "(TXT Mode: Click any note inside the box below to instantly skip to it)")

MyGui.SetFont("s12 Norm", "Calibri") 
RemainingNotesBox := MyGui.AddEdit("xm y+5 w550 h120 ReadOnly BackgroundFFFFFF c000000") 
MyGui.SetFont("s10", "Calibri") 

RestartBtn := MyGui.AddButton("xm y+10 w140 h30", "Restart Song")
RestartBtn.OnEvent("Click", RestartSong)

MyGui.SetFont("s10 Bold", "Calibri")
MyGui.AddText("xm w550 Center c000000", "----------------------------------------PROGRESS & STATS-----------------------------------------")
MyGui.SetFont("s10 Norm", "Calibri")
ProgBar := MyGui.AddProgress("w550 h25 Range0-100", 0)

MyGui.AddText("xm y+10 w100 c000000", "Active NPS:")
MyGui.SetFont("Bold")
NPSText := MyGui.AddText("x+5 yp w50 c000000", "0")
MyGui.SetFont("Norm")

ForceWhiteKeysCheck := MyGui.AddCheckbox("x+50 yp c000000", "TXT Mode: Force White Keys")
ForceWhiteKeysCheck.Value := 0
ForceWhiteKeysCheck.OnEvent("Click", (*) => UpdateDisplay())
SetTimer(UpdateNPS, 100)

MyGui.SetFont("s10 Bold", "Calibri")
MyGui.AddText("xm w550 Center c000000", "----------------------------------------GLOBAL SETTINGS-----------------------------------------")
MyGui.SetFont("s10 Norm", "Calibri")

MyGui.AddText("xm y+10 w150 c000000", "Total Chord Delay (ms):")
ChordDelayInput := MyGui.AddEdit("x+10 yp-3 w50 Number", "10")

MyGui.AddText("x+15 yp+3 w80 c000000", "Min Hold:")
HoldMinInput := MyGui.AddEdit("x+5 yp-3 w50 Number", "30")

MyGui.AddText("x+15 yp+3 w60 c000000", "Max:")
HoldMaxInput := MyGui.AddEdit("x+5 yp-3 w50 Number", "250")

MyGui.AddText("xm y+15 w130 c000000", "AutoPlayer Max NPS:")
AutoNPSInput := MyGui.AddEdit("x+5 yp-3 w40 Number", "15")

MyGui.AddText("x+15 yp+3 c000000", "Speed:")
SpeedSlider := MyGui.AddSlider("x+5 yp-3 w120 Range20-200 ToolTip", 100)
SpeedSlider.OnEvent("Change", OnSpeedChange)
global SpeedText := MyGui.AddText("x+5 yp+3 w40 c000000", "100%")

MyGui.SetFont("s10 Bold", "Calibri")
MyGui.AddText("xm y+15 c000000", "MIDI Features:")
MyGui.SetFont("s10 Norm", "Calibri")

MyGui.AddText("x+5 yp c000000", "Play Track:")
global TrackDDL := MyGui.AddDropDownList("x+5 yp-3 w100 Choose1", AvailableTracks)
TrackDDL.OnEvent("Change", ReloadMIDI)

SustainCheck := MyGui.AddCheckbox("x+10 yp+3 c000000", "Sustain (Spacebar)")
VelocityCheck := MyGui.AddCheckbox("xm y+10 c000000", "Velocity-Based Holds")
OctaveFoldCheck := MyGui.AddCheckbox("x+20 yp c000000", "Fix 88-Key (Octave Fold)")
OctaveFoldCheck.OnEvent("Click", ReloadMIDI)

global ControlText := MyGui.AddText("xm y+15 w550 c000000", "Controls: Press = or - to manually advance notes.")
MyGui.AddText("xm y+10 c000000", "Credits: Crimsxn K1ra / AstroidLord / Eikovo")

RefreshFolder()
MyGui.Show("AutoSize Center")
OnMessage(0x0202, ClickToSkip)


; --- Utility Functions ---
PreciseSleep(ms) {
    if (ms <= 0) {
        return
    }
    DllCall("Sleep", "UInt", ms)
}


; --- Real-Time Speed Slider Logic ---
OnSpeedChange(Ctrl, *) {
    global AutoStartTime, IsAutoPlaying, SpeedText, AutoSpeedMultiplier
    
    newSpeedVal := Ctrl.Value
    SpeedText.Value := newSpeedVal "%"
    newSpeed := newSpeedVal / 100.0
    
    if (IsAutoPlaying) {
        virtualTime := (A_TickCount - AutoStartTime) * AutoSpeedMultiplier
        AutoStartTime := A_TickCount - (virtualTime / newSpeed)
    }
    
    AutoSpeedMultiplier := newSpeed
}


; --- Mode Switching & Loading Logic ---
ChangeMode(*) {
    global CurrentMode, ModeRadios
    savedState := MyGui.Submit(false)
    
    StopAutoPlayer()
    ReleaseAllKeys()
    NoteTimestamps := []

    if (savedState.ModeTXT == 1) {
        CurrentMode := "TXT"
        ControlText.Value := "Controls: Press = or - to manually advance notes."
        SkipHint.Value := "(TXT Mode: Click any note inside the box below to instantly skip to it)"
    } else {
        CurrentMode := "MIDI"
        ControlText.Value := "Controls: Press `` (Backtick) to Play/Pause the AutoPlayer."
        SkipHint.Value := "(AutoPlayer Mode: Note display is read-only)"
    }
    RefreshFolder()
}

RefreshFolder(*) {
    global Sheets, SheetNames, DDL, CurrentMode
    TargetFolder := (CurrentMode == "TXT") ? A_ScriptDir "\sheets" : A_ScriptDir "\MIDI"
    Ext := (CurrentMode == "TXT") ? "*.txt" : "*.mid"
    
    Sheets := []
    SheetNames := []
    DDL.Delete()
    
    if !DirExist(TargetFolder) {
        DirCreate(TargetFolder)
        MsgBox("A '" TargetFolder "' folder has been created.`nPut your files inside and click Refresh.", "Folder Created")
        return
    }
    
    Loop Files, TargetFolder "\" Ext, "R" {
        RelativePath := StrReplace(A_LoopFilePath, TargetFolder "\", "")
        DisplayName := RegExReplace(RelativePath, "\.(txt|mid)$", "")
        DisplayName := StrReplace(DisplayName, "\", " > ")
        Sheets.Push({display: DisplayName, path: A_LoopFilePath})
        SheetNames.Push(DisplayName)
    }

    if (SheetNames.Length > 0) {
        DDL.Add(SheetNames)
        DDL.Choose(1)
        LoadSheetWrapper(DDL)
    } else {
        ClearDisplay()
    }
}

LoadSheetWrapper(Ctrl, *) {
    LoadSheet(Ctrl.Text)
}

ReloadMIDI(*) {
    global CurrentMode, DDL
    if (CurrentMode == "MIDI") {
        LoadSheet(DDL.Text)
    }
}

LoadSheet(SelectedDisplay) {
    global CurrentMode, Sheets, PianoMusic, CurrentPos, AutoIndex, AutoPauseOffset, PlaybackTimeline, NoteTimestamps, TrackDDL, AvailableTracks
    
    if (SelectedDisplay == "") {
        return
    }

    StopAutoPlayer()
    ReleaseAllKeys()
    NoteTimestamps := [] 

    for item in Sheets {
        if (item.display == SelectedDisplay) {
            if (CurrentMode == "TXT") {
                RawContents := FileRead(item.path)
                PianoMusic := RegExReplace(RawContents, "[\r\n\t\\]")
                CurrentPos := 1
                AdvancePastSpaces()
            } 
            else if (CurrentMode == "MIDI") {
                MyGui.Title := "MaMIDI Player (PARSING MIDI...)"
                PlaybackTimeline := ParseBinaryMIDI(item.path)
                AutoIndex := 1
                AutoPauseOffset := 0
                MyGui.Title := "MaMIDI Player v2.4.2"
            }
            break
        }
    }
    UpdateDisplay()
}

RestartSong(*) {
    global CurrentMode, CurrentPos, AutoIndex, AutoPauseOffset, NoteTimestamps
    StopAutoPlayer()
    ReleaseAllKeys()
    NoteTimestamps := []
    
    if (CurrentMode == "TXT") {
        CurrentPos := 1
        AdvancePastSpaces()
    } else {
        AutoIndex := 1
        AutoPauseOffset := 0
    }
    UpdateDisplay()
}

ClearDisplay() {
    global PianoMusic := "", PlaybackTimeline := []
    RemainingNotesBox.Value := ""
    ProgBar.Value := 0
}

UpdateDisplay() {
    global CurrentMode, PianoMusic, CurrentPos, PlaybackTimeline, AutoIndex, TrackDDL
    global RemainingNotesBox, ProgBar, ForceWhiteKeysCheck

    if (CurrentMode == "TXT") {
        TotalLen := StrLen(PianoMusic)
        if (TotalLen == 0) {
            ClearDisplay()
            return
        }

        RemainingNextNotes := SubStr(PianoMusic, CurrentPos, 300)
        if (ForceWhiteKeysCheck.Value) {
            ConvertedNotes := ""
            Loop StrLen(RemainingNextNotes) {
                char := SubStr(RemainingNextNotes, A_Index, 1)
                if (char == "[" || char == "]") {
                    ConvertedNotes .= char
                } else {
                    ConvertedNotes .= MapToWhiteKey(char)
                }
            }
            RemainingNextNotes := ConvertedNotes
        }
        RemainingNotesBox.Value := RemainingNextNotes
        ProgBar.Value := ((CurrentPos - 1) / TotalLen) * 100
    } 
    else if (CurrentMode == "MIDI") {
        TotalLen := PlaybackTimeline.Length
        if (TotalLen == 0) {
            ClearDisplay()
            return
        }
        
        displayStr := ""
        selectedTrack := TrackDDL.Text
        maxIter := Min(AutoIndex + 150, TotalLen)
        
        Loop (maxIter - AutoIndex + 1) {
            evObj := PlaybackTimeline[AutoIndex + A_Index - 1]
            
            validNotes := []
            for n in evObj.notes {
                if (selectedTrack == "All Tracks" || "Track " n.track == selectedTrack) {
                    validNotes.Push(n)
                }
            }

            if (validNotes.Length > 1) {
                displayStr .= "["
                for n in validNotes {
                    displayStr .= n.key
                }
                displayStr .= "] "
            } else if (validNotes.Length == 1) {
                displayStr .= validNotes[1].key " "
            }
        }
        
        RemainingNotesBox.Value := displayStr
        ProgBar.Value := (AutoIndex / TotalLen) * 100
    }
}


; --- AutoPlayer Engine (MIDI) ---

StopAutoPlayer() {
    global IsAutoPlaying, RemainingNotesBox
    IsAutoPlaying := false
    SetTimer(ProcessMIDI, 0)
    MyGui.Title := "MaMIDI Player v2.4.2"
    RemainingNotesBox.Opt("BackgroundFFFFFF")
    RemainingNotesBox.Redraw()
}

ToggleAutoPlayer() {
    global IsAutoPlaying, AutoStartTime, AutoPauseOffset, PlaybackTimeline, AutoIndex, RemainingNotesBox, AutoSpeedMultiplier
    
    if (CurrentMode != "MIDI" || PlaybackTimeline.Length == 0) {
        return
    }

    if (IsAutoPlaying) {
        IsAutoPlaying := false
        SetTimer(ProcessMIDI, 0)
        AutoPauseOffset := (A_TickCount - AutoStartTime) * AutoSpeedMultiplier
        ReleaseAllKeys() 
        MyGui.Title := "MaMIDI Player (PAUSED)"
        RemainingNotesBox.Opt("BackgroundFFCCCC") 
        RemainingNotesBox.Redraw()
    } else {
        if (AutoIndex > PlaybackTimeline.Length) {
            AutoIndex := 1
            AutoPauseOffset := 0
        }
        IsAutoPlaying := true
        AutoStartTime := A_TickCount - (AutoPauseOffset / AutoSpeedMultiplier)
        MyGui.Title := "MaMIDI Player (PLAYING)"
        RemainingNotesBox.Opt("BackgroundCCFFCC") 
        RemainingNotesBox.Redraw()
        SetTimer(ProcessMIDI, 1) 
    }
}

ProcessMIDI() {
    global IsAutoPlaying, PlaybackTimeline, AutoIndex, AutoStartTime, NoteTimestamps, LastGuiUpdate
    global ChordDelayInput, HoldMinInput, HoldMaxInput, AutoNPSInput, ActiveKeys, OldestKeyQueue, AutoSpeedMultiplier
    global SustainCheck, VelocityCheck, TrackDDL, SustainIsDown
    
    if (!IsAutoPlaying) {
        SetTimer(ProcessMIDI, 0)
        return
    }

    currentTime := (A_TickCount - AutoStartTime) * AutoSpeedMultiplier
    selectedTrack := TrackDDL.Text
    
    while (AutoIndex <= PlaybackTimeline.Length && PlaybackTimeline[AutoIndex].timeMs <= currentTime) {
        evObj := PlaybackTimeline[AutoIndex]
        
        ; 1. Process MIDI Sustain Pedal Events
        if (SustainCheck.Value) {
            for sus in evObj.sustains {
                if (sus.val >= 64 && !SustainIsDown) {
                    try SendEvent("{Space Down}")
                    SustainIsDown := true
                } else if (sus.val < 64 && SustainIsDown) {
                    try SendEvent("{Space Up}")
                    SustainIsDown := false
                }
            }
        }

        ; 2. Filter Notes by Selected Track
        filteredNotes := []
        for n in evObj.notes {
            if (selectedTrack == "All Tracks" || "Track " n.track == selectedTrack) {
                filteredNotes.Push(n)
            }
        }

        if (filteredNotes.Length == 0 && evObj.sustains.Length == 0) {
            AutoIndex++
            continue
        }

        if (filteredNotes.Length > 0) {
            
            tickNow := A_TickCount
            while (NoteTimestamps.Length > 0 && tickNow - NoteTimestamps[1] > 1000) {
                NoteTimestamps.RemoveAt(1)
            }

            NoteTimestamps.Push(A_TickCount)

            CurrentNPS := NoteTimestamps.Length
            polyLimit := (CurrentNPS >= 5) ? 4 : 5 

            currentMinHold := IsInteger(HoldMinInput.Text) ? Integer(HoldMinInput.Text) : 30
            currentMaxHold := IsInteger(HoldMaxInput.Text) ? Integer(HoldMaxInput.Text) : 250
            if (currentMinHold > currentMaxHold) {
                temp := currentMinHold
                currentMinHold := currentMaxHold
                currentMaxHold := temp
            }

            ; Dynamic Hold Logic (overridden if Velocity is unchecked)
            if (!VelocityCheck.Value) {
                if (CurrentNPS >= 10) {
                    currentMinHold := 10
                    currentMaxHold := 35
                } else if (CurrentNPS >= 5) {
                    currentMinHold := 30
                    currentMaxHold := 250
                }
            }

            limit := IsInteger(AutoNPSInput.Text) ? Integer(AutoNPSInput.Text) : 15
            allowedNotes := (limit > 0) ? (limit - NoteTimestamps.Length) : 999
            
            notesToPlay := filteredNotes
            if (limit > 0 && notesToPlay.Length > allowedNotes) {
                if (allowedNotes <= 0) {
                    AutoIndex++
                    currentTime := (A_TickCount - AutoStartTime) * AutoSpeedMultiplier 
                    continue
                }
                notesToPlay := []
                startIndex := filteredNotes.Length - allowedNotes + 1
                Loop allowedNotes {
                    notesToPlay.Push(filteredNotes[startIndex + A_Index - 1])
                }
            }

            ; --- Adaptive Polyphony Limit ---
            if (notesToPlay.Length <= polyLimit) {
                while (ActiveKeys.Count + notesToPlay.Length > polyLimit && OldestKeyQueue.Length > 0) {
                    oldKey := OldestKeyQueue.RemoveAt(1)
                    if ActiveKeys.Has(oldKey) {
                        SetTimer(ActiveKeys[oldKey], 0)
                        try SendEvent("{" oldKey " Up}")
                        ActiveKeys.Delete(oldKey)
                    }
                }
            }

            ; Scale chord delay with playback speed
            rawChordDelay := IsInteger(ChordDelayInput.Text) ? Integer(ChordDelayInput.Text) : 10
            currentChordDelay := rawChordDelay / AutoSpeedMultiplier
            delayPerNote := (notesToPlay.Length > 1) ? (currentChordDelay / (notesToPlay.Length - 1)) : 0
            
            delayAdded := 0
            for index, note in notesToPlay {
                
                ; NATURAL RESTRIKE LIFT-OFF GAP:
                if ActiveKeys.Has(note.key) {
                    SetTimer(ActiveKeys[note.key], 0)
                    try SendEvent("{" note.key " Up}")
                    ActiveKeys.Delete(note.key)
                    
                    gap := Random(25, 45)
                    PreciseSleep(gap)
                    delayAdded += gap
                }

                try SendEvent("{" note.key " Down}")
                OldestKeyQueue.Push(note.key)
                
                HoldDuration := Random(currentMinHold, currentMaxHold)
                if (VelocityCheck.Value) {
                    velRatio := note.vel / 127.0
                    HoldDuration := currentMinHold + (currentMaxHold - currentMinHold) * velRatio
                }
                
                ; ASYNCHRONOUS RELEASE HUMANIZER:
                HoldDuration := Max(currentMinHold, Min(currentMaxHold, HoldDuration + Random(-25, 25)))
                scaledHold := HoldDuration / AutoSpeedMultiplier
                
                BoundReleaseFunc := ReleaseSingleKey.Bind(note.key)
                ActiveKeys[note.key] := BoundReleaseFunc
                SetTimer(BoundReleaseFunc, -scaledHold)
                
                if (notesToPlay.Length > 1 && index < notesToPlay.Length) {
                    sleepMs := Round(delayPerNote)
                    PreciseSleep(sleepMs)
                    delayAdded += sleepMs
                }
            }
            AutoStartTime += delayAdded
        }
        
        AutoIndex++
        currentTime := (A_TickCount - AutoStartTime) * AutoSpeedMultiplier 
    }

    if (A_TickCount - LastGuiUpdate > 100) {
        UpdateDisplay()
        LastGuiUpdate := A_TickCount
    }

    if (AutoIndex > PlaybackTimeline.Length) {
        StopAutoPlayer()
        ReleaseAllKeys()
        UpdateDisplay()
    }
}


; --- Custom Binary MIDI Parser ---

ReadBE(f, bytes) {
    val := 0
    Loop bytes {
        val := (val << 8) | f.ReadUChar()
    }
    return val
}

ReadVLQ(f) {
    val := 0
    Loop {
        b := f.ReadUChar()
        val := (val << 7) | (b & 0x7F)
        if !(b & 0x80) {
            break
        }
    }
    return val
}

ParseBinaryMIDI(filePath) {
    global MIDIMap, OctaveFoldCheck, TrackDDL, AvailableTracks
    f := FileOpen(filePath, "r")
    if !f {
        return []
    }

    f.Seek(4, 0)
    headerLen := ReadBE(f, 4)
    midiFormat := ReadBE(f, 2)
    numTracks := ReadBE(f, 2)
    ticksPerQNote := ReadBE(f, 2)
    
    RawEvents := []
    UniqueTracks := Map()

    Loop numTracks {
        TrackIdx := A_Index
        chunkType := f.Read(4)
        if (chunkType != "MTrk") {
            f.Close()
            return []
        }
        
        chunkLen := ReadBE(f, 4)
        endPos := f.Pos + chunkLen
        runningStatus := 0
        absTick := 0

        while (f.Pos < endPos && !f.AtEOF) {
            delta := ReadVLQ(f)
            absTick += delta

            statusByte := f.ReadUChar()
            if (statusByte < 0x80) {
                f.Pos -= 1
                statusByte := runningStatus
            } else {
                runningStatus := statusByte
            }

            eventType := statusByte >> 4
            channel := statusByte & 0x0F

            if (eventType == 0x9) { 
                pitch := f.ReadUChar()
                vel := f.ReadUChar()
                
                ; 88-Key Octave Fold Fix
                if (OctaveFoldCheck.Value) {
                    while (pitch < 36) {
                        pitch += 12
                    }
                    while (pitch > 96) {
                        pitch -= 12
                    }
                }

                if (MIDIMap.Has(pitch) && vel > 0) {
                    RawEvents.Push({type: "note", tick: absTick, pitch: pitch, vel: vel, key: MIDIMap[pitch], track: TrackIdx})
                    UniqueTracks[TrackIdx] := true
                }
            } 
            else if (eventType == 0xB) { 
                ccNum := f.ReadUChar()
                ccVal := f.ReadUChar()
                if (ccNum == 64) {
                    RawEvents.Push({type: "sustain", tick: absTick, val: ccVal})
                }
            }
            else if (eventType == 0x8) { 
                pitch := f.ReadUChar()
                vel := f.ReadUChar()
            } 
            else if (statusByte == 0xFF) { 
                metaType := f.ReadUChar()
                metaLen := ReadVLQ(f)
                if (metaType == 0x51) { 
                    tempo := ReadBE(f, 3)
                    RawEvents.Push({type: "tempo", tick: absTick, tempo: tempo})
                } else {
                    f.Pos += metaLen
                }
            } 
            else if (statusByte == 0xF0 || statusByte == 0xF7) { 
                len := ReadVLQ(f)
                f.Pos += len
            } 
            else if (eventType == 0xC || eventType == 0xD) { 
                f.Pos += 1 
            } 
            else { 
                f.Pos += 2 
            }
        }
    }
    f.Close()

    AvailableTracks := ["All Tracks"]
    for k, v in UniqueTracks {
        AvailableTracks.Push("Track " k)
    }
    
    prevSel := TrackDDL.Text
    TrackDDL.Delete()
    TrackDDL.Add(AvailableTracks)
    found := false
    for idx, item in AvailableTracks {
        if (item == prevSel) {
            TrackDDL.Choose(idx)
            found := true
            break
        }
    }
    if (!found) {
        TrackDDL.Choose(1)
    }

    str := ""
    for index, ev in RawEvents {
        priority := (ev.type == "tempo") ? 0 : 1
        str .= Format("{:015}_{}_{:08}`n", ev.tick, priority, index)
    }
    str := Sort(str)
    
    SortedEvents := []
    Loop Parse, str, "`n", "`r" {
        if (A_LoopField == "") {
            continue
        }
        origIndex := Integer(SubStr(A_LoopField, 19, 8))
        SortedEvents.Push(RawEvents[origIndex])
    }
    RawEvents := SortedEvents

    CurrentTempo := 500000 
    CurrentTick := 0
    CurrentTimeMs := 0.0
    TimedEvents := []
    
    for ev in RawEvents {
        deltaTicks := ev.tick - CurrentTick
        MsPerTick := CurrentTempo / 1000 / ticksPerQNote
        CurrentTimeMs += deltaTicks * MsPerTick
        CurrentTick := ev.tick
        
        if (ev.type == "tempo") {
            CurrentTempo := ev.tempo
        } else {
            ev.timeMs := CurrentTimeMs
            TimedEvents.Push(ev)
        }
    }

    FinalTimeline := []
    i := 1
    while (i <= TimedEvents.Length) {
        baseTime := TimedEvents[i].timeMs
        chordNotes := []
        sustainEvents := []
        
        while (i <= TimedEvents.Length && Abs(TimedEvents[i].timeMs - baseTime) <= 5) {
            if (TimedEvents[i].type == "note") {
                chordNotes.Push(TimedEvents[i])
            } else if (TimedEvents[i].type == "sustain") {
                sustainEvents.Push(TimedEvents[i])
            }
            i++
        }
        
        ; --- Limit Chords to 5 Notes & Drop the Bass ---
        if (chordNotes.Length > 5) {
            Loop chordNotes.Length {
                j := A_Index
                Loop chordNotes.Length - j {
                    if (chordNotes[A_Index].pitch > chordNotes[A_Index+1].pitch) {
                        temp := chordNotes[A_Index]
                        chordNotes[A_Index] := chordNotes[A_Index+1]
                        chordNotes[A_Index+1] := temp
                    }
                }
            }
            chordNotes.RemoveAt(1, chordNotes.Length - 5)
        }
        FinalTimeline.Push({timeMs: baseTime, notes: chordNotes, sustains: sustainEvents})
    }
    
    return FinalTimeline
}


; --- TXT Manual Functions ---

AdvancePastSpaces() {
    global CurrentPos, PianoMusic
    TotalLen := StrLen(PianoMusic)
    while (CurrentPos <= TotalLen && (SubStr(PianoMusic, CurrentPos, 1) == " " || SubStr(PianoMusic, CurrentPos, 1) == "|")) {
        CurrentPos++
    }
}

ClickToSkip(wParam, lParam, msg, hwnd) {
    global RemainingNotesBox, CurrentPos, PianoMusic, RestartBtn, CurrentMode
    if (CurrentMode == "TXT" && PianoMusic != "" && hwnd == RemainingNotesBox.Hwnd) {
        pos := SendMessage(0x00B0, 0, 0, RemainingNotesBox.Hwnd)
        caretPos := pos & 0xFFFF 
        if (caretPos > 0) {
            CurrentPos += caretPos
            TotalLen := StrLen(PianoMusic)
            if (CurrentPos > TotalLen) {
                CurrentPos := TotalLen
            }
            ReleaseAllKeys()
            AdvancePastSpaces()
            UpdateDisplay()
            try RestartBtn.Focus()
        }
    }
}

PlayNextNoteAction(ThisHotkey) {
    global KeyStates, CurrentMode
    if (CurrentMode != "TXT") {
        return
    }
    baseKey := StrReplace(ThisHotkey, "$", "")
    if (KeyStates.Has(baseKey) && KeyStates[baseKey]) {
        return 
    }
    KeyStates[baseKey] := true
    PlayNextNote()
}

ResetKeyHold(ThisHotkey) {
    global KeyStates
    baseKey := StrReplace(ThisHotkey, "$", "")
    baseKey := StrReplace(baseKey, " Up", "")
    KeyStates[baseKey] := false
}

MapToWhiteKey(char) {
    static SymbolMap := Map("!", "1", "@", "2", "#", "3", "$", "4", "%", "5", "^", "6", "&", "7", "*", "8", "(", "9", ")", "0")
    if SymbolMap.Has(char) {
        return SymbolMap[char]
    }
    return StrLower(char)
}

ReleaseAllKeys() {
    global ActiveKeys, OldestKeyQueue, SustainIsDown
    for keyToRelease, TimerFunc in ActiveKeys {
        SetTimer(TimerFunc, 0)
        try SendEvent("{" keyToRelease " Up}")
    }
    ActiveKeys.Clear()
    OldestKeyQueue := []
    
    if (SustainIsDown) {
        try SendEvent("{Space Up}")
        SustainIsDown := false
    }
}

ReleaseSingleKey(keyToRelease) {
    global ActiveKeys
    try SendEvent("{" keyToRelease " Up}")
    if (ActiveKeys.Has(keyToRelease)) {
        ActiveKeys.Delete(keyToRelease)
    }
}

UpdateNPS() {
    global NoteTimestamps, NPSText
    CurrentTime := A_TickCount
    while (NoteTimestamps.Length > 0 && CurrentTime - NoteTimestamps[1] > 1000) {
        NoteTimestamps.RemoveAt(1)
    }
    NPSText.Value := NoteTimestamps.Length
}

PlayNextNote() {
    global PianoMusic, CurrentPos, ActiveKeys, NoteTimestamps, OldestKeyQueue
    global ChordDelayInput, HoldMinInput, HoldMaxInput, ForceWhiteKeysCheck
    
    if (PianoMusic == "") {
        return
    }

    tickNow := A_TickCount
    while (NoteTimestamps.Length > 0 && tickNow - NoteTimestamps[1] > 1000) {
        NoteTimestamps.RemoveAt(1)
    }

    NoteTimestamps.Push(A_TickCount)

    CurrentNPS := NoteTimestamps.Length
    polyLimit := (CurrentNPS >= 5) ? 4 : 5 

    currentMinHold := IsInteger(HoldMinInput.Text) ? Integer(HoldMinInput.Text) : 30
    currentMaxHold := IsInteger(HoldMaxInput.Text) ? Integer(HoldMaxInput.Text) : 250
    if (currentMinHold > currentMaxHold) {
        temp := currentMinHold
        currentMinHold := currentMaxHold
        currentMaxHold := temp
    }

    if (CurrentNPS >= 10) {
        currentMinHold := 10
        currentMaxHold := 35
    } else if (CurrentNPS >= 5) {
        currentMinHold := 30
        currentMaxHold := 250
    }

    AdvancePastSpaces()
    TotalLen := StrLen(PianoMusic)
    if (CurrentPos > TotalLen) {
        CurrentPos := 1 
        AdvancePastSpaces()
    }

    if (CurrentPos <= TotalLen) {
        if (RegExMatch(PianoMusic, "(\[[^\]]*\]|.)", &Match, CurrentPos)) {
            MatchedStr := Match[1]
            CurrentPos += StrLen(MatchedStr)
            AdvancePastSpaces()
            Keys := Trim(MatchedStr, "[]")
            Keys := StrReplace(Keys, " ", "")
            Keys := StrReplace(Keys, "|", "")

            if (ForceWhiteKeysCheck.Value) {
                ConvertedKeys := ""
                Loop StrLen(Keys) {
                    char := SubStr(Keys, A_Index, 1)
                    ConvertedKeys .= MapToWhiteKey(char)
                }
                Keys := ConvertedKeys
            }
            KeyArray := StrSplit(Keys)
            if (KeyArray.Length > 1) {
                Loop KeyArray.Length - 1 {
                    i := KeyArray.Length - A_Index + 1
                    j := Random(1, i)
                    temp := KeyArray[i]
                    KeyArray[i] := KeyArray[j]
                    KeyArray[j] := temp
                }
            }

            if (KeyArray.Length <= polyLimit) {
                while (ActiveKeys.Count + KeyArray.Length > polyLimit && OldestKeyQueue.Length > 0) {
                    oldKey := OldestKeyQueue.RemoveAt(1)
                    if ActiveKeys.Has(oldKey) {
                        SetTimer(ActiveKeys[oldKey], 0)
                        try SendEvent("{" oldKey " Up}")
                        ActiveKeys.Delete(oldKey)
                    }
                }
            }

            SetKeyDelay(-1, 0)
            currentChordDelay := IsInteger(ChordDelayInput.Text) ? Integer(ChordDelayInput.Text) : 10
            delayPerNote := (KeyArray.Length > 1) ? (currentChordDelay / (KeyArray.Length - 1)) : 0

            for index, keyToPress in KeyArray {
                if (keyToPress == "") {
                    continue
                }
                
                if ActiveKeys.Has(keyToPress) {
                    SetTimer(ActiveKeys[keyToPress], 0)
                    try SendEvent("{" keyToPress " Up}")
                    ActiveKeys.Delete(keyToPress)
                    PreciseSleep(Random(25, 45))
                }

                try SendEvent("{" keyToPress " Down}")
                OldestKeyQueue.Push(keyToPress)
                
                HoldDuration := Random(currentMinHold, currentMaxHold)
                HoldDuration := Max(currentMinHold, Min(currentMaxHold, HoldDuration + Random(-25, 25)))
                
                BoundReleaseFunc := ReleaseSingleKey.Bind(keyToPress)
                ActiveKeys[keyToPress] := BoundReleaseFunc
                SetTimer(BoundReleaseFunc, -HoldDuration)
                
                if (KeyArray.Length > 1 && index < KeyArray.Length) {
                    PreciseSleep(Round(delayPerNote))
                }
            }
        }
    }
    UpdateDisplay()
}

; --- Global Hotkeys ---

$`:: {
    ToggleAutoPlayer()
}

#HotIf !WinActive("ahk_id " MyGui.Hwnd)
$=::
$-:: {
    PlayNextNoteAction(A_ThisHotkey)
}
$= Up::
$- Up:: {
    ResetKeyHold(A_ThisHotkey)
}
#HotIf
