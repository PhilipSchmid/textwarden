// Exact bundle IDs only. Policy and maintenance: docs/APPLICATION_EXCLUSIONS.md.
// Do not add name, path, vendor-prefix, or wildcard matching here.

enum ApplicationPolicy: Equatable {
    case supported
    case safeTrial
    case pausedByDefault
    case ignored

    var requiresSafeTrialConsent: Bool {
        self == .safeTrial || self == .pausedByDefault
    }

    /// The single list of built-in exceptions. Ignored apps cannot be enabled by user overrides.
    static let defaults: [String: ApplicationPolicy] = [
        // Utilities: configuration, diagnostics, search, or viewing without a prose editor.
        "com.apple.ActivityMonitor": .ignored, // Activity Monitor
        "com.apple.airport.airportutility": .ignored, // AirPort Utility
        "com.apple.audio.AudioMIDISetup": .ignored, // Audio MIDI Setup
        "com.apple.backup.launcher": .ignored, // Time Machine
        "com.apple.BluetoothFileExchange": .ignored, // Bluetooth File Exchange
        "com.apple.calculator": .ignored, // Calculator
        "com.apple.Chess": .ignored, // Chess
        "com.apple.clock": .ignored, // Clock
        "com.apple.ColorSyncUtility": .ignored, // ColorSync Utility
        "com.apple.Console": .ignored, // Console
        "com.apple.Dictionary": .ignored, // Dictionary
        "com.apple.DigitalColorMeter": .ignored, // Digital Color Meter
        "com.apple.DiskUtility": .ignored, // Disk Utility
        "com.apple.exposelauncher": .ignored, // Mission Control
        "com.apple.findmy": .ignored, // FindMy
        "com.apple.FontBook": .ignored, // Font Book
        "com.apple.games": .ignored, // Games
        "com.apple.helpviewer": .ignored, // Tips
        "com.apple.Image_Capture": .ignored, // Image Capture
        "com.apple.Magnifier": .ignored, // Magnifier
        "com.apple.MigrateAssistant": .ignored, // Migration Assistant
        "com.apple.Passwords": .ignored, // Passwords
        "com.apple.Passwords.MenuBarExtra": .ignored, // PasswordsMenuBarExtra
        "com.apple.PhotoBooth": .ignored, // Photo Booth
        "com.apple.printcenter": .ignored, // Print Center
        "com.apple.ScreenContinuity": .ignored, // iPhone Mirroring
        "com.apple.ScreenSharing": .ignored, // Screen Sharing
        "com.apple.screenshot.launcher": .ignored, // Screenshot
        "com.apple.stocks": .ignored, // Stocks
        "com.apple.systempreferences": .ignored, // System Settings
        "com.apple.SystemProfiler": .ignored, // System Information
        "com.apple.VoiceOverUtility": .ignored, // VoiceOver Utility
        "com.apple.weather": .ignored, // Weather
        "com.apple.weather.menu": .ignored, // WeatherMenu

        // Authentication, credentials, device management, and security prompts.
        "com.apple.AppSSOAgent": .ignored, // AppSSOAgent
        "com.apple.authkit.AuthKitHeadlessUIHelper": .ignored, // AuthKitUIMacService
        "com.apple.AutoFillPanelService": .ignored, // AutoFillPanelService
        "com.apple.CaptiveNetworkAssistant": .ignored, // Captive Network Assistant
        "com.apple.CertificateAssistant": .ignored, // Certificate Assistant
        "com.apple.devicemanagementclient.alertagent": .ignored, // LaunchPolicyAlertAgent
        "com.apple.DirectoryUtility": .ignored, // Directory Utility
        "com.apple.eap8021x.eaptlstrust": .ignored, // eaptlstrust
        "com.apple.EraseAssistant": .ignored, // Erase Assistant
        "com.apple.EscrowSecurityAlert": .ignored, // EscrowSecurityAlert
        "com.apple.KerberosMenuExtra": .ignored, // KerberosMenuExtra
        "com.apple.keychainaccess": .ignored, // Keychain Access
        "com.apple.LockScreen": .ignored, // LockScreen
        "com.apple.loginwindow": .ignored, // loginwindow
        "com.apple.ManagedClient": .ignored, // ManagedClient
        "com.apple.mcx.MCXDiskAuthorization": .ignored, // MCXDiskAuthorization
        "com.apple.mcx.ProfileHelper": .ignored, // ProfileHelper
        "com.apple.MRT": .ignored, // MRT
        "com.apple.NetAuthAgent": .ignored, // NetAuthAgent
        "com.apple.PlatformSSO.PlatformSSOUIAgent": .ignored, // PlatformSSOUIAgent
        "com.apple.security.Keychain-Circle-Notification": .ignored, // Keychain Circle Notification
        "com.apple.SetupAssistant": .ignored, // Setup Assistant
        "com.apple.tcc.AuthorizationPromptService": .ignored, // AuthorizationPromptService
        "com.apple.Ticket-Viewer": .ignored, // Ticket Viewer
        "com.apple.WebDAVFS.webdav-cert-ui": .ignored, // webdav_cert_ui
        "com.apple.XProtectFramework.XProtect": .ignored, // XProtect

        // System UI, hardware setup, installers, and utility helpers.
        "com.apple.AboutThisMacLauncher": .ignored, // About This Mac
        "com.apple.AccessibilityOnboarding": .ignored, // Accessibility Tutorial
        "com.apple.AccessibilityUIServer": .ignored, // AccessibilityUIServer
        "com.apple.AirPlayUIAgent": .ignored, // AirPlayUIAgent
        "com.apple.AOSAlertManager": .ignored, // AOSAlertManager
        "com.apple.AOSUIPrefPaneLauncher": .ignored, // AOSUIPrefPaneLauncher
        "com.apple.apps.launcher": .ignored, // Apps
        "com.apple.archiveutility": .ignored, // Archive Utility
        "com.apple.AskPermissionUI": .ignored, // AskPermissionUI
        "com.apple.AutomatorInstaller": .ignored, // Automator Installer
        "com.apple.AVB-Audio-Configuration": .ignored, // AVB Configuration
        "com.apple.backgroundtaskmanagement.agent": .ignored, // BackgroundTaskManagementAgent
        "com.apple.Batteries": .ignored, // Batteries
        "com.apple.BluetoothSetupAssistant": .ignored, // BluetoothSetupAssistant
        "com.apple.BluetoothUIServer": .ignored, // BluetoothUIServer
        "com.apple.BluetoothUIService": .ignored, // BluetoothUIService
        "com.apple.Calibration-Assistant": .ignored, // Calibration Assistant
        "com.apple.ClockAngel": .ignored, // ClockAngel
        "com.apple.ColorSyncCalibrator": .ignored, // Display Calibrator
        "com.apple.controlcenter": .ignored, // ControlCenter
        "com.apple.CoreLocationAgent": .ignored, // CoreLocationAgent
        "com.apple.coreservices.UASharedPasteboardProgressUI": .ignored, // UASharedPasteboardProgressUI
        "com.apple.coreservices.uiagent": .ignored, // CoreServicesUIAgent
        "com.apple.DeskCam": .ignored, // Desk View
        "com.apple.DiagnosticsModeAssistant": .ignored, // Apple Diagnostics
        "com.apple.DiagnosticsReporter": .ignored, // Diagnostics Reporter
        "com.apple.DiscHelper": .ignored, // DiscHelper
        "com.apple.DiskImageMounter": .ignored, // DiskImageMounter
        "com.apple.dock": .ignored, // Dock
        "com.apple.dt.CommandLineTools.installondemand": .ignored, // Install Command Line Developer Tools
        "com.apple.DVDPlayer": .ignored, // DVD Player
        "com.apple.EnhancedLogging": .ignored, // Enhanced Logging
        "com.apple.ExpansionSlotUtility": .ignored, // Expansion Slot Utility
        "com.apple.familycontrols.useragent": .ignored, // ParentalControls
        "com.apple.FileSystemUIAgent": .ignored, // FileSystemUIAgent
        "com.apple.finder": .ignored, // Finder
        "com.apple.finder.Open-AirDrop": .ignored, // AirDrop
        "com.apple.finder.Open-AllMyFiles": .ignored, // All My Files
        "com.apple.finder.Open-Computer": .ignored, // Computer
        "com.apple.finder.Open-iCloudDrive": .ignored, // iCloud Drive
        "com.apple.finder.Open-Network": .ignored, // Network
        "com.apple.finder.Open-Recents": .ignored, // Recents
        "com.apple.FolderActionsSetup": .ignored, // Folder Actions Setup
        "com.apple.FontRegistryUIAgent": .ignored, // FontRegistryUIAgent
        "com.apple.frameworks.diskimages.diuiagent": .ignored, // DiskImages UI Agent
        "com.apple.installer": .ignored, // Installer
        "com.apple.Installer-Progress": .ignored, // Installer Progress
        "com.apple.IOUIAgent": .ignored, // IOUIAgent
        "com.apple.IPAInstaller": .ignored, // iOS App Installer
        "com.apple.KeyboardSetupAssistant": .ignored, // KeyboardSetupAssistant
        "com.apple.Language-Chooser": .ignored, // Language Chooser
        "com.apple.MDMMigrationTrampoline": .ignored, // MDMMigrationTrampoline
        "com.apple.MedicalImagingCalibrator": .ignored, // Medical Imaging Calibrator
        "com.apple.MemorySlotUtility": .ignored, // Memory Slot Utility
        "com.apple.MenuBarAgent": .ignored, // MenuBarAgent
        "com.apple.MobileDeviceUpdater": .ignored, // MobileDeviceUpdater
        "com.apple.NewDeviceOutreachApp": .ignored, // Coverage Details
        "com.apple.notificationcenterui": .ignored, // NotificationCenter
        "com.apple.NowPlayingTouchUI": .ignored, // NowPlayingTouchUI
        "com.apple.OAHSoftwareUpdateApp": .ignored, // Rosetta 2 Updater
        "com.apple.OBEXAgent": .ignored, // OBEXAgent
        "com.apple.OSDUIHelper": .ignored, // OSDUIHelper
        "com.apple.PackageUIKit.Install-in-Progress": .ignored, // Install in Progress
        "com.apple.PairedDevices": .ignored, // Paired Devices
        "com.apple.Pass-Viewer": .ignored, // Pass Viewer
        "com.apple.PassViewer": .ignored, // PassViewer
        "com.apple.PeopleMessageService": .ignored, // PeopleMessageService
        "com.apple.PIPAgent": .ignored, // PIPAgent
        "com.apple.PowerChime": .ignored, // PowerChime
        "com.apple.preference.displays.MirrorDisplays": .ignored, // MirrorDisplays
        "com.apple.print.add": .ignored, // AddPrinter
        "com.apple.RapportUIAgent": .ignored, // RapportUIAgent
        "com.apple.screencaptureui": .ignored, // screencaptureui
        "com.apple.ScreenSaver.Engine": .ignored, // ScreenSaverEngine
        "com.apple.ScreenTimeWidgetApplication": .ignored, // Screen Time
        "com.apple.Settings": .ignored, // SettingsPlaceholder
        "com.apple.Sharing.AirDropUI": .ignored, // AirDropUI
        "com.apple.SoftwareUpdate": .ignored, // Software Update
        "com.apple.SoftwareUpdateLauncher": .ignored, // SoftwareUpdateLauncher
        "com.apple.SoftwareUpdateNotificationManager": .ignored, // SoftwareUpdateNotificationManager
        "com.apple.SpacesTouchBarAgent": .ignored, // SpacesTouchBarAgent
        "com.apple.Spotlight": .ignored, // Spotlight
        "com.apple.systemuiserver": .ignored, // SystemUIServer
        "com.apple.TextInputMenuAgent": .ignored, // TextInputMenuAgent
        "com.apple.TextInputSwitcher": .ignored, // TextInputSwitcher
        "com.apple.ThermalTrap": .ignored, // ThermalTrap
        "com.apple.timemachine.HelperAgent": .ignored, // TMHelperAgent
        "com.apple.tips": .ignored, // TipsSpotlightHandler
        "com.apple.UniversalAccessControl": .ignored, // UniversalAccessControl
        "com.apple.UnmountAssistantAgent": .ignored, // UnmountAssistantAgent
        "com.apple.UserNotificationCenter": .ignored, // UserNotificationCenter
        "com.apple.VNCGuestRequest": .ignored, // Share Screen Request
        "com.apple.VoiceOverQuickstart": .ignored, // VoiceOver Quickstart
        "com.apple.VoiceOverUtilityCacheBuilder": .ignored, // VoiceOverUtilityCacheBuilder
        "com.apple.WatchFaceAlert": .ignored, // WatchFaceAlert
        "com.apple.wifi.diagnostics": .ignored, // Wireless Diagnostics
        "com.apple.wifi.WiFiAgent": .ignored, // WiFiAgent
        "com.apple.WindowManager": .ignored, // WindowManager
        "com.apple.windowmanager.StageManagerOnboarding": .ignored, // StageManagerOnboarding
        "com.apple.WorkoutAlert-Mac": .ignored, // WorkoutAlert-Mac

        // Credential vaults and installed utility apps without a general writing surface.
        "com.1password.1password": .ignored, // 1Password; vault contents stay outside the monitoring pipeline
        "2BUA8C4S2C.com.1password.browser-helper": .ignored, // 1Password Browser Helper
        "com.1password.1password-launcher": .ignored, // 1Password Launcher
        "com.1password.OP-Updater": .ignored, // 1Password Updater
        "com.1password.1password.helper": .ignored, // 1Password Helper
        "com.1password.1password.helper.GPU": .ignored, // 1Password GPU Helper
        "com.1password.1password.helper.Renderer": .ignored, // 1Password Renderer Helper
        "com.1password.1password.helper.Plugin": .ignored, // 1Password Plugin Helper
        "org.sparkle-project.Sparkle.Autoupdate": .ignored, // Sparkle updater
        "pro.betterdisplay.BetterDisplay": .ignored, // BetterDisplay
        "com.steipete.codexbar": .ignored, // CodexBar
        "com.adobe.acc.AdobeCreativeCloud": .ignored, // Creative Cloud app manager
        "com.adobe.acc.anc.AdobeCreativeCloud": .ignored, // Creative Cloud notification client
        "com.adobe.Creative-Cloud-Desktop-App": .ignored, // Creative Cloud Desktop App
        "Qisda.DDPM": .ignored, // Dell Display and Peripheral Manager
        "com.apple.IconComposer": .ignored, // Icon Composer
        "com.intego.commonservices.integomenu": .ignored, // Intego menu
        "com.intego.virusbarrier.alert": .ignored, // VirusBarrier Alert
        "com.intego.virusbarrier.application": .ignored, // VirusBarrier
        "com.intego.NetUpdate": .ignored, // Intego NetUpdate
        "com.logi.optionsplus": .ignored, // Logi Options+
        "com.logi.cp-dev-mgr": .ignored, // Logi Options+ agent
        "com.fabriceleyne.menubarstats": .ignored, // MenuBar Stats
        "com.fabriceleyne.menubarstatshelper": .ignored, // MenuBar Stats helper
        "com.microsoft.autoupdate2": .ignored, // Microsoft AutoUpdate
        "com.microsoft.autoupdate.fba": .ignored, // Microsoft Update Assistant
        "com.microsoft.OneDrive": .ignored, // OneDrive sync client; documents open in their editors
        "wang.jianing.app.OpenInTerminal": .ignored, // OpenInTerminal
        "wang.jianing.app.OpenInTerminalHelper": .ignored, // OpenInTerminal helper
        "com.techsmith.snagit.capturehelper": .ignored, // Snagit capture helper
        "com.TechSmith.SupportSnagit": .ignored, // Snagit diagnostic utility
        "io.tailscale.ipn.macos": .ignored, // Tailscale
        "com.tresorit.mac": .ignored, // Tresorit sync client; documents open in their editors
        "com.stonerl.Thaw": .ignored, // Thaw menu bar manager
        "com.apple.universalcontrol": .ignored, // Universal Control
        "com.apple.accessibility.universalAccessAuthWarn": .ignored, // Accessibility authorization warning
        "com.electron.wispr-flow.accessibility-mac-app": .ignored, // Wispr Flow accessibility helper; retain the notes app

        // Product exclusions: keep specialized apps quiet even if they have occasional prose fields.
        "com.apple.AppStore": .ignored, // App reviews
        "com.apple.podcasts": .ignored, // Podcast reviews
        "com.adobe.lightroomCC": .ignored, // Photo captions
        "com.TechSmith.Snagit": .ignored, // Text annotations
        "com.valvesoftware.steam": .ignored, // Chat and reviews
        "com.valvesoftware.steam.helper": .ignored, // Steam web UI can host chat
        "net.battle.app": .ignored, // Battle.net game launcher
        "com.blizzard.blizzarderror": .ignored, // Blizzard crash reporter
        "com.docker.docker": .ignored, // Container tooling with AI prompts
        "com.electron.dockerdesktop": .ignored, // Docker Desktop UI
        "app.omlx": .ignored, // Model management with chat access

        "com.openai.sky.CUAService": .ignored, // Codex Computer Use; not the main Codex app
        "com.microsoft.errorreporting": .ignored, // Microsoft Error Reporting
        "com.apple.Music": .ignored, // Music
        "com.readdle.PDFExpert-Mac": .ignored, // PDF Expert
        "com.apple.Photos": .ignored, // Photos
        "com.apple.Preview": .ignored, // Preview
        "com.apple.ProblemReporter": .ignored, // Problem Reporter
        "com.apple.appleseed.FeedbackAssistant": .ignored, // Feedback Assistant

        // These two apps have general writing editors: retain an explicit opt-in.
        "com.raycast.macos": .pausedByDefault, // Notes and AI chat
        "com.electron.wispr-flow": .pausedByDefault, // Dictation with editable notes and transcripts

        // Self-monitoring and the existing window-management exclusion.
        "io.textwarden.TextWarden": .ignored,
        "com.knollsoft.Rectangle": .ignored,

        // Terminals can contain prose: keep an explicit opt-in instead of a hard exclusion.
        "app.crynta.terax": .pausedByDefault, // Terax terminal and editor
        "com.apple.Terminal": .pausedByDefault,
        "com.googlecode.iterm2": .pausedByDefault,
        "co.zeit.hyper": .pausedByDefault,
        "dev.warp.Warp-Stable": .pausedByDefault,
        "org.alacritty": .pausedByDefault,
        "net.kovidgoyal.kitty": .pausedByDefault,
        "com.github.wez.wezterm": .pausedByDefault,
        "com.mitchellh.ghostty": .pausedByDefault,
    ]
}
