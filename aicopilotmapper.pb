; ============================================================================
; Application: AI Copilot Mapper
; Version: 1.4.0
; Description: Remaps the Windows Copilot key to custom AI services.
;              Features an embedded WebView2 browser and per-app profile support.
; ============================================================================

EnableExplicit

; ----------------------------------------------------------------------------
; EXTERNAL API IMPORTS
; ----------------------------------------------------------------------------
; PureBasic does not always include a built-in declaration for this WinAPI call.
; Import the Unicode version explicitly so per-app profiles can safely read the
; foreground process executable name.
Import "Kernel32.lib"
  QueryFullProcessImageNameW(hProcess.i, dwFlags.l, lpExeName.i, lpdwSize.i)
EndImport

; --- CONSTANTS ---
#AppVersion = "1.4.0"

; ----------------------------------------------------------------------------
; DATA STRUCTURES
; ----------------------------------------------------------------------------
; Browser structure for external browser launching
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

; Simple per-app profile structure for conditional mapping
Structure AppProfileInfo
  Process.s
  Mode.i
  AIName.s
  AIURL.s
  LaunchMode.i
  Paused.i
EndStructure

; ----------------------------------------------------------------------------
; GLOBAL VARIABLES & LISTS
; ----------------------------------------------------------------------------
Global NewList InstalledBrowsers.BrowserInfo()
Global NewList AvailableLanguages.LangInfo()
Global NewList AIServices.AIServiceInfo()
Global NewList AppProfiles.AppProfileInfo()

; Embedded view state variables used for asynchronous event handling
Global PendingLaunchURL.s = ""
Global PendingLaunchMode.i = 0

; Settings & File Paths
Global IniFile.s = GetPathPart(ProgramFilename()) + "AICopilotMapper.ini"
Global ProfileFile.s = GetPathPart(ProgramFilename()) + "AICopilotMapper_profiles.ini"
Global AppPath.s = ProgramFilename()
Global BrowserPath.s = "" 
Global SelectedAI.s = "Gemini" 
Global TargetURL.s = "https://gemini.google.com"
Global AutoStart.i = 0
Global Language.s = "DA"

; Operating Modes
Global ButtonMode.i = 0 ; 0 = AI Mode, 1 = R-CTRL Mode, 2 = R-ALT Mode
Global LaunchMode.i = 0 ; 0 = Browser app window, 1 = normal tab, 2 = new window, 3 = system default
Global UseEmbeddedBrowser.i = 1 ; 1 = WebView2Gadget (Default), 0 = External Browser
Global MappingPaused.i = 0 

; Keyboard Hook States
Global CopilotKeyDown.i = 0 
Global ActiveRemapVKey.w = 0 
Global hMutex, hHook

; Cached per-app profile state.
; IMPORTANT: This cache is refreshed periodically by a window timer (see main loop),
; NOT queried live from inside the keyboard hook. Low-level keyboard hooks (WH_KEYBOARD_LL)
; must return within a short OS timeout (LowLevelHooksTimeout, ~300ms by default) or
; Windows silently unhooks them. Doing registry/process lookups on every keypress risked
; exactly that, so the hook now only ever reads these plain globals.
Global CachedProfileActive.i = 0
Global CachedProfileMode.i = -1
Global CachedProfileLaunchMode.i = -1
Global CachedProfileAIURL.s = ""
Global CachedProfilePaused.i = -1
#ProfileCacheTimerID = 1
#ProfileCacheIntervalMs = 250

; String Variables for UI (Populated by Language Files)
Global Txt_MsgBoxTitle.s, Txt_MsgBoxRunning.s
Global Txt_TrayTooltip.s, Txt_MenuBrowser.s, Txt_MenuAI.s
Global Txt_MenuAutoStart.s, Txt_MenuLanguage.s, Txt_MenuAbout.s, Txt_MenuExit.s
Global Txt_AboutTitle.s, Txt_AboutText.s
Global Txt_MenuMode.s, Txt_ModeAI.s, Txt_ModeCTRL.s, Txt_ModeALT.s
Global Txt_MenuLaunchMode.s, Txt_LaunchApp.s, Txt_LaunchTab.s, Txt_LaunchWindow.s, Txt_LaunchDefault.s
Global Txt_MenuPause.s, Txt_MenuProfiles.s, Txt_ProfileOpen.s, Txt_ProfileReload.s, Txt_ProfileTemplate.s
Global Txt_CustomAIAdd.s, Txt_CustomAIRemove.s
Global Txt_MenuEmbedded.s 
; Previously hardcoded Danish strings, now localizable like everything else:
Global Txt_CustomAINamePrompt.s, Txt_CustomAIURLPrompt.s
Global Txt_CustomAINotCustomTitle.s, Txt_CustomAINotCustomMsg.s
Global Txt_RegErrorTitle.s, Txt_RegErrorMsg.s
Global Txt_ProfileReloadedTitle.s, Txt_ProfileReloadedMsg.s

; ----------------------------------------------------------------------------
; ENUMERATIONS (IDs for Events, Windows, Gadgets, and Menus)
; ----------------------------------------------------------------------------
Enumeration #PB_Event_FirstCustomValue
  #Event_OpenCopilot ; Custom event triggered by the keyboard hook to safely open the UI
EndEnumeration

Enumeration
  #AboutWin
  #About_ImageGadget
  #About_LinkGadget
  #About_TextGadget
  #About_CloseBtn
  #MainWin
  #AIWin
  #AICombo
  #AIGadget
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
  #Menu_Embedded
  #Menu_AutoStart
  #Menu_Pause
  #Menu_CustomAI_Add
  #Menu_CustomAI_Remove
  #Menu_Profile_Open
  #Menu_Profile_Reload
  #Menu_Profile_Template
  #Menu_About
  #Menu_Exit
  ; Bumped from 100/200/300 to give each dynamic list far more headroom
  ; before it could ever collide with the next range.
  #Menu_Browser_Base = 1000 
  #Menu_Lang_Base    = 2000 
  #Menu_AI_Base      = 3000 
EndEnumeration

; ----------------------------------------------------------------------------
; 1. INSTANCE CHECK (MUTEX)
; Prevents multiple instances of the application from running simultaneously.
; ----------------------------------------------------------------------------
Global MutexName.s = "Global\AICopilotMapper_Unique_ID"
hMutex = CreateMutex_(0, 1, @MutexName)
If GetLastError_() = 183
  ; Language strings aren't loaded yet at this point in startup, so this uses a
  ; plain bilingual fallback rather than silently exiting with no feedback.
  MessageRequester("AI Copilot Mapper", "Programmet kører allerede (se system tray)." + Chr(10) + "The application is already running (check the system tray).", #PB_MessageRequester_Info)
  End
EndIf


; ----------------------------------------------------------------------------
; 2. HELPER FUNCTIONS
; ----------------------------------------------------------------------------

; Checks if a URL string begins with a valid protocol scheme (e.g., http://)
Procedure.i StartsWithProtocol(Text.s)
  Protected L.s = LCase(Text)
  If FindString(L, "://") > 0
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

; Restricts accepted schemes to http/https only. Custom AI URLs and per-app
; profile URLs are user/ini supplied and get fed straight into RunProgram()
; and the WebView, so schemes like file:// or javascript: are rejected here.
Procedure.i IsAllowedScheme(URL.s)
  Protected L.s = LCase(URL)
  If Left(L, 7) = "http://" Or Left(L, 8) = "https://"
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

; Normalizes the URL, appending http/https if missing depending on the address.
; Returns "" if the URL uses a disallowed (non-http/https) scheme.
Procedure.s NormalizeURL(URL.s)
  URL = Trim(URL)
  If URL = "" : ProcedureReturn "" : EndIf
  
  If StartsWithProtocol(URL) = 0
    If Left(LCase(URL), 9) = "localhost" Or Left(URL, 9) = "127.0.0.1" Or Left(URL, 5) = "[::1]"
      URL = "http://" + URL
    Else
      URL = "https://" + URL
    EndIf
  EndIf
  
  If IsAllowedScheme(URL) = 0
    ProcedureReturn ""
  EndIf
  
  ProcedureReturn URL
EndProcedure

; Validates if a custom external browser has been explicitly configured
Procedure.i BrowserIsExplicit()
  If BrowserPath <> "" And LCase(BrowserPath) <> "explorer.exe" And FileSize(BrowserPath) >= 0
    ProcedureReturn 1
  EndIf
  ProcedureReturn 0
EndProcedure

; Simulates keyboard input using the Win32 SendInput API (used for key remapping)
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

; Helper function to safely read string values from the Windows Registry.
; Queries the required buffer size first instead of assuming a fixed 1024-byte
; buffer is always large enough (avoids silent truncation on long values).
Procedure.s ReadRegString(hKeyRoot, KeyPath.s, ValueName.s)
  Protected hKey.i, Type.i, BufferSize.i, Result.s = ""
  Protected *Buffer
  Protected QueryResult.i
  
  If RegOpenKeyEx_(hKeyRoot, KeyPath, 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    BufferSize = 0
    QueryResult = RegQueryValueEx_(hKey, ValueName, 0, @Type, 0, @BufferSize)
    If (QueryResult = #ERROR_SUCCESS Or QueryResult = 234) And BufferSize > 0 ; 234 = ERROR_MORE_DATA
      *Buffer = AllocateMemory(BufferSize + SizeOf(Character))
      If *Buffer
        If RegQueryValueEx_(hKey, ValueName, 0, @Type, *Buffer, @BufferSize) = #ERROR_SUCCESS
          If Type = #REG_SZ Or Type = #REG_EXPAND_SZ
            Result = PeekS(*Buffer, BufferSize / SizeOf(Character))
          EndIf
        EndIf
        FreeMemory(*Buffer)
      EndIf
    EndIf
    RegCloseKey_(hKey)
  EndIf
  
  ProcedureReturn Result
EndProcedure

; Scans a single registry root (HKLM or HKCU) for installed browsers and
; appends matches to the InstalledBrowsers() list. Shared by GetInstalledBrowsers()
; to avoid duplicating the HKLM/HKCU scanning logic.
Procedure ScanBrowserRegistryKey(hKeyRoot.i)
  Protected hKey.i, Index.i = 0
  Protected KeyName.s = Space(256), KeyNameSize.i
  Protected SubKeyName.s, BName.s, BPath.s
  
  If RegOpenKeyEx_(hKeyRoot, "SOFTWARE\Clients\StartMenuInternet", 0, #KEY_READ, @hKey) = #ERROR_SUCCESS
    Repeat
      KeyNameSize = 256
      If RegEnumKeyEx_(hKey, Index, @KeyName, @KeyNameSize, 0, 0, 0, 0) = #ERROR_SUCCESS
        SubKeyName = "SOFTWARE\Clients\StartMenuInternet\" + Left(KeyName, KeyNameSize)
        BName = ReadRegString(hKeyRoot, SubKeyName, "")
        If BName = "" : BName = Left(KeyName, KeyNameSize) : EndIf
        BPath = ReadRegString(hKeyRoot, SubKeyName + "\shell\open\command", "")
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
EndProcedure

; Scans the Windows Registry to populate the list of installed web browsers
Procedure GetInstalledBrowsers()
  ClearList(InstalledBrowsers())
  
  ScanBrowserRegistryKey(#HKEY_LOCAL_MACHINE) ; System-wide installations
  ScanBrowserRegistryKey(#HKEY_CURRENT_USER)  ; User-specific installations
  
  ; Fallback to system default if no browsers are found
  If ListSize(InstalledBrowsers()) = 0
    AddElement(InstalledBrowsers())
    InstalledBrowsers()\Name = "System Default"
    InstalledBrowsers()\Path = "explorer.exe" 
  EndIf
EndProcedure

; Discovers available language packs (*.lng files) in the application directory
Procedure GetAvailableLanguages()
  Protected Directory.s = GetPathPart(ProgramFilename())
  Protected DirID.i, FileName.s, LangCode.s
  
  ClearList(AvailableLanguages())
  
  DirID = ExamineDirectory(#PB_Any, Directory, "*.lng")
  If DirID
    While NextDirectoryEntry(DirID)
      If DirectoryEntryType(DirID) = #PB_DirectoryEntry_File
        FileName = DirectoryEntryName(DirID)
        LangCode = UCase(Left(FileName, Len(FileName) - 4))
        
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
  
  ; Fallback language if no packs are found
  If ListSize(AvailableLanguages()) = 0
    AddElement(AvailableLanguages())
    AvailableLanguages()\Code = "DA"
    AvailableLanguages()\Name = "Dansk"
  EndIf
EndProcedure

; Adds an AI service to the internal list (handles both defaults and custom user services)
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

; Retrieves the corresponding URL for a given AI service name
Procedure.s GetAIURLByName(Name.s)
  ForEach AIServices()
    If LCase(AIServices()\Name) = LCase(Name)
      ProcedureReturn AIServices()\URL
    EndIf
  Next
  ProcedureReturn "https://gemini.google.com"
EndProcedure

; Populates the base list of AI services and loads any user-defined ones from the .ini file
Procedure LoadAIServices()
  Protected Count.i, I.i, Name.s, URL.s
  ClearList(AIServices())
  
  AddAIService("Gemini", "https://gemini.google.com", 0)
  AddAIService("Kimi", "https://www.kimi.com", 0)
  AddAIService("ChatGPT", "https://chatgpt.com", 0)
  AddAIService("Claude", "https://claude.ai", 0)
  AddAIService("DeepSeek", "https://chat.deepseek.com", 0)
  AddAIService("Perplexity", "https://www.perplexity.ai", 0)
  AddAIService("Copilot", "https://copilot.microsoft.com", 0)
  
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

; Saves the user-defined custom AI services back to the .ini file
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

; Syncs the active TargetURL string with the current SelectedAI
Procedure UpdateTargetURL()
  TargetURL = GetAIURLByName(SelectedAI)
EndProcedure

; UI routine to prompt the user to add or modify a custom AI entry
Procedure AddOrEditCustomAI()
  Protected Name.s, URL.s
  Name = InputRequester("Custom AI", Txt_CustomAINamePrompt, "")
  If Trim(Name) = "" : ProcedureReturn : EndIf
  
  URL = InputRequester("Custom AI", Txt_CustomAIURLPrompt, "http://localhost:3000")
  URL = NormalizeURL(URL)
  If Trim(URL) = "" : ProcedureReturn : EndIf
  
  AddAIService(Name, URL, 1)
  SelectedAI = Trim(Name)
  UpdateTargetURL()
  SaveCustomAIServices()
EndProcedure

; UI routine to safely remove the currently selected custom AI entry
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
  MessageRequester(Txt_CustomAINotCustomTitle, Txt_CustomAINotCustomMsg, #PB_MessageRequester_Info)
EndProcedure

; Returns the localized string for a specific LaunchMode ID
Procedure.s LaunchModeName(Mode.i)
  Select Mode
    Case 0 : ProcedureReturn Txt_LaunchApp
    Case 1 : ProcedureReturn Txt_LaunchTab
    Case 2 : ProcedureReturn Txt_LaunchWindow
    Case 3 : ProcedureReturn Txt_LaunchDefault
  EndSelect
  ProcedureReturn Txt_LaunchApp
EndProcedure

; ----------------------------------------------------------------------------
; CORE LOGIC: WINDOW & BROWSER LAUNCHERS
; ----------------------------------------------------------------------------

; Clears and repopulates the AI dropdown from AIServices(), selecting SelectedAI.
; Shared by both the "first open" and "reuse existing window" paths in
; OpenEmbeddedAI() so a custom AI added while the window is open shows up
; in the dropdown immediately, instead of only on the next fresh launch.
Procedure PopulateAICombo()
  Protected i.i
  ClearGadgetItems(#AICombo)
  ForEach AIServices()
    AddGadgetItem(#AICombo, -1, AIServices()\Name)
  Next
  For i = 0 To CountGadgetItems(#AICombo) - 1
    If LCase(GetGadgetItemText(#AICombo, i)) = LCase(SelectedAI)
      SetGadgetState(#AICombo, i)
      Break
    EndIf
  Next
EndProcedure

; Opens or updates the native Embedded AI View (WebView2). 
; Features an Always-On-Top focus workaround and a UI dropdown to switch services.
Procedure OpenEmbeddedAI(URL.s)
  URL = NormalizeURL(URL)
  If URL = "" : ProcedureReturn : EndIf
  
  ; If window exists, bring to front and update URL/Dropdown
  If IsWindow(#AIWin)
    SetWindowState(#AIWin, #PB_Window_Normal)
    StickyWindow(#AIWin, 1) ; Temporary Always-On-Top to steal OS focus
    SetActiveWindow(#AIWin)
    StickyWindow(#AIWin, 0)
    
    SetGadgetText(#AIGadget, URL)
    PopulateAICombo()
    
    ProcedureReturn
  EndIf
  
  ; Initialize the window and layout for the first time
  If OpenWindow(#AIWin, #PB_Ignore, #PB_Ignore, 1024, 768, "AI Copilot View", #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_SizeGadget | #PB_Window_MaximizeGadget)
    
    StickyWindow(#AIWin, 1)
    SetActiveWindow(#AIWin)
    StickyWindow(#AIWin, 0)
    
    ; Top bar dropdown for fast AI switching
    ComboBoxGadget(#AICombo, 10, 5, 250, 25)
    PopulateAICombo()
    
    ; Edge WebView2 Gadget integration
    If WebViewGadget(#AIGadget, 0, 35, 1024, 768 - 35)
      SetGadgetText(#AIGadget, URL) 
      ResizeGadget(#AIGadget, 0, 35, WindowWidth(#AIWin), WindowHeight(#AIWin) - 35)
    EndIf
  EndIf
EndProcedure

; Main router for launching a target URL. Will either trigger the Embedded View 
; or hand the execution over to an external web browser depending on user preference.
Procedure LaunchTarget(URL.s, UseLaunchMode.i)
  If UseEmbeddedBrowser = 1
    OpenEmbeddedAI(URL)
    ProcedureReturn
  EndIf

  URL = NormalizeURL(URL)
  If URL = "" : ProcedureReturn : EndIf
  
  Select UseLaunchMode
    Case 0 
      If BrowserIsExplicit()
        RunProgram(BrowserPath, "--app=" + Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
    Case 1 
      If BrowserIsExplicit()
        RunProgram(BrowserPath, Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
    Case 2 
      If BrowserIsExplicit()
        RunProgram(BrowserPath, "--new-window " + Chr(34) + URL + Chr(34), "")
      Else
        RunProgram(URL, "", "")
      EndIf
    Case 3 
      RunProgram(URL, "", "")
    Default
      RunProgram(URL, "", "")
  EndSelect
EndProcedure

; ----------------------------------------------------------------------------
; LOCALIZATION & SYSTEM TRAY
; ----------------------------------------------------------------------------

; Reloads all UI string variables from the active language file
Procedure UpdateLanguageStrings()
  Protected AppName.s = "AI Copilot Mapper"
  Protected VerPrefix.s = " v" + #AppVersion + Chr(10)
  Protected LngFile.s = GetPathPart(ProgramFilename()) + Language + ".lng"
  
  ; Set hardcoded fallbacks
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
  Txt_MenuEmbedded = "Brug Indbygget View (Hurtig)"
  Txt_AboutTitle = "Om " + AppName
  Txt_AboutText = AppName + VerPrefix + "Udviklet til at omkode Copilot-tasten til din foretrukne AI, en lokal AI-tjeneste eller en systemtast." + Chr(10) + Chr(10) + "Nyt i 1.2.1:" + Chr(10) + "- Indbygget WebView2 Browser integration"
  Txt_MsgBoxRunning = "Programmet kører allerede."
  Txt_CustomAINamePrompt = "Navn på AI-tjenesten:" + Chr(10) + "Eksempel: Open WebUI"
  Txt_CustomAIURLPrompt = "URL til AI-tjenesten:" + Chr(10) + "Eksempel: http://localhost:3000"
  Txt_CustomAINotCustomTitle = "Custom AI"
  Txt_CustomAINotCustomMsg = "Den valgte AI er ikke en custom AI og kan derfor ikke fjernes her."
  Txt_RegErrorTitle = "Rettighedsfejl"
  Txt_RegErrorMsg = "Windows nægtede adgang til Autostart."
  Txt_ProfileReloadedTitle = "Profiler"
  Txt_ProfileReloadedMsg = "Profiler er genindlæst."
  
  ; Attempt to load dynamic definitions from the .lng file
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
      Txt_MenuEmbedded = ReadPreferenceString("MenuEmbedded", Txt_MenuEmbedded)
      Txt_AboutTitle = ReadPreferenceString("AboutTitle", Txt_AboutTitle)
      Txt_AboutText = AppName + VerPrefix + ReadPreferenceString("AboutText", "Developed to remap the Copilot key.")
      Txt_MsgBoxRunning = ReadPreferenceString("MsgBoxRunning", Txt_MsgBoxRunning)
      Txt_CustomAINamePrompt = ReadPreferenceString("CustomAINamePrompt", Txt_CustomAINamePrompt)
      Txt_CustomAIURLPrompt = ReadPreferenceString("CustomAIURLPrompt", Txt_CustomAIURLPrompt)
      Txt_CustomAINotCustomTitle = ReadPreferenceString("CustomAINotCustomTitle", Txt_CustomAINotCustomTitle)
      Txt_CustomAINotCustomMsg = ReadPreferenceString("CustomAINotCustomMsg", Txt_CustomAINotCustomMsg)
      Txt_RegErrorTitle = ReadPreferenceString("RegErrorTitle", Txt_RegErrorTitle)
      Txt_RegErrorMsg = ReadPreferenceString("RegErrorMsg", Txt_RegErrorMsg)
      Txt_ProfileReloadedTitle = ReadPreferenceString("ProfileReloadedTitle", Txt_ProfileReloadedTitle)
      Txt_ProfileReloadedMsg = ReadPreferenceString("ProfileReloadedMsg", Txt_ProfileReloadedMsg)
      ClosePreferences()
    EndIf
  EndIf
  
  Txt_MsgBoxTitle = AppName
  Txt_TrayTooltip = AppName
EndProcedure

; Updates the hover-text of the system tray icon with current status and configuration
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
  If UseEmbeddedBrowser
    Tip + Chr(10) + "Åbning: WebView2 (Embedded)"
  Else
    Tip + Chr(10) + "Åbning: " + LaunchModeName(LaunchMode)
  EndIf
  SysTrayIconToolTip(#TrayIcon, Tip)
EndProcedure

; Rebuilds the entire System Tray Context Menu dynamically based on active state
Procedure RebuildMenu()
  Protected Index.i = 0
  If IsMenu(#TrayMenu)
    FreeMenu(#TrayMenu)
  EndIf
  
  If CreatePopupMenu(#TrayMenu)
    OpenSubMenu(Txt_MenuMode)
      MenuItem(#Menu_Mode_AI, Txt_ModeAI)
      MenuItem(#Menu_Mode_CTRL, Txt_ModeCTRL)
      MenuItem(#Menu_Mode_ALT, Txt_ModeALT)
    CloseSubMenu()
    MenuBar()
    
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
    
    OpenSubMenu(Txt_MenuLaunchMode)
      MenuItem(#Menu_Launch_App, Txt_LaunchApp)
      MenuItem(#Menu_Launch_Tab, Txt_LaunchTab)
      MenuItem(#Menu_Launch_Window, Txt_LaunchWindow)
      MenuItem(#Menu_Launch_Default, Txt_LaunchDefault)
    CloseSubMenu()
    
    MenuBar()
    MenuItem(#Menu_Embedded, Txt_MenuEmbedded)
    MenuItem(#Menu_AutoStart, Txt_MenuAutoStart)
    MenuItem(#Menu_Pause, Txt_MenuPause)
    
    OpenSubMenu(Txt_MenuProfiles)
      MenuItem(#Menu_Profile_Open, Txt_ProfileOpen)
      MenuItem(#Menu_Profile_Reload, Txt_ProfileReload)
      MenuItem(#Menu_Profile_Template, Txt_ProfileTemplate)
    CloseSubMenu()
    
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
    
    ; Apply checkmarks to currently active options
    SetMenuItemState(#TrayMenu, #Menu_Mode_AI, Bool(ButtonMode = 0))
    SetMenuItemState(#TrayMenu, #Menu_Mode_CTRL, Bool(ButtonMode = 1))
    SetMenuItemState(#TrayMenu, #Menu_Mode_ALT, Bool(ButtonMode = 2))
    SetMenuItemState(#TrayMenu, #Menu_Launch_App, Bool(LaunchMode = 0))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Tab, Bool(LaunchMode = 1))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Window, Bool(LaunchMode = 2))
    SetMenuItemState(#TrayMenu, #Menu_Launch_Default, Bool(LaunchMode = 3))
    SetMenuItemState(#TrayMenu, #Menu_Embedded, UseEmbeddedBrowser) 
    SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
    SetMenuItemState(#TrayMenu, #Menu_Pause, MappingPaused)
  EndIf
  
  UpdateTrayTooltip()
EndProcedure

; ----------------------------------------------------------------------------
; SETTINGS & PROFILE MANAGEMENT
; ----------------------------------------------------------------------------

; Toggles the application in the Windows Registry to start on system boot
Procedure.i SetAutoStartRegistry(Enable.i)
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
      If Result <> #ERROR_SUCCESS
        If Result = 2 : Result = #ERROR_SUCCESS : EndIf
      EndIf
    EndIf
    RegCloseKey_(hKey)
  EndIf
  
  If Result <> #ERROR_SUCCESS
    MessageRequester(Txt_RegErrorTitle, Txt_RegErrorMsg + Chr(10) + "Fejlkode: " + Str(Result), #PB_MessageRequester_Warning)
    ProcedureReturn 0
  EndIf
  
  ProcedureReturn 1
EndProcedure

; Saves the current configuration block to the local .ini file
Procedure SaveSettings()
  If OpenPreferences(IniFile, #PB_UTF8) Or CreatePreferences(IniFile, #PB_UTF8)
    PreferenceGroup("Settings")
    WritePreferenceString("Browser", BrowserPath)
    WritePreferenceInteger("AutoStart", AutoStart)
    WritePreferenceString("Language", Language)
    WritePreferenceString("AI", SelectedAI)
    WritePreferenceInteger("ButtonMode", ButtonMode)
    WritePreferenceInteger("LaunchMode", LaunchMode)
    WritePreferenceInteger("UseEmbeddedBrowser", UseEmbeddedBrowser)
    ClosePreferences()
  EndIf
EndProcedure

; Loads and validates previous application state from the local .ini file
Procedure LoadSettings()
  If OpenPreferences(IniFile, #PB_UTF8)
    PreferenceGroup("Settings")
    BrowserPath = ReadPreferenceString("Browser", "")
    AutoStart = ReadPreferenceInteger("AutoStart", 0)
    Language = ReadPreferenceString("Language", "DA")
    SelectedAI = ReadPreferenceString("AI", "Gemini")
    ButtonMode = ReadPreferenceInteger("ButtonMode", 0)
    LaunchMode = ReadPreferenceInteger("LaunchMode", 0)
    UseEmbeddedBrowser = ReadPreferenceInteger("UseEmbeddedBrowser", 1) ; Defaults to 1 (Enabled)
    ClosePreferences()
  EndIf
  
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

; Creates an empty template for per-app profiles if the file does not exist
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
    CloseFile(File)
  EndIf
EndProcedure

; Parses and caches the active per-app custom profile configurations
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

; Opens the profile .ini file in Notepad for user editing
Procedure OpenProfileFile()
  CreateProfileTemplate(0)
  RunProgram("notepad.exe", Chr(34) + ProfileFile + Chr(34), "")
EndProcedure

; Queries the Windows API to identify the currently active foreground application
Procedure.s GetActiveProcessName()
  Protected hWnd.i, PID.i, hProcess.i
  Protected Buffer.s = Space(1024), Size.i = 1024
  Protected Result.s = ""
  
  hWnd = GetForegroundWindow_()
  If hWnd = 0 : ProcedureReturn "" : EndIf
  GetWindowThreadProcessId_(hWnd, @PID)
  If PID = 0 : ProcedureReturn "" : EndIf
  
  hProcess = OpenProcess_($1000, 0, PID)
  If hProcess
    If QueryFullProcessImageNameW(hProcess, 0, @Buffer, @Size)
      Result = LCase(GetFilePart(Left(Buffer, Size)))
    EndIf
    CloseHandle_(hProcess)
  EndIf
  
  ProcedureReturn Result
EndProcedure

; Refreshes the cached "effective profile" state used by KeyboardProc().
; Called periodically by a window timer (and on demand after profile edits),
; so the actual registry/process lookups never happen inside the low-level
; keyboard hook itself. See the CachedProfile* globals for details.
Procedure UpdateActiveProfileCache()
  Protected Proc.s = GetActiveProcessName()
  
  CachedProfileActive = 0
  CachedProfileMode = -1
  CachedProfileLaunchMode = -1
  CachedProfileAIURL = ""
  CachedProfilePaused = -1
  
  If Proc = "" : ProcedureReturn : EndIf
  
  ForEach AppProfiles()
    If LCase(AppProfiles()\Process) = Proc
      CachedProfileActive = 1
      CachedProfileMode = AppProfiles()\Mode
      CachedProfileLaunchMode = AppProfiles()\LaunchMode
      CachedProfilePaused = AppProfiles()\Paused
      If AppProfiles()\AIURL <> ""
        CachedProfileAIURL = AppProfiles()\AIURL
      ElseIf AppProfiles()\AIName <> ""
        CachedProfileAIURL = GetAIURLByName(AppProfiles()\AIName)
      EndIf
      Break
    EndIf
  Next
EndProcedure


; ----------------------------------------------------------------------------
; 3. KEYBOARD HOOK LOGIC (With SendInput API)
; Intercepts global keyboard events to remap the specific vkCode $86 key.
; ----------------------------------------------------------------------------

Procedure.l KeyboardProc(nCode, wParam, lParam)
  Protected *pkbdll.KBDLLHOOKSTRUCT = lParam
  Protected EffMode.i, EffLaunchMode.i, EffPaused.i
  Protected EffURL.s
  Protected VKey.w
  
  ; Pass through events if code < 0 or if the event was injected by software
  If nCode < 0
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf
  If *pkbdll\flags & $10
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  ; $86 corresponds to the modern AI Copilot hardware key
  If *pkbdll\vkCode = $86 
    EffMode = ButtonMode
    EffLaunchMode = LaunchMode
    EffPaused = MappingPaused
    EffURL = TargetURL
    
    ; Apply profile overrides from the periodically-refreshed cache. No registry
    ; or process API calls happen here — see UpdateActiveProfileCache().
    If CachedProfileActive
      If CachedProfilePaused = 1
        EffPaused = 1
      ElseIf CachedProfilePaused = 0 And MappingPaused = 0
        EffPaused = 0
      EndIf
      
      If CachedProfileMode >= 0 And CachedProfileMode <= 2
        EffMode = CachedProfileMode
      EndIf
      
      If CachedProfileLaunchMode >= 0 And CachedProfileLaunchMode <= 3
        EffLaunchMode = CachedProfileLaunchMode
      EndIf
      
      If CachedProfileAIURL <> ""
        EffURL = CachedProfileAIURL
      EndIf
    EndIf
    
    If EffPaused
      CopilotKeyDown = 0
      ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
    EndIf
    
    ; Handle the initial key press
    If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
      If CopilotKeyDown = 0
        CopilotKeyDown = 1
        
        Select EffMode
          Case 0 
            ; AI Mode: Queue the event for the main thread to handle safely
            PendingLaunchURL = EffURL
            PendingLaunchMode = EffLaunchMode
            PostEvent(#Event_OpenCopilot)
            
          Case 1, 2 
            ; Remap Mode: Emulate a CTRL or ALT keydown event instead
            If EffMode = 1 : VKey = #VK_RCONTROL : Else : VKey = #VK_RMENU : EndIf
            ActiveRemapVKey = VKey
            
            ; Release modifier keys to prevent conflicting input states
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
      
    ; Handle key release and clean up emulated strokes
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


; ----------------------------------------------------------------------------
; 4. APPLICATION INITIALIZATION & MAIN LOOP
; ----------------------------------------------------------------------------

; Configure WebView2 to isolate user data (cookies/logins) in a local folder
SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", GetPathPart(ProgramFilename()) + "WebViewData")

; Bootstrap startup resources
GetAvailableLanguages() 
LoadAIServices()
GetInstalledBrowsers()
LoadSettings()
LoadAppProfiles()
UpdateLanguageStrings()
UpdateActiveProfileCache() ; Prime the cache so the very first keypress isn't stale

; Initialize hidden background window for the System Tray handler
If OpenWindow(#MainWin, 0, 0, 0, 0, "AICopilotMapper", #PB_Window_Invisible)
  
  CatchImage(#AppIcon, ?AppIconStart, ?AppIconEnd - ?AppIconStart)
  AddSysTrayIcon(#TrayIcon, WindowID(#MainWin), ImageID(#AppIcon))
  SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip)
  RebuildMenu()
  
  ; Register the global Low-Level Keyboard hook
  hHook = SetWindowsHookEx_(13, @KeyboardProc(), GetModuleHandle_(0), 0)
  If hHook = 0
    MessageRequester("Keyboard hook fejl", "Kunne ikke installere keyboard hook.", #PB_MessageRequester_Error)
  EndIf
  
  ; Periodic timer that refreshes the active-profile cache so KeyboardProc()
  ; never has to touch the registry/process APIs directly.
  AddWindowTimer(#MainWin, #ProfileCacheTimerID, #ProfileCacheIntervalMs)
  
  ; Core UI Event Loop
  Repeat
    Define Event.i = WaitWindowEvent()
    
    ; Dynamic layout handling: scale the embedded browser when window resizes
    If Event = #PB_Event_SizeWindow And EventWindow() = #AIWin
      ResizeGadget(#AIGadget, 0, 35, WindowWidth(#AIWin), WindowHeight(#AIWin) - 35)
    EndIf
    
    Select Event      
      ; Execute the queued launch request dispatched from the keyboard hook
      Case #Event_OpenCopilot
        LaunchTarget(PendingLaunchURL, PendingLaunchMode)
        
      ; Handle native UI interactions (Dropdown menu changes)
      Case #PB_Event_Gadget
        If EventGadget() = #AICombo
          Define SelectedIdx.i = GetGadgetState(#AICombo)
          If SelectedIdx >= 0
            SelectElement(AIServices(), SelectedIdx)
            SelectedAI = AIServices()\Name
            UpdateTargetURL()
            SetGadgetText(#AIGadget, TargetURL)
            SaveSettings()
            RebuildMenu()
          EndIf
        EndIf
        
      Case #PB_Event_CloseWindow
        ; Safely close the Embedded AI Window without terminating the background app
        If EventWindow() = #AIWin
          CloseWindow(#AIWin)
        Else
          Break
        EndIf

      ; Show context menu on system tray click
      Case #PB_Event_SysTray
        If EventType() = #PB_EventType_RightClick Or EventType() = #PB_EventType_LeftClick
          DisplayPopupMenu(#TrayMenu, WindowID(#MainWin))
        EndIf
        
      ; Refresh the cached active-profile state on a timer, not inside the hook
      Case #PB_Event_Timer
        If EventTimer() = #ProfileCacheTimerID And EventWindow() = #MainWin
          UpdateActiveProfileCache()
        EndIf
        
      ; Handle system tray menu selections and update internal state
      Case #PB_Event_Menu
        Define MenuID.i = EventMenu()
        
        If MenuID >= #Menu_Browser_Base And MenuID < #Menu_Browser_Base + ListSize(InstalledBrowsers())
          SelectElement(InstalledBrowsers(), MenuID - #Menu_Browser_Base)
          BrowserPath = InstalledBrowsers()\Path : SaveSettings() : RebuildMenu()
          
        ElseIf MenuID >= #Menu_Lang_Base And MenuID < #Menu_Lang_Base + ListSize(AvailableLanguages())
          SelectElement(AvailableLanguages(), MenuID - #Menu_Lang_Base)
          Language = AvailableLanguages()\Code
          UpdateLanguageStrings() : SaveSettings() : RebuildMenu()
          
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
            
            Case #Menu_Embedded
              UseEmbeddedBrowser = 1 - UseEmbeddedBrowser
              SaveSettings() : RebuildMenu()

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
              
            Case #Menu_Profile_Open     : OpenProfileFile()
            Case #Menu_Profile_Reload
              LoadAppProfiles()
              UpdateActiveProfileCache()
              MessageRequester(Txt_ProfileReloadedTitle, Txt_ProfileReloadedMsg, #PB_MessageRequester_Info)
              RebuildMenu()
              
            Case #Menu_Profile_Template : CreateProfileTemplate(1) : OpenProfileFile()
            Case #Menu_About            : MessageRequester(Txt_AboutTitle, Txt_AboutText, #PB_MessageRequester_Info)
            Case #Menu_Exit             : Break
          EndSelect
        EndIf
    EndSelect
  ForEver ; Keep application alive dynamically unless explicitly closed

  ; --------------------------------------------------------------------------
  ; 5. GRACEFUL CLEANUP 
  ; Remove hooks, release handles and unregister tray icons before termination
  ; --------------------------------------------------------------------------
  RemoveWindowTimer(#MainWin, #ProfileCacheTimerID)
  If IsWindow(#AIWin) : CloseWindow(#AIWin) : EndIf
  If ActiveRemapVKey <> 0 : SendKeyInput(ActiveRemapVKey, #KEYEVENTF_KEYUP) : EndIf
  If hHook : UnhookWindowsHookEx_(hHook) : EndIf
  RemoveSysTrayIcon(#TrayIcon)
  If hMutex : CloseHandle_(hMutex) : EndIf
EndIf

DataSection
  AppIconStart: 
    IncludeBinary "aicopilotmapper.ico"
  AppIconEnd:
EndDataSection
; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 10
; Folding = -----
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = ..\AICopilotMapper.exe
; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 1212
; FirstLine = 1189
; Folding = ------
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = ..\AICopilotMapper.exe