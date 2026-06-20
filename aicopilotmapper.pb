EnableExplicit

; PureBasic does not always include a built-in declaration for this WinAPI call.
; Import the Unicode version explicitly so per-app profiles can read the
; foreground process executable name.
Import "Kernel32.lib"
  QueryFullProcessImageNameW(hProcess.i, dwFlags.l, lpExeName.i, lpdwSize.i)
EndImport

; --- CONSTANTS ---
#AppVersion = "1.2.1"

; Browser structure
Structure BrowserInfo
  Name.s
  Path.s
EndStructure

; AI service structure - built-in and user-defined services use the same list
Structure AIServiceInfo
  Name.s
  URL.s
  IsCustom.i
EndStructure

; Language structure for dynamic menus
Structure LangInfo
  Code.s ; E.g., "DA", "EN", "DE"
  Name.s ; E.g., "Dansk", "English"
EndStructure

; Simple per-app profile structure
; Mode:       -1 = inherit, 0 = AI Mode, 1 = R-CTRL Mode, 2 = R-ALT Mode
; LaunchMode: -1 = inherit, 0 = app window, 1 = normal tab, 2 = new window, 3 = system default
; Paused:     -1 = inherit, 0 = active, 1 = paused for this process
Structure AppProfileInfo
  Process.s
  Mode.i
  AIName.s
  AIURL.s
  LaunchMode.i
  Paused.i
EndStructure

; Global lists
Global NewList InstalledBrowsers.BrowserInfo()
Global NewList AvailableLanguages.LangInfo()
Global NewList AIServices.AIServiceInfo()
Global NewList AppProfiles.AppProfileInfo()

; Settings & Files
Global IniFile.s = GetPathPart(ProgramFilename()) + "AICopilotMapper.ini"
Global ProfileFile.s = GetPathPart(ProgramFilename()) + "AICopilotMapper_profiles.ini"
Global AppPath.s = ProgramFilename()
Global BrowserPath.s = "" 
Global SelectedAI.s = "Gemini" 
Global TargetURL.s = "https://gemini.google.com"
Global AutoStart.i = 0
Global Language.s = "DA"
Global ButtonMode.i = 0 ; 0 = AI Mode, 1 = R-CTRL Mode, 2 = R-ALT Mode
Global LaunchMode.i = 0 ; 0 = Browser app window, 1 = normal tab, 2 = new window, 3 = system default
Global MappingPaused.i = 0 ; runtime pause, not persisted
Global CopilotKeyDown.i = 0 ; debounce so holding the key does not repeatedly launch AI
Global ActiveRemapVKey.w = 0 ; remembers which synthetic modifier is currently held
Global hMutex, hHook

; String Variables for UI (Loaded via .lng file or fallback)
Global Txt_MsgBoxTitle.s, Txt_MsgBoxRunning.s
Global Txt_TrayTooltip.s, Txt_MenuBrowser.s, Txt_MenuAI.s
Global Txt_MenuAutoStart.s, Txt_MenuLanguage.s, Txt_MenuAbout.s, Txt_MenuExit.s
Global Txt_AboutTitle.s, Txt_AboutText.s
Global Txt_MenuMode.s, Txt_ModeAI.s, Txt_ModeCTRL.s, Txt_ModeALT.s
Global Txt_MenuLaunchMode.s, Txt_LaunchApp.s, Txt_LaunchTab.s, Txt_LaunchWindow.s, Txt_LaunchDefault.s
Global Txt_MenuPause.s, Txt_MenuProfiles.s, Txt_ProfileOpen.s, Txt_ProfileReload.s, Txt_ProfileTemplate.s
Global Txt_CustomAIAdd.s, Txt_CustomAIRemove.s

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
  #Menu_Mode_AI
  #Menu_Mode_CTRL
  #Menu_Mode_ALT
  #Menu_Launch_App
  #Menu_Launch_Tab
  #Menu_Launch_Window
  #Menu_Launch_Default
  #Menu_AutoStart
  #Menu_Pause
  #Menu_CustomAI_Add
  #Menu_CustomAI_Remove
  #Menu_Profile_Open
  #Menu_Profile_Reload
  #Menu_Profile_Template
  #Menu_About
  #Menu_Exit
  #Menu_Browser_Base = 100 
  #Menu_Lang_Base    = 200 ; Dynamic language items start here
  #Menu_AI_Base      = 300 ; Dynamic AI items start here
EndEnumeration

; --- 1. INSTANCE CHECK (MUTEX) ---
; Placeret helt i toppen for at afvise ekstra instanser øjeblikkeligt.
Global MutexName.s = "Global\AICopilotMapper_Unique_ID"
hMutex = CreateMutex_(0, 1, @MutexName)
If GetLastError_() = 183 : End : EndIf


; --- 2. HELPER FUNCTIONS ---

Procedure.i StartsWithProtocol(Text.s)
  Protected L.s = LCase(Text)
  If FindString(L, "://") > 0
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

Procedure.s NormalizeURL(URL.s)
  URL = Trim(URL)
  If URL <> "" And StartsWithProtocol(URL) = 0
    ; Local endpoints such as localhost/127.0.0.1 normally use http, everything else defaults to https.
    If Left(LCase(URL), 9) = "localhost" Or Left(URL, 9) = "127.0.0.1" Or Left(URL, 5) = "[::1]"
      URL = "http://" + URL
    Else
      URL = "https://" + URL
    EndIf
  EndIf
  ProcedureReturn URL
EndProcedure

Procedure.i BrowserIsExplicit()
  If BrowserPath <> "" And LCase(BrowserPath) <> "explorer.exe" And FileSize(BrowserPath) >= 0
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

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
  
  ; HKLM browser registration
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
  
  ; HKCU browser registration - catches some per-user installations
  Index = 0
  If RegOpenKeyEx_(#HKEY_CURRENT_USER, "SOFTWARE\Clients\StartMenuInternet", 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    Repeat
      KeyNameSize = 256
      If RegEnumKeyEx_(hKey, Index, @KeyName, @KeyNameSize, 0, 0, 0, 0) = #ERROR_SUCCESS
        SubKeyName = "SOFTWARE\Clients\StartMenuInternet\" + Left(KeyName, KeyNameSize)
        BName = ReadRegString(#HKEY_CURRENT_USER, SubKeyName, "")
        If BName = "" : BName = Left(KeyName, KeyNameSize) : EndIf
        BPath = ReadRegString(#HKEY_CURRENT_USER, SubKeyName + "\shell\open\command", "")
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

Procedure AddAIService(Name.s, URL.s, IsCustom.i)
  Name = Trim(Name)
  URL = NormalizeURL(URL)
  If Name = "" Or URL = "" : ProcedureReturn : EndIf
  
  ForEach AIServices()
    If LCase(AIServices()\Name) = LCase(Name)
      AIServices()\URL = URL
      AIServices()\IsCustom = IsCustom
      ProcedureReturn
    EndIf
  Next
  
  AddElement(AIServices())
  AIServices()\Name = Name
  AIServices()\URL = URL
  AIServices()\IsCustom = IsCustom
EndProcedure

Procedure.s GetAIURLByName(Name.s)
  ForEach AIServices()
    If LCase(AIServices()\Name) = LCase(Name)
      ProcedureReturn AIServices()\URL
    EndIf
  Next
  ProcedureReturn "https://gemini.google.com"
EndProcedure

Procedure LoadAIServices()
  Protected Count.i, I.i, Name.s, URL.s
  ClearList(AIServices())
  
  ; Built-in services
  AddAIService("Gemini", "https://gemini.google.com", 0)
  AddAIService("Kimi", "https://www.kimi.com", 0)
  AddAIService("ChatGPT", "https://chatgpt.com", 0)
  AddAIService("Claude", "https://claude.ai", 0)
  AddAIService("DeepSeek", "https://chat.deepseek.com", 0)
  AddAIService("Perplexity", "https://www.perplexity.ai", 0)
  AddAIService("Copilot", "https://copilot.microsoft.com", 0)
  
  ; Custom services from INI, e.g. local Open WebUI, Ollama WebUI, LibreChat etc.
  If OpenPreferences(IniFile, #PB_UTF8)
    PreferenceGroup("CustomAI")
    Count = ReadPreferenceInteger("Count", 0)
    For I = 1 To Count
      Name = ReadPreferenceString(Str(I) + "Name", "")
      URL = ReadPreferenceString(Str(I) + "URL", "")
      AddAIService(Name, URL, 1)
    Next
    ClosePreferences()
  EndIf
EndProcedure

Procedure SaveCustomAIServices()
  Protected Count.i = 0, I.i = 0
  If OpenPreferences(IniFile, #PB_UTF8) Or CreatePreferences(IniFile, #PB_UTF8)
    PreferenceGroup("CustomAI")
    ForEach AIServices()
      If AIServices()\IsCustom
        Count + 1
      EndIf
    Next
    WritePreferenceInteger("Count", Count)
    ForEach AIServices()
      If AIServices()\IsCustom
        I + 1
        WritePreferenceString(Str(I) + "Name", AIServices()\Name)
        WritePreferenceString(Str(I) + "URL", AIServices()\URL)
      EndIf
    Next
    ClosePreferences()
  EndIf
EndProcedure

; Maps the selected AI to its respective URL
Procedure UpdateTargetURL()
  TargetURL = GetAIURLByName(SelectedAI)
EndProcedure

Procedure AddOrEditCustomAI()
  Protected Name.s, URL.s
  Name = InputRequester("Custom AI", "Navn på AI-tjenesten:" + Chr(10) + "Eksempel: Open WebUI", "")
  If Trim(Name) = "" : ProcedureReturn : EndIf
  
  URL = InputRequester("Custom AI", "URL til AI-tjenesten:" + Chr(10) + "Eksempel: http://localhost:3000", "http://localhost:3000")
  URL = NormalizeURL(URL)
  If Trim(URL) = "" : ProcedureReturn : EndIf
  
  AddAIService(Name, URL, 1)
  SelectedAI = Trim(Name)
  UpdateTargetURL()
  SaveCustomAIServices()
EndProcedure

Procedure RemoveSelectedCustomAI()
  ForEach AIServices()
    If LCase(AIServices()\Name) = LCase(SelectedAI) And AIServices()\IsCustom
      DeleteElement(AIServices())
      SelectedAI = "Gemini"
      UpdateTargetURL()
      SaveCustomAIServices()
      ProcedureReturn
    EndIf
  Next
  MessageRequester("Custom AI", "Den valgte AI er ikke en custom AI og kan derfor ikke fjernes her.", #PB_MessageRequester_Info)
EndProcedure

Procedure.s LaunchModeName(Mode.i)
  Select Mode
    Case 0 : ProcedureReturn Txt_LaunchApp
    Case 1 : ProcedureReturn Txt_LaunchTab
    Case 2 : ProcedureReturn Txt_LaunchWindow
    Case 3 : ProcedureReturn Txt_LaunchDefault
  EndSelect
  ProcedureReturn Txt_LaunchApp
EndProcedure

Procedure LaunchTarget(URL.s, UseLaunchMode.i)
  URL = NormalizeURL(URL)
  If URL = "" : ProcedureReturn : EndIf
  
  Select UseLaunchMode
    Case 0 ; Browser app window, best with Chromium-based browsers
      If BrowserIsExplicit()
        RunProgram(BrowserPath, "--app=" + Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
      
    Case 1 ; Normal browser tab/window using selected browser if possible
      If BrowserIsExplicit()
        RunProgram(BrowserPath, Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
      
    Case 2 ; New browser window
      If BrowserIsExplicit()
        RunProgram(BrowserPath, "--new-window " + Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
      
    Case 3 ; System default browser/handler
      RunProgram(URL, "", "")
      
    Default
      RunProgram(URL, "", "")
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
  Txt_MenuLaunchMode = "Åbningsmetode" : Txt_LaunchApp = "App-vindue" : Txt_LaunchTab = "Normal fane" : Txt_LaunchWindow = "Nyt vindue" : Txt_LaunchDefault = "Systemstandard"
  Txt_MenuPause = "Pause mapping"
  Txt_MenuProfiles = "Profiler pr. app"
  Txt_ProfileOpen = "Åbn profil-fil"
  Txt_ProfileReload = "Genindlæs profiler"
  Txt_ProfileTemplate = "Opret profil-skabelon"
  Txt_CustomAIAdd = "Tilføj/ret custom AI..."
  Txt_CustomAIRemove = "Fjern valgt custom AI"
  Txt_AboutTitle = "Om " + AppName
  Txt_AboutText = AppName + VerPrefix + "Udviklet til at omkode Copilot-tasten til din foretrukne AI, en lokal AI-tjeneste eller en systemtast." + Chr(10) + Chr(10) + "Nyt i 1.2.0:" + Chr(10) + "- Custom AI og custom URL" + Chr(10) + "- Local AI endpoints" + Chr(10) + "- Key-repeat beskyttelse" + Chr(10) + "- Flere åbningsmetoder" + Chr(10) + "- Pause og profiler pr. app"
  
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
      Txt_MenuLaunchMode = ReadPreferenceString("MenuLaunchMode", Txt_MenuLaunchMode)
      Txt_LaunchApp = ReadPreferenceString("LaunchApp", Txt_LaunchApp)
      Txt_LaunchTab = ReadPreferenceString("LaunchTab", Txt_LaunchTab)
      Txt_LaunchWindow = ReadPreferenceString("LaunchWindow", Txt_LaunchWindow)
      Txt_LaunchDefault = ReadPreferenceString("LaunchDefault", Txt_LaunchDefault)
      Txt_MenuPause = ReadPreferenceString("MenuPause", Txt_MenuPause)
      Txt_MenuProfiles = ReadPreferenceString("MenuProfiles", Txt_MenuProfiles)
      Txt_ProfileOpen = ReadPreferenceString("ProfileOpen", Txt_ProfileOpen)
      Txt_ProfileReload = ReadPreferenceString("ProfileReload", Txt_ProfileReload)
      Txt_ProfileTemplate = ReadPreferenceString("ProfileTemplate", Txt_ProfileTemplate)
      Txt_CustomAIAdd = ReadPreferenceString("CustomAIAdd", Txt_CustomAIAdd)
      Txt_CustomAIRemove = ReadPreferenceString("CustomAIRemove", Txt_CustomAIRemove)
      Txt_AboutTitle = ReadPreferenceString("AboutTitle", Txt_AboutTitle)
      Txt_AboutText = AppName + VerPrefix + ReadPreferenceString("AboutText", "Developed to remap the Copilot key.")
      ClosePreferences()
    EndIf
  EndIf
  
  Txt_MsgBoxTitle = AppName
  Txt_TrayTooltip = AppName
EndProcedure

Procedure UpdateTrayTooltip()
  Protected Tip.s
  Tip = "AI Copilot Mapper v" + #AppVersion + Chr(10)
  If MappingPaused
    Tip + "Status: Paused" + Chr(10)
  EndIf
  Tip + "AI: " + SelectedAI + Chr(10)
  Tip + "Mode: "
  Select ButtonMode
    Case 0 : Tip + Txt_ModeAI
    Case 1 : Tip + Txt_ModeCTRL
    Case 2 : Tip + Txt_ModeALT
  EndSelect
  Tip + Chr(10) + "Åbning: " + LaunchModeName(LaunchMode)
  SysTrayIconToolTip(#TrayIcon, Tip)
EndProcedure

; Builds the system tray popup menu
Procedure RebuildMenu()
  Protected Index.i = 0
  If IsMenu(#TrayMenu)
    FreeMenu(#TrayMenu)
  EndIf
  
  If CreatePopupMenu(#TrayMenu)
    ; Mode Selection
    OpenSubMenu(Txt_MenuMode)
      MenuItem(#Menu_Mode_AI, Txt_ModeAI)
      MenuItem(#Menu_Mode_CTRL, Txt_ModeCTRL)
      MenuItem(#Menu_Mode_ALT, Txt_ModeALT)
    CloseSubMenu()
    MenuBar()
    
    ; AI submenu - now dynamic, so custom services appear automatically
    OpenSubMenu(Txt_MenuAI)
      Index = 0
      ForEach AIServices()
        If AIServices()\IsCustom
          MenuItem(#Menu_AI_Base + Index, AIServices()\Name + " (Custom)")
        Else
          Select AIServices()\Name
            Case "Gemini"     : MenuItem(#Menu_AI_Base + Index, "Google Gemini")
            Case "ChatGPT"    : MenuItem(#Menu_AI_Base + Index, "OpenAI ChatGPT")
            Case "Claude"     : MenuItem(#Menu_AI_Base + Index, "Anthropic Claude")
            Case "Perplexity" : MenuItem(#Menu_AI_Base + Index, "Perplexity AI")
            Case "Copilot"    : MenuItem(#Menu_AI_Base + Index, "Microsoft Copilot (Web)")
            Default           : MenuItem(#Menu_AI_Base + Index, AIServices()\Name)
          EndSelect
        EndIf
        If LCase(SelectedAI) = LCase(AIServices()\Name)
          SetMenuItemState(#TrayMenu, #Menu_AI_Base + Index, 1)
        EndIf
        Index + 1
      Next
      MenuBar()
      MenuItem(#Menu_CustomAI_Add, Txt_CustomAIAdd)
      MenuItem(#Menu_CustomAI_Remove, Txt_CustomAIRemove)
    CloseSubMenu()
    
    ; Browser submenu
    OpenSubMenu(Txt_MenuBrowser)
      Index = 0
      ForEach InstalledBrowsers()
        MenuItem(#Menu_Browser_Base + Index, InstalledBrowsers()\Name)
        If LCase(BrowserPath) = LCase(InstalledBrowsers()\Path)
          SetMenuItemState(#TrayMenu, #Menu_Browser_Base + Index, 1)
        EndIf
        Index + 1
      Next
    CloseSubMenu()
    
    ; Launch mode submenu
    OpenSubMenu(Txt_MenuLaunchMode)
      MenuItem(#Menu_Launch_App, Txt_LaunchApp)
      MenuItem(#Menu_Launch_Tab, Txt_LaunchTab)
      MenuItem(#Menu_Launch_Window, Txt_LaunchWindow)
      MenuItem(#Menu_Launch_Default, Txt_LaunchDefault)
    CloseSubMenu()
    
    MenuBar()
    MenuItem(#Menu_AutoStart, Txt_MenuAutoStart)
    MenuItem(#Menu_Pause, Txt_MenuPause)
    
    ; Per-app profiles submenu
    OpenSubMenu(Txt_MenuProfiles)
      MenuItem(#Menu_Profile_Open, Txt_ProfileOpen)
      MenuItem(#Menu_Profile_Reload, Txt_ProfileReload)
      MenuItem(#Menu_Profile_Template, Txt_ProfileTemplate)
    CloseSubMenu()
    
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
    SetMenuItemState(#TrayMenu, #Menu_Launch_App, Bool(LaunchMode = 0))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Tab, Bool(LaunchMode = 1))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Window, Bool(LaunchMode = 2))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Default, Bool(LaunchMode = 3))
    SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
    SetMenuItemState(#TrayMenu, #Menu_Pause, MappingPaused)
  EndIf
  
  UpdateTrayTooltip()
EndProcedure

Procedure.i SetAutoStartRegistry(Enable.i)
  Protected hKey.i, Result.i
  Protected KeyPath.s = "Software\Microsoft\Windows\CurrentVersion\Run"
  Protected ValueName.s = "AICopilotMapper"
  Protected Path.s = Chr(34) + ProgramFilename() + Chr(34)
  Protected DataSize.i = StringByteLength(Path) + SizeOf(Character)
  Protected AccessMask.i = $0002 ; KEY_SET_VALUE
  
  Result = RegOpenKeyEx_(#HKEY_CURRENT_USER, KeyPath, 0, AccessMask, @hKey)
  
  If Result = #ERROR_SUCCESS
    If Enable
      Result = RegSetValueEx_(hKey, ValueName, 0, #REG_SZ, @Path, DataSize)
    Else
      Result = RegDeleteValue_(hKey, ValueName)
      If Result <> #ERROR_SUCCESS
        ; If the value was already gone, treat it as success.
        If Result = 2
          Result = #ERROR_SUCCESS
        EndIf
      EndIf
    EndIf
    RegCloseKey_(hKey)
  EndIf
  
  If Result <> #ERROR_SUCCESS
    MessageRequester("Rettighedsfejl", "Windows nægtede adgang til Autostart." + Chr(10) + "Fejlkode: " + Str(Result), #PB_MessageRequester_Warning)
    ProcedureReturn 0
  EndIf
  
  ProcedureReturn 1
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
    WritePreferenceInteger("LaunchMode", LaunchMode)
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
    LaunchMode = ReadPreferenceInteger("LaunchMode", 0)
    ClosePreferences()
  EndIf
  
  ; Sikkerheds-fallback hvis BrowserPath er tom eller ugyldig
  If BrowserPath = "" Or (LCase(BrowserPath) <> "explorer.exe" And FileSize(BrowserPath) < 0)
    If FirstElement(InstalledBrowsers())
      BrowserPath = InstalledBrowsers()\Path
    Else
      BrowserPath = "explorer.exe"
    EndIf
  EndIf
  
  If ButtonMode < 0 Or ButtonMode > 2 : ButtonMode = 0 : EndIf
  If LaunchMode < 0 Or LaunchMode > 3 : LaunchMode = 0 : EndIf
  If GetAIURLByName(SelectedAI) = "https://gemini.google.com" And LCase(SelectedAI) <> "gemini"
    SelectedAI = "Gemini"
  EndIf
  UpdateTargetURL() 
EndProcedure

Procedure CreateProfileTemplate(Overwrite.i)
  Protected File.i
  If FileSize(ProfileFile) >= 0 And Overwrite = 0 : ProcedureReturn : EndIf
  
  File = CreateFile(#PB_Any, ProfileFile, #PB_UTF8)
  If File
    WriteStringN(File, "; AI Copilot Mapper - profiler pr. app")
    WriteStringN(File, "; Sæt Count til antal aktive profiler, og udfyld felterne nedenfor.")
    WriteStringN(File, "; Process er exe-navnet på det aktive program, f.eks. notepad.exe, code.exe eller firefox.exe.")
    WriteStringN(File, "; Mode: -1=arv standard, 0=AI, 1=Højre CTRL, 2=Højre ALT")
    WriteStringN(File, "; LaunchMode: -1=arv standard, 0=app-vindue, 1=normal fane, 2=nyt vindue, 3=systemstandard")
    WriteStringN(File, "; Paused: -1=arv standard, 0=aktiv, 1=pause mapping for denne app")
    WriteStringN(File, "")
    WriteStringN(File, "[Profiles]")
    WriteStringN(File, "Count=0")
    WriteStringN(File, "")
    WriteStringN(File, "; Eksempel:")
    WriteStringN(File, "; Count=1")
    WriteStringN(File, "; 1Process=notepad.exe")
    WriteStringN(File, "; 1Mode=0")
    WriteStringN(File, "; 1AIName=ChatGPT")
    WriteStringN(File, "; 1AIURL=")
    WriteStringN(File, "; 1LaunchMode=1")
    WriteStringN(File, "; 1Paused=0")
    WriteStringN(File, "")
    WriteStringN(File, "; Local AI eksempel:")
    WriteStringN(File, "; 2Process=code.exe")
    WriteStringN(File, "; 2Mode=0")
    WriteStringN(File, "; 2AIName=")
    WriteStringN(File, "; 2AIURL=http://localhost:3000")
    WriteStringN(File, "; 2LaunchMode=1")
    WriteStringN(File, "; 2Paused=0")
    CloseFile(File)
  EndIf
EndProcedure

Procedure LoadAppProfiles()
  Protected Count.i, I.i
  ClearList(AppProfiles())
  CreateProfileTemplate(0)
  
  If OpenPreferences(ProfileFile, #PB_UTF8)
    PreferenceGroup("Profiles")
    Count = ReadPreferenceInteger("Count", 0)
    For I = 1 To Count
      If ReadPreferenceString(Str(I) + "Process", "") <> ""
        AddElement(AppProfiles())
        AppProfiles()\Process = LCase(Trim(ReadPreferenceString(Str(I) + "Process", "")))
        AppProfiles()\Mode = ReadPreferenceInteger(Str(I) + "Mode", -1)
        AppProfiles()\AIName = Trim(ReadPreferenceString(Str(I) + "AIName", ""))
        AppProfiles()\AIURL = NormalizeURL(ReadPreferenceString(Str(I) + "AIURL", ""))
        AppProfiles()\LaunchMode = ReadPreferenceInteger(Str(I) + "LaunchMode", -1)
        AppProfiles()\Paused = ReadPreferenceInteger(Str(I) + "Paused", -1)
      EndIf
    Next
    ClosePreferences()
  EndIf
EndProcedure

Procedure OpenProfileFile()
  CreateProfileTemplate(0)
  RunProgram("notepad.exe", Chr(34) + ProfileFile + Chr(34), "")
EndProcedure

Procedure.s GetActiveProcessName()
  Protected hWnd.i, PID.i, hProcess.i
  Protected Buffer.s = Space(1024), Size.i = 1024
  Protected Result.s = ""
  
  hWnd = GetForegroundWindow_()
  If hWnd = 0 : ProcedureReturn "" : EndIf
  GetWindowThreadProcessId_(hWnd, @PID)
  If PID = 0 : ProcedureReturn "" : EndIf
  
  ; PROCESS_QUERY_LIMITED_INFORMATION = $1000
  hProcess = OpenProcess_($1000, 0, PID)
  If hProcess
    If QueryFullProcessImageNameW(hProcess, 0, @Buffer, @Size)
      Result = LCase(GetFilePart(Left(Buffer, Size)))
    EndIf
    CloseHandle_(hProcess)
  EndIf
  
  ProcedureReturn Result
EndProcedure

Procedure.i FindActiveProfile()
  Protected Proc.s = GetActiveProcessName()
  If Proc = "" : ProcedureReturn 0 : EndIf
  
  ForEach AppProfiles()
    If LCase(AppProfiles()\Process) = Proc
      ProcedureReturn 1
    EndIf
  Next
  ProcedureReturn 0
EndProcedure


; --- 3. KEYBOARD HOOK LOGIC (With SendInput API) ---

Procedure.l KeyboardProc(nCode, wParam, lParam)
  Protected *pkbdll.KBDLLHOOKSTRUCT = lParam
  Protected EffMode.i, EffLaunchMode.i, EffPaused.i
  Protected EffURL.s
  Protected VKey.w
  
  If nCode < 0
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  ; Ignore injected keystrokes so our synthetic RCTRL/RALT does not loop back into the hook.
  If *pkbdll\flags & $10
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  If *pkbdll\vkCode = $86 ; Copilot Key / F23
    EffMode = ButtonMode
    EffLaunchMode = LaunchMode
    EffPaused = MappingPaused
    EffURL = TargetURL
    
    ; Per-app profile overrides are resolved at the moment the key is pressed.
    If FindActiveProfile()
      If AppProfiles()\Paused = 1
        EffPaused = 1
      ElseIf AppProfiles()\Paused = 0 And MappingPaused = 0
        EffPaused = 0
      EndIf
      
      If AppProfiles()\Mode >= 0 And AppProfiles()\Mode <= 2
        EffMode = AppProfiles()\Mode
      EndIf
      
      If AppProfiles()\LaunchMode >= 0 And AppProfiles()\LaunchMode <= 3
        EffLaunchMode = AppProfiles()\LaunchMode
      EndIf
      
      If AppProfiles()\AIURL <> ""
        EffURL = AppProfiles()\AIURL
      ElseIf AppProfiles()\AIName <> ""
        EffURL = GetAIURLByName(AppProfiles()\AIName)
      EndIf
    EndIf
    
    If EffPaused
      CopilotKeyDown = 0
      ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
    EndIf
    
    If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
      ; Debounce: only act once per physical key press.
      If CopilotKeyDown = 0
        CopilotKeyDown = 1
        
        Select EffMode
          Case 0 ; --- AI Shortcut Mode ---
            LaunchTarget(EffURL, EffLaunchMode)
            
          Case 1, 2 ; --- Modifier Remapping Mode (SendInput) ---
            If EffMode = 1 : VKey = #VK_RCONTROL : Else : VKey = #VK_RMENU : EndIf
            ActiveRemapVKey = VKey
            
            ; The physical Copilot combo often arrives with modifiers; release them before emulating.
            If GetAsyncKeyState_(#VK_LSHIFT) & $8000
              SendKeyInput(#VK_LSHIFT, #KEYEVENTF_KEYUP)
            EndIf
            If GetAsyncKeyState_(#VK_LWIN) & $8000
              SendKeyInput(#VK_LWIN, #KEYEVENTF_KEYUP)
            EndIf
            
            SendKeyInput(VKey, 0)
        EndSelect
      EndIf
      
      ProcedureReturn 1
      
    ElseIf wParam = #WM_KEYUP Or wParam = #WM_SYSKEYUP
      If ActiveRemapVKey <> 0
        SendKeyInput(ActiveRemapVKey, #KEYEVENTF_KEYUP)
        ActiveRemapVKey = 0
      EndIf
      CopilotKeyDown = 0
      ProcedureReturn 1
    EndIf
    
    ProcedureReturn 1
  EndIf

  ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
EndProcedure


; --- 4. APPLICATION INITIALIZATION ---

GetAvailableLanguages() ; Scans for languages first
LoadAIServices()
GetInstalledBrowsers()
LoadSettings()
LoadAppProfiles()
UpdateLanguageStrings()

; Hidden window to handle background events and tray menu
If OpenWindow(#MainWin, 0, 0, 0, 0, "AICopilotMapper", #PB_Window_Invisible)
  
  CatchImage(#AppIcon, ?AppIconStart, ?AppIconEnd - ?AppIconStart)
  AddSysTrayIcon(#TrayIcon, WindowID(#MainWin), ImageID(#AppIcon))
  SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip)
  RebuildMenu()
  
  hHook = SetWindowsHookEx_(13, @KeyboardProc(), GetModuleHandle_(0), 0)
  If hHook = 0
    MessageRequester("Keyboard hook fejl", "Kunne ikke installere keyboard hook." + Chr(10) + "Fejlkode: " + Str(GetLastError_()), #PB_MessageRequester_Error)
  EndIf
  
  ; Main Event Loop
  Repeat
    Define Event.i = WaitWindowEvent()
    Select Event
      Case #PB_Event_SysTray
        If EventType() = #PB_EventType_RightClick Or EventType() = #PB_EventType_LeftClick
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
          
        ; Handle dynamic AI clicks
        ElseIf MenuID >= #Menu_AI_Base And MenuID < #Menu_AI_Base + ListSize(AIServices())
          SelectElement(AIServices(), MenuID - #Menu_AI_Base)
          SelectedAI = AIServices()\Name
          UpdateTargetURL() : SaveSettings() : RebuildMenu()
          
        Else
          Select MenuID
            Case #Menu_Mode_AI    : ButtonMode = 0 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_CTRL  : ButtonMode = 1 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_ALT   : ButtonMode = 2 : SaveSettings() : RebuildMenu()
            
            Case #Menu_Launch_App     : LaunchMode = 0 : SaveSettings() : RebuildMenu()
            Case #Menu_Launch_Tab     : LaunchMode = 1 : SaveSettings() : RebuildMenu()
            Case #Menu_Launch_Window  : LaunchMode = 2 : SaveSettings() : RebuildMenu()
            Case #Menu_Launch_Default : LaunchMode = 3 : SaveSettings() : RebuildMenu()
            
            Case #Menu_CustomAI_Add
              AddOrEditCustomAI()
              SaveSettings() : RebuildMenu()
              
            Case #Menu_CustomAI_Remove
              RemoveSelectedCustomAI()
              SaveSettings() : RebuildMenu()

            Case #Menu_AutoStart
              Define NewAutoStart.i = 1 - AutoStart
              If SetAutoStartRegistry(NewAutoStart)
                AutoStart = NewAutoStart
                SaveSettings()
              EndIf
              RebuildMenu()
              
            Case #Menu_Pause
              MappingPaused = 1 - MappingPaused
              CopilotKeyDown = 0
              If ActiveRemapVKey <> 0
                SendKeyInput(ActiveRemapVKey, #KEYEVENTF_KEYUP)
                ActiveRemapVKey = 0
              EndIf
              RebuildMenu()
              
            Case #Menu_Profile_Open
              OpenProfileFile()
              
            Case #Menu_Profile_Reload
              LoadAppProfiles()
              MessageRequester("Profiler", "Profiler er genindlæst." + Chr(10) + "Aktive profiler: " + Str(ListSize(AppProfiles())), #PB_MessageRequester_Info)
              RebuildMenu()
              
            Case #Menu_Profile_Template
              CreateProfileTemplate(1)
              OpenProfileFile()
              
            Case #Menu_About
              MessageRequester(Txt_AboutTitle, Txt_AboutText, #PB_MessageRequester_Info)
              
            Case #Menu_Exit
              Break
          EndSelect
        EndIf
    EndSelect
  Until Event = #PB_Event_CloseWindow

  ; Cleanup before exit
  If ActiveRemapVKey <> 0
    SendKeyInput(ActiveRemapVKey, #KEYEVENTF_KEYUP)
  EndIf
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
; IDE Options = PureBasic 6.40 (Windows - x64)
; Folding = --
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = ..\AICopilotMapper.exe

; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 1006
; FirstLine = 959
; Folding = -----
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = ..\AICopilotMapper.exe