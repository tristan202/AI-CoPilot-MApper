EnableExplicit

; --- CONSTANTS ---
#AppVersion = "1.1.0"

; Browser structure
Structure BrowserInfo
  Name.s
  Path.s
EndStructure

; Language structure for dynamic menus
Structure LangInfo
  Code.s ; E.g., "DA", "EN", "DE"
  Name.s ; E.g., "Dansk", "English"
EndStructure

; Global lists
Global NewList InstalledBrowsers.BrowserInfo()
Global NewList AvailableLanguages.LangInfo()

; Settings & Files
Global IniFile.s = GetPathPart(ProgramFilename()) + "AICopilotMapper.ini"
Global AppPath.s = ProgramFilename()
Global BrowserPath.s = "" 
Global SelectedAI.s = "Gemini" 
Global TargetURL.s = "https://gemini.google.com"
Global AutoStart.i = 0
Global Language.s = "DA"
Global ButtonMode.i = 0 ; 0 = AI Mode, 1 = R-CTRL Mode, 2 = R-ALT Mode
Global hMutex, hHook

; String Variables for UI (Loaded via .lng file or fallback)
Global Txt_MsgBoxTitle.s, Txt_MsgBoxRunning.s
Global Txt_TrayTooltip.s, Txt_MenuBrowser.s, Txt_MenuAI.s
Global Txt_MenuAutoStart.s, Txt_MenuLanguage.s, Txt_MenuAbout.s, Txt_MenuExit.s
Global Txt_AboutTitle.s, Txt_AboutText.s
Global Txt_MenuMode.s, Txt_ModeAI.s, Txt_ModeCTRL.s, Txt_ModeALT.s

; Menu and Gadget IDs
Enumeration
  #AboutWin
  #About_ImageGadget
  #About_LinkGadget
  #About_TextGadget
  #About_CloseBtn
  #MainWin
  #TrayMenu
  #TrayIcon
  #AppIcon
  #Menu_AI_Gemini
  #Menu_AI_ChatGPT
  #Menu_AI_Claude
  #Menu_AI_Perplexity
  #Menu_AI_Copilot
  #Menu_AI_DeepSeek
  #Menu_Mode_AI
  #Menu_Mode_CTRL
  #Menu_Mode_ALT
  #Menu_AutoStart
  #Menu_About
  #Menu_Exit
  #Menu_Browser_Base = 100 
  #Menu_Lang_Base    = 200 ; Dynamic language items start here
EndEnumeration

; --- 1. INSTANCE CHECK (MUTEX) ---
; Placeret helt i toppen for at afvise ekstra instanser øjeblikkeligt.
Global MutexName.s = "Global\AICopilotMapper_Unique_ID"
hMutex = CreateMutex_(0, 1, @MutexName)
If GetLastError_() = 183 : End : EndIf


; --- 2. HELPER FUNCTIONS ---

; Modern replacement for keybd_event_ using SendInput_
Procedure SendKeyInput(VKey.w, Flags.l)
  Protected Input.INPUT
  Input\type = #INPUT_KEYBOARD
  Input\ki\wVk = VKey
  Input\ki\wScan = 0
  Input\ki\dwFlags = Flags
  Input\ki\time = 0
  Input\ki\dwExtraInfo = 0
  SendInput_(1, @Input, SizeOf(INPUT))
EndProcedure

; Reads a string from the Windows Registry
Procedure.s ReadRegString(hKeyRoot, KeyPath.s, ValueName.s)
  Protected hKey.i, Type.i, BufferSize.i = 1024
  Protected *Buffer = AllocateMemory(BufferSize)
  Protected Result.s = ""
  If RegOpenKeyEx_(hKeyRoot, KeyPath, 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    If RegQueryValueEx_(hKey, ValueName, 0, @Type, *Buffer, @BufferSize) = #ERROR_SUCCESS
      If Type = #REG_SZ Or Type = #REG_EXPAND_SZ
        Result = PeekS(*Buffer)
      EndIf
    EndIf
    RegCloseKey_(hKey)
  EndIf
  FreeMemory(*Buffer)
  ProcedureReturn Result
EndProcedure

; Scans the registry for installed web browsers
Procedure GetInstalledBrowsers()
  Protected hKey.i, Index.i = 0
  Protected KeyName.s = Space(256), KeyNameSize.i
  Protected SubKeyName.s, BName.s, BPath.s
  ClearList(InstalledBrowsers())
  If RegOpenKeyEx_(#HKEY_LOCAL_MACHINE, "SOFTWARE\Clients\StartMenuInternet", 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    Repeat
      KeyNameSize = 256
      If RegEnumKeyEx_(hKey, Index, @KeyName, @KeyNameSize, 0, 0, 0, 0) = #ERROR_SUCCESS
        SubKeyName = "SOFTWARE\Clients\StartMenuInternet\" + Left(KeyName, KeyNameSize)
        BName = ReadRegString(#HKEY_LOCAL_MACHINE, SubKeyName, "")
        If BName = "" : BName = Left(KeyName, KeyNameSize) : EndIf
        BPath = ReadRegString(#HKEY_LOCAL_MACHINE, SubKeyName + "\shell\open\command", "")
        If FindString(LCase(BPath), ".exe")
          BPath = Left(BPath, FindString(LCase(BPath), ".exe") + 3)
          BPath = RemoveString(BPath, #DQUOTE$)
        EndIf
        If BName <> "" And BPath <> ""
          AddElement(InstalledBrowsers())
          InstalledBrowsers()\Name = BName
          InstalledBrowsers()\Path = BPath
        EndIf
        Index + 1
      Else
        Break
      EndIf
    ForEver
    RegCloseKey_(hKey)
  EndIf
  
  ; Fallback hvis listen er tom
  If ListSize(InstalledBrowsers()) = 0
    AddElement(InstalledBrowsers())
    InstalledBrowsers()\Name = "System Default"
    InstalledBrowsers()\Path = "explorer.exe" 
  EndIf
EndProcedure

; Scans the application directory for .lng files dynamically
Procedure GetAvailableLanguages()
  Protected Directory.s = GetPathPart(ProgramFilename())
  Protected DirID.i, FileName.s, LangCode.s
  
  ClearList(AvailableLanguages())
  
  DirID = ExamineDirectory(#PB_Any, Directory, "*.lng")
  If DirID
    While NextDirectoryEntry(DirID)
      If DirectoryEntryType(DirID) = #PB_DirectoryEntry_File
        FileName = DirectoryEntryName(DirID)
        LangCode = UCase(Left(FileName, Len(FileName) - 4)) ; Remove ".lng"
        
        If OpenPreferences(Directory + FileName, #PB_UTF8)
          PreferenceGroup("Language")
          AddElement(AvailableLanguages())
          AvailableLanguages()\Code = LangCode
          AvailableLanguages()\Name = ReadPreferenceString("LanguageName", LangCode)
          ClosePreferences()
        EndIf
      EndIf
    Wend
    FinishDirectory(DirID)
  EndIf
  
  ; Fallback if no language files are found on disk
  If ListSize(AvailableLanguages()) = 0
    AddElement(AvailableLanguages())
    AvailableLanguages()\Code = "DA"
    AvailableLanguages()\Name = "Dansk"
  EndIf
EndProcedure

; Maps the selected AI to its respective URL
Procedure UpdateTargetURL()
  Select SelectedAI
    Case "ChatGPT"    : TargetURL = "https://chatgpt.com"
    Case "Claude"     : TargetURL = "https://claude.ai"
    Case "Perplexity" : TargetURL = "https://www.perplexity.ai"
    Case "Copilot"    : TargetURL = "https://copilot.microsoft.com"
    Case "DeepSeek"   : TargetURL = "https://chat.deepseek.com"
    Default           : TargetURL = "https://gemini.google.com" 
  EndSelect
EndProcedure

; Dynamic Language Loader (.lng files) with hardcoded Danish fallback
Procedure UpdateLanguageStrings()
  Protected AppName.s = "AI Copilot Mapper"
  Protected VerPrefix.s = " v" + #AppVersion + Chr(10)
  Protected LngFile.s = GetPathPart(ProgramFilename()) + Language + ".lng"
  
  ; Sæt hårdkodede standardværdier (Dansk fallback) først
  Txt_MenuMode = "Knap Funktion" : Txt_ModeAI = "AI Genvej" : Txt_ModeCTRL = "Højre CTRL" : Txt_ModeALT = "Højre ALT"
  Txt_MenuAI = "Vælg AI" : Txt_MenuBrowser = "Vælg Browser" : Txt_MenuAutoStart = "Start med Windows"
  Txt_MenuLanguage = "Sprog" : Txt_MenuExit = "Afslut" : Txt_MenuAbout = "Om programmet"
  Txt_AboutTitle = "Om " + AppName
  Txt_AboutText = AppName + VerPrefix + "Udviklet til at omkode Copilot-tasten til din foretrukne AI eller en systemtast."
  
  ; Forsøg at indlæse fra ekstern .lng fil, hvis den eksisterer
  If FileSize(LngFile) > 0
    If OpenPreferences(LngFile, #PB_UTF8)
      PreferenceGroup("Language")
      Txt_MenuMode = ReadPreferenceString("MenuMode", Txt_MenuMode)
      Txt_ModeAI = ReadPreferenceString("ModeAI", Txt_ModeAI)
      Txt_ModeCTRL = ReadPreferenceString("ModeCTRL", Txt_ModeCTRL)
      Txt_ModeALT = ReadPreferenceString("ModeALT", Txt_ModeALT)
      Txt_MenuAI = ReadPreferenceString("MenuAI", Txt_MenuAI)
      Txt_MenuBrowser = ReadPreferenceString("MenuBrowser", Txt_MenuBrowser)
      Txt_MenuAutoStart = ReadPreferenceString("MenuAutoStart", Txt_MenuAutoStart)
      Txt_MenuLanguage = ReadPreferenceString("MenuLanguage", Txt_MenuLanguage)
      Txt_MenuExit = ReadPreferenceString("MenuExit", Txt_MenuExit)
      Txt_MenuAbout = ReadPreferenceString("MenuAbout", Txt_MenuAbout)
      Txt_AboutTitle = ReadPreferenceString("AboutTitle", Txt_AboutTitle)
      Txt_AboutText = AppName + VerPrefix + ReadPreferenceString("AboutText", "Developed to remap the Copilot key.")
      ClosePreferences()
    EndIf
  EndIf
  
  Txt_MsgBoxTitle = AppName
  Txt_TrayTooltip = AppName
EndProcedure

; Builds the system tray popup menu
Procedure RebuildMenu()
  Protected Index = 0
  If CreatePopupMenu(#TrayMenu)
    ; Mode Selection
    OpenSubMenu(Txt_MenuMode)
      MenuItem(#Menu_Mode_AI, Txt_ModeAI)
      MenuItem(#Menu_Mode_CTRL, Txt_ModeCTRL)
      MenuItem(#Menu_Mode_ALT, Txt_ModeALT)
    CloseSubMenu()
    MenuBar()
    
    ; AI submenu
    OpenSubMenu(Txt_MenuAI)
      MenuItem(#Menu_AI_Gemini, "Google Gemini")
      MenuItem(#Menu_AI_ChatGPT, "OpenAI ChatGPT")
      MenuItem(#Menu_AI_Claude, "Anthropic Claude")
      MenuItem(#Menu_AI_DeepSeek, "DeepSeek")
      MenuItem(#Menu_AI_Perplexity, "Perplexity AI")
      MenuItem(#Menu_AI_Copilot, "Microsoft Copilot (Web)")
    CloseSubMenu()
    
    ; Browser submenu
    OpenSubMenu(Txt_MenuBrowser)
      ForEach InstalledBrowsers()
        MenuItem(#Menu_Browser_Base + Index, InstalledBrowsers()\Name)
        If LCase(BrowserPath) = LCase(InstalledBrowsers()\Path)
          SetMenuItemState(#TrayMenu, #Menu_Browser_Base + Index, 1)
        EndIf
        Index + 1
      Next
    CloseSubMenu()
    
    MenuBar()
    MenuItem(#Menu_AutoStart, Txt_MenuAutoStart)
    
    ; Dynamic Language Submenu
    OpenSubMenu(Txt_MenuLanguage)
      Index = 0
      ForEach AvailableLanguages()
        MenuItem(#Menu_Lang_Base + Index, AvailableLanguages()\Name)
        If UCase(Language) = UCase(AvailableLanguages()\Code)
          SetMenuItemState(#TrayMenu, #Menu_Lang_Base + Index, 1)
        EndIf
        Index + 1
      Next
    CloseSubMenu()
    
    MenuBar()
    MenuItem(#Menu_About, Txt_MenuAbout)
    MenuItem(#Menu_Exit, Txt_MenuExit)
    
    ; Set Menu Item States
    SetMenuItemState(#TrayMenu, #Menu_Mode_AI, Bool(ButtonMode = 0))
    SetMenuItemState(#TrayMenu, #Menu_Mode_CTRL, Bool(ButtonMode = 1))
    SetMenuItemState(#TrayMenu, #Menu_Mode_ALT, Bool(ButtonMode = 2))
    SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
    
    Select SelectedAI
      Case "ChatGPT"    : SetMenuItemState(#TrayMenu, #Menu_AI_ChatGPT, 1)
      Case "Claude"     : SetMenuItemState(#TrayMenu, #Menu_AI_Claude, 1)
      Case "DeepSeek"   : SetMenuItemState(#TrayMenu, #Menu_AI_DeepSeek, 1)
      Case "Perplexity" : SetMenuItemState(#TrayMenu, #Menu_AI_Perplexity, 1)
      Case "Copilot"    : SetMenuItemState(#TrayMenu, #Menu_AI_Copilot, 1)
      Default           : SetMenuItemState(#TrayMenu, #Menu_AI_Gemini, 1)
    EndSelect
  EndIf
EndProcedure

Procedure SetAutoStartRegistry(Enable.i)
  Protected hKey.i, Result.i
  Protected KeyPath.s = "Software\Microsoft\Windows\CurrentVersion\Run"
  Protected ValueName.s = "AICopilotMapper"
  Protected Path.s = Chr(34) + ProgramFilename() + Chr(34)
  Protected DataSize.i = StringByteLength(Path) + SizeOf(Character)
  Protected AccessMask.i = $0002 
  
  Result = RegOpenKeyEx_(#HKEY_CURRENT_USER, KeyPath, 0, AccessMask, @hKey)
  
  If Result = #ERROR_SUCCESS
    If Enable
      Result = RegSetValueEx_(hKey, ValueName, 0, #REG_SZ, @Path, DataSize)
    Else
      Result = RegDeleteValue_(hKey, ValueName)
    EndIf
    RegCloseKey_(hKey)
  Else
    MessageRequester("Rettighedsfejl", "Windows nægtede adgang til Autostart." + Chr(10) + "Fejlkode: " + Str(Result), #PB_MessageRequester_Warning)
  EndIf
EndProcedure

; Saves user settings to INI file
Procedure SaveSettings()
  If OpenPreferences(IniFile, #PB_UTF8) Or CreatePreferences(IniFile, #PB_UTF8)
    PreferenceGroup("Settings")
    WritePreferenceString("Browser", BrowserPath)
    WritePreferenceInteger("AutoStart", AutoStart)
    WritePreferenceString("Language", Language)
    WritePreferenceString("AI", SelectedAI)
    WritePreferenceInteger("ButtonMode", ButtonMode)
    ClosePreferences()
  EndIf
EndProcedure

; Loads user settings from INI file
Procedure LoadSettings()
  If OpenPreferences(IniFile, #PB_UTF8)
    PreferenceGroup("Settings")
    BrowserPath = ReadPreferenceString("Browser", "")
    AutoStart = ReadPreferenceInteger("AutoStart", 0)
    Language = ReadPreferenceString("Language", "DA")
    SelectedAI = ReadPreferenceString("AI", "Gemini")
    ButtonMode = ReadPreferenceInteger("ButtonMode", 0)
    ClosePreferences()
  EndIf
  
  ; Sikkerheds-fallback hvis BrowserPath er tom eller ugyldig
  If BrowserPath = ""
    If FirstElement(InstalledBrowsers())
      BrowserPath = InstalledBrowsers()\Path
    Else
      BrowserPath = "explorer.exe"
    EndIf
  EndIf
  UpdateTargetURL() 
EndProcedure


; --- 3. KEYBOARD HOOK LOGIC (With SendInput API) ---

Procedure.l KeyboardProc(nCode, wParam, lParam)
  Protected *pkbdll.KBDLLHOOKSTRUCT = lParam
  
  If nCode < 0
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  If *pkbdll\flags & $10
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  If *pkbdll\vkCode = $86 ; Copilot Key / F23
    Select ButtonMode
      Case 0 ; --- AI Shortcut Mode ---
        If wParam = #WM_KEYDOWN
          If BrowserPath = "explorer.exe"
            RunProgram(TargetURL, "", "")
          Else
            RunProgram(BrowserPath, "--app=" + TargetURL, "")
          EndIf
        EndIf
        
      Case 1, 2 ; --- Modifier Remapping Mode (SendInput) ---
        Protected VKey.w
        If ButtonMode = 1 : VKey = #VK_RCONTROL : Else : VKey = #VK_RMENU : EndIf
        
        If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
          If GetAsyncKeyState_(#VK_LSHIFT) & $8000
            SendKeyInput(#VK_LSHIFT, #KEYEVENTF_KEYUP)
          EndIf
          If GetAsyncKeyState_(#VK_LWIN) & $8000
            SendKeyInput(#VK_LWIN, #KEYEVENTF_KEYUP)
          EndIf
          
          SendKeyInput(VKey, 0)
          
        ElseIf wParam = #WM_KEYUP Or wParam = #WM_SYSKEYUP
          SendKeyInput(VKey, #KEYEVENTF_KEYUP)
        EndIf
    EndSelect
    
    ProcedureReturn 1
  EndIf

  ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
EndProcedure


; --- 4. APPLICATION INITIALIZATION ---

GetAvailableLanguages() ; Scans for languages first
GetInstalledBrowsers()
LoadSettings()
UpdateLanguageStrings()

; Hidden window to handle background events and tray menu
If OpenWindow(#MainWin, 0, 0, 0, 0, "AICopilotMapper", #PB_Window_Invisible)
  
  CatchImage(#AppIcon, ?AppIconStart, ?AppIconEnd - ?AppIconStart)
  AddSysTrayIcon(#TrayIcon, WindowID(#MainWin), ImageID(#AppIcon))
  SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip)
  RebuildMenu()
  
  hHook = SetWindowsHookEx_(13, @KeyboardProc(), GetModuleHandle_(0), 0)
  
  ; Main Event Loop
  Repeat
    Define Event.i = WaitWindowEvent()
    Select Event
      Case #PB_Event_SysTray
        If EventType() = #PB_EventType_RightClick
          DisplayPopupMenu(#TrayMenu, WindowID(#MainWin))
        EndIf
        
      Case #PB_Event_Menu
        Define MenuID.i = EventMenu()
        
        ; Handle dynamic browser clicks
        If MenuID >= #Menu_Browser_Base And MenuID < #Menu_Browser_Base + ListSize(InstalledBrowsers())
          SelectElement(InstalledBrowsers(), MenuID - #Menu_Browser_Base)
          BrowserPath = InstalledBrowsers()\Path : SaveSettings() : RebuildMenu()
          
        ; Handle dynamic language clicks
        ElseIf MenuID >= #Menu_Lang_Base And MenuID < #Menu_Lang_Base + ListSize(AvailableLanguages())
          SelectElement(AvailableLanguages(), MenuID - #Menu_Lang_Base)
          Language = AvailableLanguages()\Code
          UpdateLanguageStrings() : SaveSettings() : RebuildMenu()
          
        Else
          Select MenuID
            Case #Menu_Mode_AI    : ButtonMode = 0 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_CTRL  : ButtonMode = 1 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_ALT   : ButtonMode = 2 : SaveSettings() : RebuildMenu()
            
            Case #Menu_AI_Gemini To #Menu_AI_Copilot
              Select MenuID
                Case #Menu_AI_Gemini     : SelectedAI = "Gemini"
                Case #Menu_AI_ChatGPT    : SelectedAI = "ChatGPT"
                Case #Menu_AI_Claude     : SelectedAI = "Claude"
                Case #Menu_AI_DeepSeek   : SelectedAI = "DeepSeek"
                Case #Menu_AI_Perplexity : SelectedAI = "Perplexity"
                Case #Menu_AI_Copilot    : SelectedAI = "Copilot"
              EndSelect
              UpdateTargetURL() : SaveSettings() : RebuildMenu()

            Case #Menu_AutoStart
              AutoStart = 1 - AutoStart
              SetAutoStartRegistry(AutoStart)
              SaveSettings() : RebuildMenu()
              
            Case #Menu_About
              MessageRequester(Txt_AboutTitle, Txt_AboutText, #PB_MessageRequester_Info)
              
            Case #Menu_Exit
              Break
          EndSelect
        EndIf
    EndSelect
  Until Event = #PB_Event_CloseWindow

  ; Cleanup before exit
  If hHook : UnhookWindowsHookEx_(hHook) : EndIf
  RemoveSysTrayIcon(#TrayIcon)
  If hMutex : CloseHandle_(hMutex) : EndIf
EndIf

; Embedded resources
DataSection
  AppIconStart: 
    IncludeBinary "aicopilotmapper.ico"
  AppIconEnd:
EndDataSection
; IDE Options = PureBasic 6.30 (Windows - x64)
; CursorPosition = 3
; Folding = --
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = AICopilotMapper.exe