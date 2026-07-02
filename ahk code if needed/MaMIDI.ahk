#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True ; Prevents the script from accidentally triggering its own hotkeys

SetWorkingDir A_ScriptDir

; Global Variables
global Sheets := []
global PianoMusic := ""
global CurrentPos := 1
global ActiveKeys := Map() 
global NoteTimestamps := [] 
global KeyStates := Map()  ; Strictly tracks if a key is currently held down

; GUI Control References
global DDL, RemainingNotesBox, ProgBar, NPSText, ForceWhiteKeysCheck, RestartBtn
global ChordDelayInput, HoldMinInput, HoldMaxInput

; --- GUI Setup ---
MyGui := Gui("+AlwaysOnTop", "MaMIDI Player")
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.BackColor := "FFFFFF"
MyGui.SetFont("s10", "Calibri")

MyGui.AddText("w550 Center c000000", "----------------------------------------SELECT SHEET-----------------------------------------")

; Dropdown and Refresh Button
DDL := MyGui.AddDropDownList("xm w460")
DDL.OnEvent("Change", LoadSheet)
RefreshBtn := MyGui.AddButton("x+10 yp-1 w80 h26", "Refresh")
RefreshBtn.OnEvent("Click", RefreshFolder)

MyGui.AddText("xm w550 Center c000000", "-----------------------------------CURRENT SHEET / NEXT NOTES-----------------------------------")

; Tiny instruction for the click-to-skip feature
MyGui.SetFont("s9 Italic", "Calibri")
MyGui.AddText("xm y+2 w550 Center c555555", "(Click any note inside the box below to instantly skip to it)")

MyGui.SetFont("s12 Norm", "Calibri") 
RemainingNotesBox := MyGui.AddEdit("xm y+5 w550 h120 ReadOnly BackgroundFFFFFF c000000") 
MyGui.SetFont("s10", "Calibri") 

RestartBtn := MyGui.AddButton("xm y+10 w140 h30", "Restart Song")
RestartBtn.OnEvent("Click", RestartSong)

MyGui.AddText("xm w550 Center c000000", "----------------------------------------PROGRESS & STATS-----------------------------------------")
ProgBar := MyGui.AddProgress("w550 h25 Range0-100", 0)

; NPS Display and Force White Keys Toggle
MyGui.AddText("xm y+10 w100 c000000", "Active NPS:")

MyGui.SetFont("Bold")
NPSText := MyGui.AddText("x+5 yp w50 c000000", "0")
MyGui.SetFont("Norm")

ForceWhiteKeysCheck := MyGui.AddCheckbox("x+50 yp c000000", "Force White Keys (No Black Keys)")
ForceWhiteKeysCheck.Value := 0
ForceWhiteKeysCheck.OnEvent("Click", (*) => UpdateDisplay())

SetTimer(UpdateNPS, 100)

; --- Settings Section ---
MyGui.AddText("xm w550 Center c000000", "----------------------------------------SETTINGS-----------------------------------------")

MyGui.AddText("xm y+10 w140 c000000", "Base Chord Delay (ms):")
ChordDelayInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "30")

MyGui.AddText("x+20 yp+3 w90 c000000", "Min Hold (ms):")
HoldMinInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "300")

MyGui.AddText("x+20 yp+3 w60 c000000", "Max (ms):")
HoldMaxInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "700")

MyGui.AddText("xm y+15 c000000", "Controls: Press = or - to advance to the next note")
MyGui.AddText("xm y+10 c000000", "Credits: Crimsxn K1ra / AstroidLord")
MyGui.AddText("xm c000000", "Developer: Eikovo")

; Initialize everything on startup
RefreshFolder()

MyGui.Show("AutoSize Center")
OnMessage(0x0202, ClickToSkip)


; --- Logic Functions ---

; Fast forwards the tracker past any spaces or visual pipes so they aren't played
AdvancePastSpaces() {
    global CurrentPos, PianoMusic
    TotalLen := StrLen(PianoMusic)
    while (CurrentPos <= TotalLen && (SubStr(PianoMusic, CurrentPos, 1) == " " || SubStr(PianoMusic, CurrentPos, 1) == "|")) {
        CurrentPos++
    }
}

; Scans the sheets folder and updates the DropDownList dynamically
RefreshFolder(*) {
    global Sheets, SheetNames, DDL
    TargetFolder := A_ScriptDir "\sheets"
    
    Sheets := []
    SheetNames := []
    DDL.Delete() ; Clear current items
    
    if !DirExist(TargetFolder) {
        DirCreate(TargetFolder)
        MsgBox("A 'sheets' folder has been created.`nPut your .txt sheets inside and click Refresh.", "Folder Created")
        return
    }
    
    Loop Files, TargetFolder "\*.txt", "R" {
        RelativePath := StrReplace(A_LoopFilePath, TargetFolder "\", "")
        DisplayName := RegExReplace(RelativePath, "\.txt$", "")
        DisplayName := StrReplace(DisplayName, "\", " > ")
        Sheets.Push({display: DisplayName, path: A_LoopFilePath})
        SheetNames.Push(DisplayName)
    }

    if (SheetNames.Length > 0) {
        DDL.Add(SheetNames)
        DDL.Choose(1)
        LoadSheet(DDL)
    } else {
        global PianoMusic := ""
        UpdateDisplay()
    }
}

; Runs whenever a mouse click is released anywhere in the script
ClickToSkip(wParam, lParam, msg, hwnd) {
    global RemainingNotesBox, CurrentPos, PianoMusic, RestartBtn
    
    if (PianoMusic != "" && hwnd == RemainingNotesBox.Hwnd) {
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
    global KeyStates
    
    ; Strip the "$" used in the hotkey definition for checking
    baseKey := StrReplace(ThisHotkey, "$", "")
    
    ; True Anti-Spam: If the key is already marked as down, ignore Windows auto-repeat completely.
    if (KeyStates.Has(baseKey) && KeyStates[baseKey]) {
        return 
    }
    
    ; Mark the key as held down
    KeyStates[baseKey] := true
    PlayNextNote()
}

ResetKeyHold(ThisHotkey) {
    global KeyStates
    
    ; Strip the "$" and " Up" from the hotkey name to find the base key
    baseKey := StrReplace(ThisHotkey, "$", "")
    baseKey := StrReplace(baseKey, " Up", "")
    
    KeyStates[baseKey] := false
}

LoadSheet(Ctrl, *) {
    global PianoMusic, CurrentPos, Sheets
    SelectedDisplay := Ctrl.Text
    if (SelectedDisplay == "") {
        return
    }

    for item in Sheets {
        if (item.display == SelectedDisplay) {
            RawContents := FileRead(item.path)
            
            ; Strips Enters, Tabs, and slashes, but KEEPS Spaces and |
            PianoMusic := RegExReplace(RawContents, "[\r\n\t\\]")
            
            ReleaseAllKeys()
            CurrentPos := 1
            AdvancePastSpaces()
            break
        }
    }
    UpdateDisplay()
}

RestartSong(*) {
    global CurrentPos
    ReleaseAllKeys()
    CurrentPos := 1
    AdvancePastSpaces()
    UpdateDisplay()
}

MapToWhiteKey(char) {
    static SymbolMap := Map("!", "1", "@", "2", "#", "3", "$", "4", "%", "5", "^", "6", "&", "7", "*", "8", "(", "9", ")", "0")
    if SymbolMap.Has(char) {
        return SymbolMap[char]
    }
    return StrLower(char)
}

UpdateDisplay() {
    global PianoMusic, CurrentPos, RemainingNotesBox, ProgBar, ForceWhiteKeysCheck

    if (PianoMusic == "") {
        RemainingNotesBox.Value := ""
        ProgBar.Value := 0
        return
    }

    TotalLen := StrLen(PianoMusic)
    if (TotalLen == 0) {
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

UpdateNPS() {
    global NoteTimestamps, NPSText
    CurrentTime := A_TickCount
    while (NoteTimestamps.Length > 0 && CurrentTime - NoteTimestamps[1] > 1000) {
        NoteTimestamps.RemoveAt(1)
    }
    NPSText.Value := NoteTimestamps.Length
}

ReleaseAllKeys() {
    global ActiveKeys
    for keyToRelease, TimerFunc in ActiveKeys {
        SetTimer(TimerFunc, 0)
        try SendEvent("{" keyToRelease " Up}")
    }
    ActiveKeys.Clear()
}

ReleaseSingleKey(keyToRelease) {
    global ActiveKeys
    try SendEvent("{" keyToRelease " Up}")
    if (ActiveKeys.Has(keyToRelease)) {
        ActiveKeys.Delete(keyToRelease)
    }
}

PlayNextNote() {
    global PianoMusic, CurrentPos, ActiveKeys, NoteTimestamps
    global ChordDelayInput, HoldMinInput, HoldMaxInput, ForceWhiteKeysCheck
    
    if (PianoMusic == "") {
        return
    }

    currentChordDelay := IsInteger(ChordDelayInput.Value) ? Integer(ChordDelayInput.Value) : 30
    currentMinHold    := IsInteger(HoldMinInput.Value) ? Integer(HoldMinInput.Value) : 300
    currentMaxHold    := IsInteger(HoldMaxInput.Value) ? Integer(HoldMaxInput.Value) : 700

    if (currentMinHold > currentMaxHold) {
        temp := currentMinHold
        currentMinHold := currentMaxHold
        currentMaxHold := temp
    }

    ; Skip any spaces right before we process the note
    AdvancePastSpaces()

    TotalLen := StrLen(PianoMusic)
    if (CurrentPos > TotalLen) {
        CurrentPos := 1 
        AdvancePastSpaces()
    }

    if (CurrentPos <= TotalLen) {
        if (RegExMatch(PianoMusic, "(\[[^\]]*\]|.)", &Match, CurrentPos)) {
            ReleaseAllKeys()
            MatchedStr := Match[1]
            CurrentPos += StrLen(MatchedStr)
            
            ; Instantly skip trailing spaces so the GUI updates nicely to the exact next real note
            AdvancePastSpaces()

            Keys := Trim(MatchedStr, "[]")
            
            ; Cleanup just in case a user put spaces or pipes inside a chord bracket [a | b c]
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

            SetKeyDelay(-1, 0)

            for index, keyToPress in KeyArray {
                ; Skip execution if the key somehow ends up blank
                if (keyToPress == "") {
                    continue
                }

                try SendEvent("{" keyToPress " Down}")
                
                ; Add this specific keystroke to our active NPS tracking
                NoteTimestamps.Push(A_TickCount)
                
                HoldDuration := Random(currentMinHold, currentMaxHold)
                BoundReleaseFunc := ReleaseSingleKey.Bind(keyToPress)
                ActiveKeys[keyToPress] := BoundReleaseFunc
                SetTimer(BoundReleaseFunc, -HoldDuration)
                
                if (KeyArray.Length > 1 && index < KeyArray.Length) {
                    MinDelay := Round(currentChordDelay * 0.85)
                    MaxDelay := Round(currentChordDelay * 1.75)
                    
                    if (MinDelay < 1) {
                        MinDelay := 1
                    }
                    if (MaxDelay < MinDelay) {
                        MaxDelay := MinDelay
                    }
                    Sleep(Random(MinDelay, MaxDelay))
                }
            }
        }
    }
    UpdateDisplay()
}

; --- Hardcoded Hotkeys ---
; The #HotIf prevents these hotkeys from running when the piano GUI is actively clicked/focused.
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
