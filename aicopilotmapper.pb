EnableExplicit

; --- CONSTANTS ---
#AppVersion = "1.0.1" ; Update version number here

; Browser structure
Structure BrowserInfo
  Name.s
  Path.s
EndStructure

; Global list of installed browsers
Global NewList InstalledBrowsers.BrowserInfo()

; Settings & Files
Global IniFile.s = GetCurrentDirectory() + "AICopilotMapper.ini"
Global AppPath.s = ProgramFilename()
Global BrowserPath.s = "" 
Global SelectedAI.s = "Gemini" 
Global TargetURL.s = "https://gemini.google.com"
Global AutoStart.i = 0
Global Language.s = "DA"
Global ButtonMode.i = 0 ; 0 = AI Mode, 1 = R-CTRL Mode, 2 = R-ALT Mode
Global hMutex, hHook

; String Variables for UI
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
  #Menu_Lang_DA
  #Menu_Lang_EN
  #Menu_Lang_ES
  #Menu_Lang_FR
  #Menu_Lang_IT
  #Menu_Lang_DE
  #Menu_About
  #Menu_Exit
  #Menu_Browser_Base = 100 
EndEnumeration

; --- HELPER FUNCTIONS ---

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
  If ListSize(InstalledBrowsers()) = 0
    AddElement(InstalledBrowsers())
    InstalledBrowsers()\Name = "System Default"
    InstalledBrowsers()\Path = "explorer.exe" 
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

; Sets the UI strings based on the selected language
Procedure UpdateLanguageStrings()
  Protected AppName.s = "AI Copilot Mapper"
  Protected VerPrefix.s = " v" + #AppVersion + Chr(10)
  
  Select Language
    Case "EN"
      Txt_MenuMode = "Button Function" : Txt_ModeAI = "AI Shortcut" : Txt_ModeCTRL = "Right CTRL" : Txt_ModeALT = "Right ALT"
      Txt_MenuAI = "Select AI" : Txt_MenuBrowser = "Select Browser" : Txt_MenuAutoStart = "Start with Windows"
      Txt_MenuLanguage = "Language" : Txt_MenuExit = "Exit" : Txt_MenuAbout = "About"
      Txt_AboutTitle = "About " + AppName
      Txt_AboutText = AppName + VerPrefix + "Developed to remap the Copilot key to your favorite AI or a system key."
    Case "ES"
      Txt_MenuMode = "Función del botón" : Txt_ModeAI = "Acceso directo IA" : Txt_ModeCTRL = "CTRL derecho" : Txt_ModeALT = "ALT derecho"
      Txt_MenuAI = "Seleccionar IA" : Txt_MenuBrowser = "Seleccionar navegador" : Txt_MenuAutoStart = "Iniciar con Windows"
      Txt_MenuLanguage = "Idioma" : Txt_MenuExit = "Salir" : Txt_MenuAbout = "Acerca de"
      Txt_AboutTitle = "Acerca de " + AppName
      Txt_AboutText = AppName + VerPrefix + "Desarrollado para reasignar la tecla Copilot a tu IA favorita o a una tecla del sistema."
    Case "FR"
      Txt_MenuMode = "Fonction du bouton" : Txt_ModeAI = "Raccourci IA" : Txt_ModeCTRL = "CTRL droit" : Txt_ModeALT = "ALT droit"
      Txt_MenuAI = "Sélectionner l'IA" : Txt_MenuBrowser = "Sélectionner le navigateur" : Txt_MenuAutoStart = "Démarrer avec Windows"
      Txt_MenuLanguage = "Langue" : Txt_MenuExit = "Quitter" : Txt_MenuAbout = "À propos"
      Txt_AboutTitle = "À propos de " + AppName
      Txt_AboutText = AppName + VerPrefix + "Développé pour remapper la touche Copilot vers votre IA préférée ou une touche système."
    Case "IT"
      Txt_MenuMode = "Funzione pulsante" : Txt_ModeAI = "Scorciatoia IA" : Txt_ModeCTRL = "CTRL destro" : Txt_ModeALT = "ALT destro"
      Txt_MenuAI = "Seleziona IA" : Txt_MenuBrowser = "Seleziona browser" : Txt_MenuAutoStart = "Avvia con Windows"
      Txt_MenuLanguage = "Lingua" : Txt_MenuExit = "Esci" : Txt_MenuAbout = "Informazioni"
      Txt_AboutTitle = "Informazioni su " + AppName
      Txt_AboutText = AppName + VerPrefix + "Sviluppato per rimappare il tasto Copilot sulla tua IA preferita o su un tasto di sistema."
    Case "DE"
      Txt_MenuMode = "Tastenfunktion" : Txt_ModeAI = "KI-Verknüpfung" : Txt_ModeCTRL = "Rechtes CTRL" : Txt_ModeALT = "Rechtes ALT"
      Txt_MenuAI = "KI auswählen" : Txt_MenuBrowser = "Browser auswählen" : Txt_MenuAutoStart = "Mit Windows starten"
      Txt_MenuLanguage = "Sprache" : Txt_MenuExit = "Beenden" : Txt_MenuAbout = "Über"
      Txt_AboutTitle = "Über " + AppName
      Txt_AboutText = AppName + VerPrefix + "Entwickelt, um die Copilot-Taste Ihrer Lieblings-KI oder einer Systemtaste neu zuzuweisen."
    Default ; DA
      Txt_MenuMode = "Knap Funktion" : Txt_ModeAI = "AI Genvej" : Txt_ModeCTRL = "Højre CTRL" : Txt_ModeALT = "Højre ALT"
      Txt_MenuAI = "Vælg AI" : Txt_MenuBrowser = "Vælg Browser" : Txt_MenuAutoStart = "Start med Windows"
      Txt_MenuLanguage = "Sprog" : Txt_MenuExit = "Afslut" : Txt_MenuAbout = "Om programmet"
      Txt_AboutTitle = "Om " + AppName
      Txt_AboutText = AppName + VerPrefix + "Udviklet til at omkode Copilot-tasten til din foretrukne AI eller en systemtast."
  EndSelect
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
    
    ; Language Submenu
    OpenSubMenu(Txt_MenuLanguage)
      MenuItem(#Menu_Lang_DA, "Dansk")
      MenuItem(#Menu_Lang_EN, "English")
      MenuItem(#Menu_Lang_ES, "Español")
      MenuItem(#Menu_Lang_FR, "Français")
      MenuItem(#Menu_Lang_IT, "Italiano")
      MenuItem(#Menu_Lang_DE, "Deutsch")
    CloseSubMenu()
    
    MenuBar()
    MenuItem(#Menu_About, Txt_MenuAbout)
    MenuItem(#Menu_Exit, Txt_MenuExit)
    
    ; Set Menu Item States
    SetMenuItemState(#TrayMenu, #Menu_Mode_AI, Bool(ButtonMode = 0))
    SetMenuItemState(#TrayMenu, #Menu_Mode_CTRL, Bool(ButtonMode = 1))
    SetMenuItemState(#TrayMenu, #Menu_Mode_ALT, Bool(ButtonMode = 2))
    SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
    
    Select Language
      Case "EN": SetMenuItemState(#TrayMenu, #Menu_Lang_EN, 1)
      Case "ES": SetMenuItemState(#TrayMenu, #Menu_Lang_ES, 1)
      Case "FR": SetMenuItemState(#TrayMenu, #Menu_Lang_FR, 1)
      Case "IT": SetMenuItemState(#TrayMenu, #Menu_Lang_IT, 1)
      Case "DE": SetMenuItemState(#TrayMenu, #Menu_Lang_DE, 1)
      Default:   SetMenuItemState(#TrayMenu, #Menu_Lang_DA, 1)
    EndSelect
    
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

; Handles Windows Auto-start registry key
Procedure SetAutoStartRegistry(Enable.i)
  Protected hKey.i
  If RegOpenKeyEx_(#HKEY_CURRENT_USER, "Software\Microsoft\Windows\CurrentVersion\Run", 0, #KEY_ALL_ACCESS, @hKey) = #ERROR_SUCCESS
    If Enable = 1
      RegSetValueEx_(hKey, "AICopilotMapper", 0, #REG_SZ, @AppPath, StringByteLength(AppPath) + SizeOf(Character))
    Else
      RegDeleteValue_(hKey, "AICopilotMapper")
    EndIf
    RegCloseKey_(hKey)
  EndIf
EndProcedure

; Saves user settings to INI file
Procedure SaveSettings()
  If OpenPreferences(IniFile) Or CreatePreferences(IniFile)
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
  If OpenPreferences(IniFile)
    PreferenceGroup("Settings")
    BrowserPath = ReadPreferenceString("Browser", "")
    AutoStart = ReadPreferenceInteger("AutoStart", 0)
    Language = ReadPreferenceString("Language", "DA")
    SelectedAI = ReadPreferenceString("AI", "Gemini")
    ButtonMode = ReadPreferenceInteger("ButtonMode", 0)
    ClosePreferences()
  EndIf
  If BrowserPath = ""
    If FirstElement(InstalledBrowsers())
      BrowserPath = InstalledBrowsers()\Path
    EndIf
  EndIf
  UpdateTargetURL() 
EndProcedure

; --- KEYBOARD HOOK LOGIC ---

Procedure.l KeyboardProc(nCode, wParam, lParam)
  Protected *pkbdll.KBDLLHOOKSTRUCT = lParam
  
  ; Must pass the hook to next app if nCode is < 0
  If nCode < 0
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  ; Avoid infinite recursion by ignoring injected keys (software generated)
  ; LLMHF_INJECTED = $10
  If *pkbdll\flags & $10
    ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
  EndIf

  If *pkbdll\vkCode = $86 ; Copilot Key / F23
    Select ButtonMode
      Case 0 ; --- AI Shortcut Mode ---
        If wParam = #WM_KEYDOWN
          RunProgram(BrowserPath, "--app=" + TargetURL, "")
        EndIf
        
      Case 1, 2 ; --- Modifier Remapping Mode ---
        Protected VKey.i
        If ButtonMode = 1 : VKey = #VK_RCONTROL : Else : VKey = #VK_RMENU : EndIf
        
        If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
          ; Neutralize ghost keys (Win+Shift) often sent by Copilot hardware
          ; We only neutralize if they are currently pressed to prevent system instability (BSOD protection)
          If GetAsyncKeyState_(#VK_LSHIFT) & $8000
            keybd_event_(#VK_LSHIFT, 0, #KEYEVENTF_KEYUP, 0)
          EndIf
          If GetAsyncKeyState_(#VK_LWIN) & $8000
            keybd_event_(#VK_LWIN, 0, #KEYEVENTF_KEYUP, 0)
          EndIf
          
          ; Send the desired remapped key
          keybd_event_(VKey, 0, 0, 0)
          
        ElseIf wParam = #WM_KEYUP Or wParam = #WM_SYSKEYUP
          ; Release the remapped key
          keybd_event_(VKey, 0, #KEYEVENTF_KEYUP, 0)
        EndIf
    EndSelect
    
    ProcedureReturn 1 ; Block the original F23 event from reaching Windows
  EndIf

  ; Let all other keys pass through
  ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
EndProcedure

; --- MAIN PROGRAM START ---

GetInstalledBrowsers()
LoadSettings()
UpdateLanguageStrings()

; Use a Mutex to prevent multiple instances of the application
Global MutexName.s = "Global\AICopilotMapper_Unique_ID"
hMutex = CreateMutex_(0, 1, @MutexName)
If GetLastError_() = 183 : End : EndIf

; Hidden window to handle background events and tray menu
If OpenWindow(#MainWin, 0, 0, 0, 0, "AICopilotMapper", #PB_Window_Invisible)
  
  ; Load app icon from DataSection
  CatchImage(#AppIcon, ?AppIconStart, ?AppIconEnd - ?AppIconStart)
  AddSysTrayIcon(#TrayIcon, WindowID(#MainWin), ImageID(#AppIcon))
  SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip)
  RebuildMenu()
  
  ; Install the Low-Level Keyboard Hook
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
        
        ; Handle browser selection
        If MenuID >= #Menu_Browser_Base And MenuID < #Menu_Browser_Base + ListSize(InstalledBrowsers())
          SelectElement(InstalledBrowsers(), MenuID - #Menu_Browser_Base)
          BrowserPath = InstalledBrowsers()\Path : SaveSettings() : RebuildMenu()
        Else
          ; Handle static menu items
          Select MenuID
            Case #Menu_Mode_AI : ButtonMode = 0 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_CTRL : ButtonMode = 1 : SaveSettings() : RebuildMenu()
            Case #Menu_Mode_ALT : ButtonMode = 2 : SaveSettings() : RebuildMenu()
            
            Case #Menu_AI_Gemini To #Menu_AI_Copilot
              Select MenuID
                Case #Menu_AI_Gemini : SelectedAI = "Gemini"
                Case #Menu_AI_ChatGPT : SelectedAI = "ChatGPT"
                Case #Menu_AI_Claude : SelectedAI = "Claude"
                Case #Menu_AI_DeepSeek : SelectedAI = "DeepSeek"
                Case #Menu_AI_Perplexity : SelectedAI = "Perplexity"
                Case #Menu_AI_Copilot : SelectedAI = "Copilot"
              EndSelect
              UpdateTargetURL() : SaveSettings() : RebuildMenu()

            Case #Menu_Lang_DA To #Menu_Lang_DE
              Select MenuID
                Case #Menu_Lang_DA : Language = "DA"
                Case #Menu_Lang_EN : Language = "EN"
                Case #Menu_Lang_ES : Language = "ES"
                Case #Menu_Lang_FR : Language = "FR"
                Case #Menu_Lang_IT : Language = "IT"
                Case #Menu_Lang_DE : Language = "DE"
              EndSelect
              UpdateLanguageStrings() : SaveSettings() : RebuildMenu()

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
; Executable = ..\AICopilotMapper.exe
; IncludeVersionInfo
; VersionField0 = 1.0.0.0
; VersionField1 = 1.0.0.0
; VersionField2 = tristan202
; VersionField3 = AI CoPilot Mapper
; VersionField4 = 1.0.0
; VersionField5 = 1.0.0
; VersionField6 = Maps CoPilot key to any AI
; VersionField7 = aicopilotmapper
; VersionField8 = aicopilotmapper.exe
; VersionField13 = tristan202@gmail.com
; VersionField17 = 0800 System Default Language