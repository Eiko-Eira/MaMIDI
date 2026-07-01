#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir A_ScriptDir

; Global Variables
global Sheets := []
global PianoMusic := ""
global CurrentPos := 1
global ActiveKeys := Map() ; Tracks each specific key and its unique release timer

; GUI Control References
global DDL, RemainingNotesBox, ProgBar
global ChordDelayInput, HoldMinInput, HoldMaxInput

; --- GUI Setup ---
MyGui := Gui("+AlwaysOnTop", "Pro AutoPiano")
MyGui.OnEvent("Close", (*) => ExitApp())
MyGui.BackColor := "FFFFFF"
MyGui.SetFont("s10", "Calibri")

MyGui.AddText("w550 Center c000000", "----------------------------------------SELECT SHEET-----------------------------------------")
DDL := MyGui.AddDropDownList("w550")
DDL.OnEvent("Change", LoadSheet)

MyGui.AddText("w550 Center c000000", "-----------------------------------CURRENT SHEET / NEXT NOTES-----------------------------------")

; The Remaining Active Sheet Box (Expanded to full width since the next note box is removed)
MyGui.SetFont("s12", "Calibri") 
RemainingNotesBox := MyGui.AddEdit("xm y+5 w550 h120 ReadOnly BackgroundFFFFFF c000000") 

; Reset font for the rest of the GUI
MyGui.SetFont("s10", "Calibri") 

RestartBtn := MyGui.AddButton("xm y+10 w140 h30", "Restart Song")
RestartBtn.OnEvent("Click", RestartSong)

MyGui.AddText("xm w550 Center c000000", "----------------------------------------PROGRESS-----------------------------------------")
ProgBar := MyGui.AddProgress("w550 h25 Range0-100", 0)

; --- Settings Section ---
MyGui.AddText("xm w550 Center c000000", "----------------------------------------SETTINGS-----------------------------------------")

MyGui.AddText("xm y+10 w140 c000000", "Base Chord Delay (ms):")
ChordDelayInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "30")

MyGui.AddText("x+20 yp+3 w90 c000000", "Min Hold (ms):")
HoldMinInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "300")

MyGui.AddText("x+20 yp+3 w60 c000000", "Max (ms):")
HoldMaxInput := MyGui.AddEdit("x+10 yp-3 w60 Number", "700")

; Reset column position to left margin for bottom texts
MyGui.AddText("xm y+15 c000000", "Controls: Press = or [ or ] to play next note")
MyGui.AddText("xm c000000", "Credits: Crimsxn K1ra, Modified by Eikovo")
MyGui.AddText("xm c000000", "Discord: Eikovo")

; --- Populate File Dropdown (Relative Path Search) ---
SheetNames := []
TargetFolder := A_ScriptDir "\sheets"

; Check if folder exists next to the EXE/AHK file. If not, create it.
if !DirExist(TargetFolder) {
    DirCreate(TargetFolder)
    MsgBox("A 'sheets' folder has been created in the same directory as this program.`n`nPlease put your .txt sheet files inside it and restart the program.", "Folder Created")
} else {
    Loop Files, TargetFolder "\*.txt", "R"
    {
        ; Extract the path relative to the "sheets" folder
        RelativePath := StrReplace(A_LoopFilePath, TargetFolder "\", "")
        
        ; Remove the ".txt" extension for a cleaner display name
        DisplayName := RegExReplace(RelativePath, "\.txt$", "")
        
        ; Replace folder slashes with " > " for subfolders (e.g., "Anime > SongName")
        DisplayName := StrReplace(DisplayName, "\", " > ")
        
        Sheets.Push({display: DisplayName, path: A_LoopFilePath})
        SheetNames.Push(DisplayName)
    }

    if (SheetNames.Length > 0) {
        DDL.Add(SheetNames)
        DDL.Choose(1) ; Select the first item by default
        LoadSheet(DDL) ; Automatically load the first sheet on startup
    } else {
        MsgBox("No .txt files were found inside the 'sheets' folder.`n`nPath: " TargetFolder, "No Sheets Found")
    }
}

MyGui.Show("AutoSize Center")


; --- Logic Functions ---

LoadSheet(Ctrl, *) {
    global PianoMusic, CurrentPos, Sheets
    SelectedDisplay := Ctrl.Text
    if (SelectedDisplay == "")
        return

    for item in Sheets {
        if (item.display == SelectedDisplay) {
            
            ; Read the exact text inside the text file
            RawContents := FileRead(item.path)
            
            ; Clean all whitespace, linebreaks, backslashes, AND the | symbol out of the raw text for playing
            PianoMusic := RegExReplace(RawContents, "[\r\n\s\\|]")
            
            ; Reset states
            ReleaseAllKeys()
            CurrentPos := 1
            break
        }
    }
    UpdateDisplay()
}

RestartSong(*) {
    global CurrentPos
    ReleaseAllKeys()
    CurrentPos := 1
    UpdateDisplay()
}

UpdateDisplay() {
    global PianoMusic, CurrentPos, RemainingNotesBox, ProgBar

    if (PianoMusic == "") {
        RemainingNotesBox.Value := ""
        ProgBar.Value := 0
        return
    }

    TotalLen := StrLen(PianoMusic)
    if (TotalLen == 0) {
        RemainingNotesBox.Value := ""
        ProgBar.Value := 0
        return
    }

    ; Grab a large chunk of upcoming notes (300 characters) starting from the current position
    RemainingNextNotes := SubStr(PianoMusic, CurrentPos, 300)

    RemainingNotesBox.Value := RemainingNextNotes
    
    ProgBar.Value := ((CurrentPos - 1) / TotalLen) * 100
}

; Immediately cancels all active holds and lifts the keys
ReleaseAllKeys() {
    global ActiveKeys
    for keyToRelease, TimerFunc in ActiveKeys {
        SetTimer(TimerFunc, 0)  ; Stop the scheduled timer
        try SendEvent("{" keyToRelease " Up}")
    }
    ActiveKeys.Clear()
}

; Function assigned to release a specific single key naturally over time
ReleaseSingleKey(keyToRelease) {
    global ActiveKeys
    try SendEvent("{" keyToRelease " Up}")
    
    ; Remove it from our tracking map once it's lifted
    if ActiveKeys.Has(keyToRelease) {
        ActiveKeys.Delete(keyToRelease)
    }
}

PlayNextNote() {
    global PianoMusic, CurrentPos, ActiveKeys
    global ChordDelayInput, HoldMinInput, HoldMaxInput
    
    if (PianoMusic == "")
        return

    ; Safely read dynamic values on-the-fly (with fallbacks if inputs are left blank)
    currentChordDelay := IsInteger(ChordDelayInput.Value) ? Integer(ChordDelayInput.Value) : 30
    currentMinHold    := IsInteger(HoldMinInput.Value) ? Integer(HoldMinInput.Value) : 300
    currentMaxHold    := IsInteger(HoldMaxInput.Value) ? Integer(HoldMaxInput.Value) : 700

    ; Swap safety check to prevent Random() from failing if Min is larger than Max
    if (currentMinHold > currentMaxHold) {
        temp := currentMinHold
        currentMinHold := currentMaxHold
        currentMaxHold := temp
    }

    TotalLen := StrLen(PianoMusic)
    if (CurrentPos > TotalLen) {
        CurrentPos := 1 
    }

    if (CurrentPos <= TotalLen) {
        
        ; Match one note "a" or one chord "[abc]"
        if (RegExMatch(PianoMusic, "(\[[^\]]*\]|.)", &Match, CurrentPos)) {
            
            ; 1. Lift up any keys from the PREVIOUS keystroke before striking the new ones
            ReleaseAllKeys()

            MatchedStr := Match[1]
            CurrentPos += StrLen(MatchedStr)

            ; Remove brackets to get raw chord letters
            Keys := Trim(MatchedStr, "[]")

            ; Convert the chord to an array of single characters
            KeyArray := StrSplit(Keys)

            ; Humanizer: If it's a chord, there's a 40% chance we slightly shuffle the roll order.
            if (KeyArray.Length > 1 && Random(1, 10) <= 4) {
                Loop KeyArray.Length - 1 {
                    i := KeyArray.Length - A_Index + 1
                    j := Random(1, i)
                    temp := KeyArray[i]
                    KeyArray[i] := KeyArray[j]
                    KeyArray[j] := temp
                }
            }

            ; Force AutoHotkey to type Down/Up commands instantly
            SetKeyDelay(-1, 0)

            ; 2. Press new keys DOWN individually and set a UNIQUE release timer for each
            for index, keyToPress in KeyArray
            {
                try SendEvent("{" keyToPress " Down}")
                
                ; Generate a completely random hold duration just for THIS specific key
                HoldDuration := Random(currentMinHold, currentMaxHold)
                
                ; Bind this specific key to the release function so it remembers which one to lift
                BoundReleaseFunc := ReleaseSingleKey.Bind(keyToPress)
                ActiveKeys[keyToPress] := BoundReleaseFunc
                
                ; Start the timer for this single key
                SetTimer(BoundReleaseFunc, -HoldDuration)
                
                ; Add a slightly randomized delay between keys in a chord
                if (KeyArray.Length > 1 && index < KeyArray.Length) {
                    
                    ; Calculate variance: -15% up to +75% based on our dynamic ChordDelay setting
                    MinDelay := Round(currentChordDelay * 0.85)
                    MaxDelay := Round(currentChordDelay * 1.75)
                    
                    ; Fallbacks to prevent calculation errors under extreme user settings
                    if (MinDelay < 1)
                        MinDelay := 1
                    if (MaxDelay < MinDelay)
                        MaxDelay := MinDelay

                    ActualDelay := Random(MinDelay, MaxDelay)
                    Sleep(ActualDelay)
                }
            }
        }
    }

    UpdateDisplay()
}

; --- Hotkeys ---
; The #HotIf prevents these hotkeys from running when the piano GUI is active.
#HotIf !WinActive("ahk_id " MyGui.Hwnd)
$=::
$[::
$]:: {
    PlayNextNote()
}
#HotIf
