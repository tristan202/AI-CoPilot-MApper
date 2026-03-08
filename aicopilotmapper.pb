EnableExplicit

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
Global SelectedAI.s = "Gemini" ; Default AI
Global TargetURL.s = "https://gemini.google.com"
Global AutoStart.i = 0
Global Language.s = "DA"
Global hMutex, hHook

; String Variables
Global Txt_MsgBoxTitle.s, Txt_MsgBoxRunning.s
Global Txt_TrayTooltip.s, Txt_MenuBrowser.s, Txt_MenuAI.s
Global Txt_MenuAutoStart.s, Txt_MenuLanguage.s, Txt_MenuAbout.s, Txt_MenuExit.s
Global Txt_AboutTitle.s, Txt_AboutText.s

; Menu IDs
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

; Helper function for registry
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

; Find installed browsers
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

; Update target URL
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

; Language strings function
Procedure UpdateLanguageStrings()
  Protected AppName.s = "AI Copilot Mapper"
  
  Select Language
    Case "EN"
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = AppName + " is already running!" + Chr(10) + "You can find the icon in the system tray."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "Select AI"
      Txt_MenuBrowser = "Select Browser" 
      Txt_MenuAutoStart = "Start with Windows"
      Txt_MenuLanguage = "Language"
      Txt_MenuAbout = "About"
      Txt_MenuExit = "Exit"
      Txt_AboutTitle = "About " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Developed to remap the Windows Copilot key to your favorite AI."
      
    Case "ES"
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = "¡" + AppName + " ya se está ejecutando!" + Chr(10) + "Puedes encontrar el icono en la bandeja del sistema."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "Seleccionar IA"
      Txt_MenuBrowser = "Seleccionar navegador"
      Txt_MenuAutoStart = "Iniciar con Windows"
      Txt_MenuLanguage = "Idioma"
      Txt_MenuAbout = "Acerca de"
      Txt_MenuExit = "Salir"
      Txt_AboutTitle = "Acerca de " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Desarrollado para reasignar la tecla Copilot de Windows a tu IA favorita."
      
    Case "FR"
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = AppName + " est déjà en cours d'exécution !" + Chr(10) + "Vous pouvez trouver l'icône dans la zone de notification."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "Sélectionner l'IA"
      Txt_MenuBrowser = "Sélectionner le navigateur"
      Txt_MenuAutoStart = "Démarrer avec Windows"
      Txt_MenuLanguage = "Langue"
      Txt_MenuAbout = "À propos"
      Txt_MenuExit = "Quitter"
      Txt_AboutTitle = "À propos de " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Développé pour remapper la touche Windows Copilot vers votre IA préférée."
      
    Case "IT"
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = AppName + " è già in esecuzione!" + Chr(10) + "Puoi trovare l'icona nella barra delle applicazioni."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "Seleziona IA"
      Txt_MenuBrowser = "Seleziona browser"
      Txt_MenuAutoStart = "Avvia con Windows"
      Txt_MenuLanguage = "Lingua"
      Txt_MenuAbout = "Informazioni"
      Txt_MenuExit = "Esci"
      Txt_AboutTitle = "Informazioni su " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Sviluppato per rimappare il tasto Windows Copilot alla tua IA preferita."
      
    Case "DE"
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = AppName + " wird bereits ausgeführt!" + Chr(10) + "Sie finden das Symbol in der Taskleiste."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "KI auswählen"
      Txt_MenuBrowser = "Browser auswählen"
      Txt_MenuAutoStart = "Mit Windows starten"
      Txt_MenuLanguage = "Sprache"
      Txt_MenuAbout = "Über"
      Txt_MenuExit = "Beenden"
      Txt_AboutTitle = "Über " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Entwickelt, um die Windows Copilot-Taste Ihrer Lieblings-KI neu zuzuweisen."
      
    Default ; "DA" is default
      Txt_MsgBoxTitle = AppName
      Txt_MsgBoxRunning = AppName + " kører allerede!" + Chr(10) + "Du kan finde ikonet i systembakken."
      Txt_TrayTooltip = AppName
      Txt_MenuAI = "Vælg AI"
      Txt_MenuBrowser = "Vælg Browser" 
      Txt_MenuAutoStart = "Start med Windows"
      Txt_MenuLanguage = "Sprog"
      Txt_MenuAbout = "Om programmet"
      Txt_MenuExit = "Afslut"
      Txt_AboutTitle = "Om " + AppName
      Txt_AboutText = AppName + " v1.0.0" + Chr(10) + "Udviklet til at omkode Windows Copilot-tasten til din foretrukne AI."
  EndSelect
EndProcedure

; Menu builder
Procedure RebuildMenu()
  Protected Index = 0
  
  If CreatePopupMenu(#TrayMenu)
    
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
    MenuBar()
    
    ; Language submenu
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
    
    ; Tick chosen AI
    Select SelectedAI
      Case "ChatGPT"    : SetMenuItemState(#TrayMenu, #Menu_AI_ChatGPT, 1)
      Case "Claude"     : SetMenuItemState(#TrayMenu, #Menu_AI_Claude, 1)
      Case "DeepSeek"   : SetMenuItemState(#TrayMenu, #Menu_AI_DeepSeek, 1)
      Case "Perplexity" : SetMenuItemState(#TrayMenu, #Menu_AI_Perplexity, 1)
      Case "Copilot"    : SetMenuItemState(#TrayMenu, #Menu_AI_Copilot, 1)
      Default           : SetMenuItemState(#TrayMenu, #Menu_AI_Gemini, 1)
    EndSelect
    
    ; Tick for the rest
    SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
    
    Select Language
      Case "EN": SetMenuItemState(#TrayMenu, #Menu_Lang_EN, 1)
      Case "ES": SetMenuItemState(#TrayMenu, #Menu_Lang_ES, 1)
      Case "FR": SetMenuItemState(#TrayMenu, #Menu_Lang_FR, 1)
      Case "IT": SetMenuItemState(#TrayMenu, #Menu_Lang_IT, 1)
      Case "DE": SetMenuItemState(#TrayMenu, #Menu_Lang_DE, 1)
      Default:   SetMenuItemState(#TrayMenu, #Menu_Lang_DA, 1)
    EndSelect
  EndIf
EndProcedure

; Windows autostart registry management
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

; Load/Save settings
Procedure SaveSettings()
  If OpenPreferences(IniFile) Or CreatePreferences(IniFile)
    PreferenceGroup("Settings")
    WritePreferenceString("Browser", BrowserPath)
    WritePreferenceInteger("AutoStart", AutoStart)
    WritePreferenceString("Language", Language)
    WritePreferenceString("AI", SelectedAI)
    ClosePreferences()
  EndIf
EndProcedure

Procedure LoadSettings()
  If OpenPreferences(IniFile)
    PreferenceGroup("Settings")
    BrowserPath = ReadPreferenceString("Browser", "")
    AutoStart = ReadPreferenceInteger("AutoStart", 0)
    Language = ReadPreferenceString("Language", "DA")
    SelectedAI = ReadPreferenceString("AI", "Gemini")
    ClosePreferences()
  EndIf
  
  If BrowserPath = ""
    FirstElement(InstalledBrowsers())
    BrowserPath = InstalledBrowsers()\Path
  EndIf
  
  UpdateTargetURL() 
EndProcedure

; Keyboard Hook procedure
Procedure.l KeyboardProc(nCode, wParam, lParam)
  Protected *pkbdll.KBDLLHOOKSTRUCT = lParam
  If nCode = 0
    If *pkbdll\vkCode = $86 ; Copilot Key / F23
      If wParam = $0100 ; Keydown
        RunProgram(BrowserPath, "--app=" + TargetURL, "")
      EndIf
      ProcedureReturn 1 ; Block original event
    EndIf
  EndIf
  ProcedureReturn CallNextHookEx_(hHook, nCode, wParam, lParam)
EndProcedure

; --- MAIN PROGRAM START ---
GetInstalledBrowsers()
LoadSettings()
UpdateLanguageStrings()
SetAutoStartRegistry(AutoStart)

; Unique Mutex to prevent multiple instances
Global MutexName.s = "Global\AICopilotMapper_Unique_ID"
hMutex = CreateMutex_(0, 1, @MutexName)
If GetLastError_() = 183
  MessageRequester(Txt_MsgBoxTitle, Txt_MsgBoxRunning, #PB_MessageRequester_Info)
  If hMutex : CloseHandle_(hMutex) : EndIf
  End
EndIf

; Invisible main window to handle tray events
If OpenWindow(#MainWin, 0, 0, 0, 0, "AICopilotMapper", #PB_Window_Invisible)
  
  ; Load Icon from DataSection (Self-contained)
  If Not CatchImage(#AppIcon, ?AppIconStart, ?AppIconEnd - ?AppIconStart)
    ; Fallback if catching fails
    CreateImage(#AppIcon, 16, 16) 
    StartDrawing(ImageOutput(#AppIcon))
      Box(0, 0, 16, 16, RGB(255, 0, 255)) ; Pink square indicates a resource error
    StopDrawing()
  EndIf
  
  AddSysTrayIcon(#TrayIcon, WindowID(#MainWin), ImageID(#AppIcon))
  SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip)
  
  RebuildMenu()
  
  ; Install Keyboard Hook
  hHook = SetWindowsHookEx_(13, @KeyboardProc(), GetModuleHandle_(0), 0)
  
  ; Main Event Loop
  Repeat
    Define Event = WaitWindowEvent()
    Select Event
      Case #PB_Event_SysTray
        If EventType() = #PB_EventType_RightClick
          DisplayPopupMenu(#TrayMenu, WindowID(#MainWin))
        EndIf
        
      Case #PB_Event_Menu
        Define MenuID = EventMenu()
        
        ; Browser selection
        If MenuID >= #Menu_Browser_Base And MenuID < #Menu_Browser_Base + ListSize(InstalledBrowsers())
          SelectElement(InstalledBrowsers(), MenuID - #Menu_Browser_Base)
          BrowserPath = InstalledBrowsers()\Path
          SaveSettings()
          RebuildMenu() 
          
        Else
          Select MenuID
            ; --- AI SELECTION ---
            Case #Menu_AI_Gemini, #Menu_AI_ChatGPT, #Menu_AI_Claude, #Menu_AI_DeepSeek, #Menu_AI_Perplexity, #Menu_AI_Copilot
              Select MenuID
                Case #Menu_AI_Gemini    : SelectedAI = "Gemini"
                Case #Menu_AI_ChatGPT   : SelectedAI = "ChatGPT"
                Case #Menu_AI_Claude    : SelectedAI = "Claude"
                Case #Menu_AI_DeepSeek  : SelectedAI = "DeepSeek"
                Case #Menu_AI_Perplexity: SelectedAI = "Perplexity"
                Case #Menu_AI_Copilot   : SelectedAI = "Copilot"
              EndSelect
              UpdateTargetURL()
              SaveSettings()
              RebuildMenu()

            ; --- OTHER FUNCTIONS ---
            Case #Menu_AutoStart
              AutoStart = 1 - AutoStart 
              SetAutoStartRegistry(AutoStart)
              SaveSettings()
              SetMenuItemState(#TrayMenu, #Menu_AutoStart, AutoStart)
              
            Case #Menu_Lang_DA, #Menu_Lang_EN, #Menu_Lang_ES, #Menu_Lang_FR, #Menu_Lang_IT, #Menu_Lang_DE
              Select MenuID
                Case #Menu_Lang_DA: Language = "DA"
                Case #Menu_Lang_EN: Language = "EN"
                Case #Menu_Lang_ES: Language = "ES"
                Case #Menu_Lang_FR: Language = "FR"
                Case #Menu_Lang_IT: Language = "IT"
                Case #Menu_Lang_DE: Language = "DE"
              EndSelect
              SaveSettings()
              UpdateLanguageStrings()
              RebuildMenu() 
              SysTrayIconToolTip(#TrayIcon, Txt_TrayTooltip) 
              
            Case #Menu_About
              If OpenWindow(#AboutWin, 0, 0, 300, 220, Txt_AboutTitle, #PB_Window_SystemMenu | #PB_Window_ScreenCentered)
                StickyWindow(#AboutWin, #True)
                ImageGadget(#About_ImageGadget, 126, 20, 48, 48, ImageID(#AppIcon))    
                TextGadget(#About_TextGadget, 10, 80, 280, 60, Txt_AboutText, #PB_Text_Center)
                HyperLinkGadget(#About_LinkGadget, 90, 145, 280, 20, "Visit GitHub Repository", RGB(0, 0, 255), #PB_HyperLink_Underline)
                SetGadgetColor(#About_LinkGadget, #PB_Gadget_FrontColor, RGB(0, 102, 204))
                ButtonGadget(#About_CloseBtn, 110, 180, 80, 25, "OK")    
                Repeat
                  Define AboutEvent = WaitWindowEvent()
                  Select AboutEvent
                    Case #PB_Event_Gadget
                      Select EventGadget()
                        Case #About_LinkGadget
                          RunProgram("https://github.com/tristan202/AI-Copilot-Mapper")
              
                        Case #About_CloseBtn
                          CloseWindow(#AboutWin)
                          Break
                      EndSelect
          
                    Case #PB_Event_CloseWindow
                      If EventWindow() = #AboutWin
                        CloseWindow(#AboutWin)
                        Break
                      EndIf
                  EndSelect
                ForEver
              EndIf
              
            Case #Menu_Exit
              Break
          EndSelect
        EndIf
    EndSelect
  Until Event = #PB_Event_CloseWindow

  ; Cleanup
  If hHook : UnhookWindowsHookEx_(hHook) : EndIf
  RemoveSysTrayIcon(#TrayIcon)
  If hMutex : CloseHandle_(hMutex) : EndIf
EndIf

; --- DATA SECTION FOR EMBEDDED RESOURCES ---
DataSection
  AppIconStart: 
    IncludeBinary "aicopilotmapper.ico"
  AppIconEnd:
EndDataSection
; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 438
; FirstLine = 424
; Folding = --
; Optimizer
; EnableXP
; DPIAware
; UseIcon = aicopilotmapper.ico
; Executable = ..\AICopilotMapper.exe
; DisableDebugger
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