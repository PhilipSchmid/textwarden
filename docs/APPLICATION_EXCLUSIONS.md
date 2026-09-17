# Application exclusions

TextWarden should stay quiet in system utilities and credential dialogs. A search box,
file name, account field, or device label is not a reason to offer grammar checking.
This policy addresses [discussion #123](https://github.com/PhilipSchmid/textwarden/discussions/123).

## One editable list

[`ApplicationPolicy.defaults`](../Sources/AppConfiguration/ApplicationPolicy.swift)
is the authoritative list. Each entry is an exact, case-sensitive bundle identifier:

- `.ignored`: no text monitoring, consent prompt, or action to enable checking.
- `.pausedByDefault`: paused until the user opts in; currently used for terminals.

There are no application-name, path, vendor-prefix, or wildcard rules. An identifier
absent from the list uses its registered support profile, or requires safe-trial
consent if no profile exists. An uninstalled identifier has no effect, so older macOS
entries need not be removed when Apple renames an app.

Do not exclude every Apple app or every process with `LSUIElement`. Helpers can host
real editors too. Preview annotations, Books notes, Photos captions, Live Speech,
Shortcuts, Script Editor, Feedback Assistant, and generic script/application hosts
remain eligible. Unknown does not mean supported: an eligible unregistered app still
requires consent and starts with copy-only fixes.

Third-party antivirus and security panels need verified bundle identifiers and a
review of their writing features. Do not guess identifiers or block an entire vendor.
Use the [exclusion report form](https://github.com/PhilipSchmid/textwarden/issues/new?template=application_exclusion.yml).

## Where the policy is enforced

`AppRegistry.policy(for:)` checks this list before registered app configurations.
`UserPreferences.isEnabled(for:)` rejects ignored apps before saved Active or safe-trial
choices. Resetting preferences cannot remove a built-in exclusion.

`AnalysisCoordinator` resolves runtime health before starting or resuming monitoring.
An ignored app resolves to inactive with no recovery action, before permission and
consent checks. `TextMonitor.startMonitoring` also checks `ApplicationContext.shouldCheck()`.
The menu hides per-app enable actions for these apps. Settings lists installed exclusions
read-only; it does not keep another exclusion list.

The application tracker must still report focus changes into an excluded app, so the
coordinator stops monitoring the previous editor and clears its overlays. Skipping the
focus notification would leave stale UI behind. AI editor actions use the monitored
text element, which is cleared when monitoring stops. This list controls external app
monitoring; TextWarden's own Sketch Pad continues to work internally.

## Exclude an app or suggest a default

Open Settings → Applications. Choose Paused Until Resumed, or use Pause Another App…
to select an app without launching it. Apps awaiting approval offer the same pause in
their More menu. A personal pause persists across restarts and can be resumed.

More → Suggest Default Exclusion… opens a GitHub draft containing only the app name
and bundle identifier. Explain what the app does and whether it has any prose editors.
Review the draft before submitting; no report or diagnostic data is sent automatically.

For a code change, verify `CFBundleIdentifier` in the installed app's
`Contents/Info.plist`, add it to the appropriate group in `ApplicationPolicy.defaults`,
and extend `SafeTrialPromptControllerTests` if the case introduces a new boundary.
Check that the app stays inactive even with previously saved consent and an Active
override, and that switching back to a writing app resumes normal checking.

## macOS audit: 27 beta, build 26A428

The 2026-09-17 inventory covered `/System/Applications`, `/System/Library`,
`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/usr/libexec`, `/Library/Apple`,
and the App/OS cryptex application and `usr` trees. User-installed software and user
folders were outside the audit. Bundle metadata and Mach-O headers were inspected;
system executables were not launched en masse.

| Inventory | Result |
| --- | ---: |
| App bundle copies with readable metadata | 333 |
| Distinct app bundle identifiers reviewed below | 329 |
| Shipped app identifiers explicitly excluded | 161 |
| Mach-O executable files (`MH_EXECUTE`) | 3,290 |
| Executables inside app bundles, including their helpers | 577 |
| Executables in XPC services or extensions outside app bundles | 892 |
| Other command/helper executables | 1,821 |
| Executable scripts | 297 |

The scan also encountered loadable Mach-O libraries/bundles and resources carrying
executable permission bits. These are not independent foreground applications.
Command-line tools, daemons, XPC services, and frameworks are handled through their
foreground host where applicable; adding their executable names as app exclusions
would have no effect. For example, commands in Terminal inherit Terminal's pause.
Some non-app plists even declare `APPL` for frameworks or schemas, so that metadata
alone is not enough to classify an application.

This is a static inventory and policy review, not a claim that every system executable
or UI flow was exercised. Protected directories/files and dangling framework links
could not be read (3,029 recorded access/link failures). The inventory therefore does
not prove coverage of every binary in every macOS installation. No system protections
were changed. Earlier macOS versions were not available for a live audit; existing
exact-ID defaults were retained, and the implementation uses no macOS 27-only APIs.

Tips deserves special attention: the visible app uses `com.apple.helpviewer` on this
build; `com.apple.tips` belongs to TipsSpotlightHandler. Both are excluded.

### Reviewed app inventory

This table records the audit, not a second configuration file. Change the Swift list
above to change behavior. “Retained” means no new exclusion: either the app can accept
useful text, hosts variable content, or is an internal helper without enough evidence
for a permanent block. Such helpers do not normally become foreground editors; if one
does, the ordinary consent gate still applies. “Paused” keeps the existing terminal
opt-in. Duplicate shipped copies are collapsed by identifier.

<details>
<summary>All 329 reviewed identifiers</summary>

| Application or helper | Bundle identifier | Decision |
| --- | --- | --- |
| 50onPaletteServer | `com.apple.50onPaletteIM` | Retained |
| ABAssistantService | `com.apple.ABAssistantService` | Retained |
| About This Mac | `com.apple.AboutThisMacLauncher` | Excluded |
| Accessibility Reader | `com.apple.accessibility.AccessibilityReader` | Retained |
| Accessibility Tutorial | `com.apple.AccessibilityOnboarding` | Excluded |
| AccessibilityUIServer | `com.apple.AccessibilityUIServer` | Excluded |
| AccessibilityVisualsAgent | `com.apple.AccessibilityVisualsAgent` | Retained |
| Activity Monitor | `com.apple.ActivityMonitor` | Excluded |
| AddPrinter | `com.apple.print.add` | Excluded |
| AddressBookManager | `com.apple.AddressBook.abd` | Retained |
| AddressBookSourceSync | `com.apple.AddressBookSourceSync` | Retained |
| AddressBookSync | `com.apple.AddressBook.sync` | Retained |
| AddressBookUrlForwarder | `com.apple.AddressBook.UrlForwarder` | Retained |
| AinuIM | `com.apple.inputmethod.Ainu` | Retained |
| AirDrop | `com.apple.finder.Open-AirDrop` | Excluded |
| AirDropUI | `com.apple.Sharing.AirDropUI` | Excluded |
| AirPlayUIAgent | `com.apple.AirPlayUIAgent` | Excluded |
| AirPort Utility | `com.apple.airport.airportutility` | Excluded |
| AirScanLegacyDiscovery | `com.apple.print.AirScanLegacyDiscovery` | Retained |
| AirScanScanner | `com.apple.AirScanScanner` | Retained |
| All My Files | `com.apple.finder.Open-AllMyFiles` | Excluded |
| AMSEngagementViewService | `com.apple.AMSEngagementViewService` | Retained |
| AOSAlertManager | `com.apple.AOSAlertManager` | Excluded |
| AOSHeartbeat | `com.apple.AOSHeartbeat` | Retained |
| AOSPushRelay | `com.apple.AOSPushRelay` | Retained |
| AOSUIPrefPaneLauncher | `com.apple.AOSUIPrefPaneLauncher` | Excluded |
| App Store | `com.apple.AppStore` | Excluded |
| Apple Diagnostics | `com.apple.DiagnosticsModeAssistant` | Excluded |
| AppleMobileDeviceHelper | `com.apple.SyncServices.AppleMobileDeviceHelper` | Retained |
| AppleMobileSync | `com.apple.SyncServices.AppleMobileSync` | Retained |
| AppleScript Utility | `com.apple.AppleScriptUtility` | Retained |
| Apps | `com.apple.apps.launcher` | Excluded |
| AppSSOAgent | `com.apple.AppSSOAgent` | Excluded |
| AquaAppearanceHelper | `com.apple.AquaAppearanceHelper` | Retained |
| Archive Utility | `com.apple.archiveutility` | Excluded |
| ARDAgent | `com.apple.RemoteDesktopAgent` | Retained |
| AskPermissionUI | `com.apple.AskPermissionUI` | Excluded |
| Assistive Control | `com.apple.inputmethod.AssistiveControl` | Retained |
| Audio MIDI Setup | `com.apple.audio.AudioMIDISetup` | Excluded |
| AuthKitUIMacService | `com.apple.authkit.AuthKitHeadlessUIHelper` | Excluded |
| AuthorizationPromptService | `com.apple.tcc.AuthorizationPromptService` | Excluded |
| AutoFillPanelService | `com.apple.AutoFillPanelService` | Excluded |
| AutomationModeUI | `com.apple.dt.AutomationModeUI` | Retained |
| Automator Application Stub | `com.apple.Automator.Automator-Application-Stub` | Retained |
| Automator Installer | `com.apple.AutomatorInstaller` | Excluded |
| Automator | `com.apple.Automator` | Retained |
| AVB Configuration | `com.apple.AVB-Audio-Configuration` | Excluded |
| AXVisualSupportAgent | `com.apple.accessibility.AXVisualSupportAgent` | Retained |
| BackgroundTaskManagementAgent | `com.apple.backgroundtaskmanagement.agent` | Excluded |
| Batteries | `com.apple.Batteries` | Excluded |
| Bluetooth File Exchange | `com.apple.BluetoothFileExchange` | Excluded |
| BluetoothSetupAssistant | `com.apple.BluetoothSetupAssistant` | Excluded |
| BluetoothUIServer | `com.apple.BluetoothUIServer` | Excluded |
| BluetoothUIService | `com.apple.BluetoothUIService` | Excluded |
| Books | `com.apple.iBooksX` | Retained |
| Build Web Page | `com.apple.BuildWebPage` | Retained |
| Calculator | `com.apple.calculator` | Excluded |
| Calendar | `com.apple.iCal` | Retained |
| CalendarFileHandler | `com.apple.CalendarFileHandler` | Retained |
| Calibration Assistant | `com.apple.Calibration-Assistant` | Excluded |
| Captive Network Assistant | `com.apple.CaptiveNetworkAssistant` | Excluded |
| Certificate Assistant | `com.apple.CertificateAssistant` | Excluded |
| CharacterPalette | `com.apple.CharacterPaletteIM` | Retained |
| Chess | `com.apple.Chess` | Excluded |
| ChineseTextConverterService | `com.apple.ChineseTextConverterService` | Retained |
| CIMFindInputCodeTool | `com.apple.CCE.CIMFindInputCode` | Retained |
| CinematicFramingOnboardingUI | `com.apple.CMViewSrvc` | Retained |
| ClassroomAppLockHelper | `com.apple.classroom.AppLockHelper` | Retained |
| ClassroomStudentMenuExtra | `com.apple.ClassroomStudentMenuExtra` | Retained |
| Clock | `com.apple.clock` | Excluded |
| ClockAngel | `com.apple.ClockAngel` | Excluded |
| Cocoa-AppleScript Applet | `com.apple.ScriptEditor.id.cocoa-applet-template` | Retained |
| ColorSync Utility | `com.apple.ColorSyncUtility` | Excluded |
| Computer | `com.apple.finder.Open-Computer` | Excluded |
| Conflict Resolver | `com.apple.syncservices.ConflictResolver` | Retained |
| Console | `com.apple.Console` | Excluded |
| Contacts | `com.apple.AddressBook` | Retained |
| ContinuityCaptureOnboardingUI | `com.apple.ContinuityCaptureOnboardingUI` | Retained |
| ControlCenter | `com.apple.controlcenter` | Excluded |
| ControlStrip | `com.apple.controlstrip` | Retained |
| CoreLocationAgent | `com.apple.CoreLocationAgent` | Excluded |
| CoreServicesUIAgent | `com.apple.coreservices.uiagent` | Excluded |
| Coverage Details | `com.apple.NewDeviceOutreachApp` | Excluded |
| ctkbind | `com.apple.ctkbind` | Retained |
| Database Events | `com.apple.databaseevents` | Retained |
| Desk View | `com.apple.DeskCam` | Excluded |
| DFRHUD | `com.apple.accessibility.DFRHUD` | Retained |
| Diagnostics Reporter | `com.apple.DiagnosticsReporter` | Excluded |
| DictationIM | `com.apple.inputmethod.ironwood` | Retained |
| Dictionary | `com.apple.Dictionary` | Excluded |
| Digital Color Meter | `com.apple.DigitalColorMeter` | Excluded |
| Directory Utility | `com.apple.DirectoryUtility` | Excluded |
| DiscHelper | `com.apple.DiscHelper` | Excluded |
| Disk Utility | `com.apple.DiskUtility` | Excluded |
| DiskImageMounter | `com.apple.DiskImageMounter` | Excluded |
| DiskImages UI Agent | `com.apple.frameworks.diskimages.diuiagent` | Excluded |
| Display Calibrator | `com.apple.ColorSyncCalibrator` | Excluded |
| Dock | `com.apple.dock` | Excluded |
| Droplet with Settable Properties | `com.apple.ScriptEditor.id.droplet-with-settable-properties-template` | Retained |
| DVD Player | `com.apple.DVDPlayer` | Excluded |
| Dwell Control | `com.apple.DwellControl` | Retained |
| eaptlstrust | `com.apple.eap8021x.eaptlstrust` | Excluded |
| EmojiFunctionRowIM | `com.apple.EmojiFunctionRowItem-Container` | Retained |
| Enhanced Logging | `com.apple.EnhancedLogging` | Excluded |
| Erase Assistant | `com.apple.EraseAssistant` | Excluded |
| EscrowSecurityAlert | `com.apple.EscrowSecurityAlert` | Excluded |
| Expansion Slot Utility | `com.apple.ExpansionSlotUtility` | Excluded |
| FaceTime | `com.apple.FaceTime` | Retained |
| Family | `com.apple.Family` | Retained |
| FamilyExtensionHost | `com.apple.FamilyExtensionHost` | Retained |
| Feedback Assistant | `com.apple.appleseed.FeedbackAssistant` | Retained |
| FeedbackRemoteView | `com.apple.FeedbackRemoteView` | Retained |
| FileProvider-Feedback | `com.apple.FileProvider-Feedback` | Retained |
| FileSystemUIAgent | `com.apple.FileSystemUIAgent` | Excluded |
| Finder | `com.apple.finder` | Excluded |
| FindMy | `com.apple.findmy` | Excluded |
| FindMyMacMessenger | `com.apple.FindMyMacMessenger` | Retained |
| Folder Actions Setup | `com.apple.FolderActionsSetup` | Excluded |
| FolderActionsDispatcher | `com.apple.FolderActionsDispatcher` | Retained |
| FollowUpUI | `com.apple.FollowUpUI` | Retained |
| Font Book | `com.apple.FontBook` | Excluded |
| FontRegistryUIAgent | `com.apple.FontRegistryUIAgent` | Excluded |
| Freeform | `com.apple.freeform` | Retained |
| Game Center | `com.apple.gamecenter` | Retained |
| GameOverlayUI | `com.apple.GameOverlayUI` | Retained |
| Games | `com.apple.games` | Excluded |
| GameTrampoline | `com.apple.GameTrampoline` | Retained |
| Grapher | `com.apple.grapher` | Retained |
| HanjaTool | `com.apple.inputmethod.Korean.HanjaTool` | Retained |
| Home | `com.apple.Home` | Retained |
| iCloud Drive | `com.apple.finder.Open-iCloudDrive` | Excluded |
| iCloud Drive | `com.apple.bird` | Retained |
| iCloud+ | `com.apple.icq` | Retained |
| iCloud | `com.apple.CloudKit.ShareBear` | Retained |
| iCloudUserNotificationsd | `com.apple.iCloudUserNotificationsd` | Retained |
| identityservicesd | `com.apple.identityservicesd` | Retained |
| IDSRemoteURLConnectionAgent | `com.apple.idsfoundation.IDSRemoteURLConnectionAgent` | Retained |
| Image Capture | `com.apple.Image_Capture` | Excluded |
| Image Events | `com.apple.imageevents` | Retained |
| Image Playground | `com.apple.GenerativePlaygroundApp` | Retained |
| imagent | `com.apple.imagent` | Retained |
| IMAutomaticHistoryDeletionAgent | `com.apple.IMAutomaticHistoryDeletionAgent` | Retained |
| IMTransferAgent | `com.apple.imtransferservices.IMTransferAgent` | Retained |
| Install Command Line Developer Tools | `com.apple.dt.CommandLineTools.installondemand` | Excluded |
| Install in Progress | `com.apple.PackageUIKit.Install-in-Progress` | Excluded |
| Installer Progress | `com.apple.Installer-Progress` | Excluded |
| Installer | `com.apple.installer` | Excluded |
| iOS App Installer | `com.apple.IPAInstaller` | Excluded |
| IOUIAgent | `com.apple.IOUIAgent` | Excluded |
| iPhone Mirroring | `com.apple.ScreenContinuity` | Excluded |
| JapaneseIM-KanaTyping | `com.apple.JapaneseIM.KanaTyping` | Retained |
| JapaneseIM-RomajiTyping | `com.apple.JapaneseIM.RomajiTyping` | Retained |
| JavaLauncher | `com.apple.JavaLauncher` | Retained |
| Journal | `com.apple.journal` | Retained |
| KerberosMenuExtra | `com.apple.KerberosMenuExtra` | Excluded |
| KeyboardAccessAgent | `com.apple.KeyboardAccessAgent` | Retained |
| KeyboardSetupAssistant | `com.apple.KeyboardSetupAssistant` | Excluded |
| Keychain Access | `com.apple.keychainaccess` | Excluded |
| Keychain Circle Notification | `com.apple.security.Keychain-Circle-Notification` | Excluded |
| KoreanIM | `com.apple.KIM-Container` | Retained |
| Language Chooser | `com.apple.Language-Chooser` | Excluded |
| LaunchPolicyAlertAgent | `com.apple.devicemanagementclient.alertagent` | Excluded |
| LinkedNotesUIService | `com.apple.LinkedNotesUIService` | Retained |
| Live Captions | `com.apple.accessibility.LiveTranscriptionAgent` | Retained |
| Live Speech | `com.apple.accessibility.LiveSpeech` | Retained |
| LockScreen | `com.apple.LockScreen` | Excluded |
| loginwindow | `com.apple.loginwindow` | Excluded |
| Magnifier | `com.apple.Magnifier` | Excluded |
| Mail | `com.apple.mail` | Retained |
| MakePDF | `com.apple.MakePDF` | Retained |
| ManagedClient | `com.apple.ManagedClient` | Excluded |
| Maps | `com.apple.Maps` | Retained |
| mbproximityhelper | `com.apple.mbproximityhelper` | Retained |
| MCXDiskAuthorization | `com.apple.mcx.MCXDiskAuthorization` | Excluded |
| MDMMigrationTrampoline | `com.apple.MDMMigrationTrampoline` | Excluded |
| MediaRemoteUI | `com.apple.MediaRemoteUI` | Retained |
| MediaRemoteUIService | `com.apple.MediaRemoteUIService` | Retained |
| Medical Imaging Calibrator | `com.apple.MedicalImagingCalibrator` | Excluded |
| Memory Slot Utility | `com.apple.MemorySlotUtility` | Excluded |
| MenuBarAgent | `com.apple.MenuBarAgent` | Excluded |
| Messages | `com.apple.MobileSMS` | Retained |
| Migration Assistant | `com.apple.MigrateAssistant` | Excluded |
| MiniTerm | `com.apple.pppminiterm` | Retained |
| MirrorDisplays | `com.apple.preference.displays.MirrorDisplays` | Excluded |
| Mission Control | `com.apple.exposelauncher` | Excluded |
| MobileDeviceUpdater | `com.apple.MobileDeviceUpdater` | Excluded |
| MRT | `com.apple.MRT` | Excluded |
| MTLReplayer | `com.apple.MTLReplayer` | Retained |
| Music | `com.apple.Music` | Retained |
| MusicRecognitionMac | `com.apple.musicrecognition.mac` | Retained |
| NetAuthAgent | `com.apple.NetAuthAgent` | Excluded |
| Network | `com.apple.finder.Open-Network` | Excluded |
| News | `com.apple.news` | Retained |
| Notes | `com.apple.Notes` | Retained |
| NotificationCenter | `com.apple.notificationcenterui` | Excluded |
| NowPlayingTouchUI | `com.apple.NowPlayingTouchUI` | Excluded |
| OBEXAgent | `com.apple.OBEXAgent` | Excluded |
| OSDUIHelper | `com.apple.OSDUIHelper` | Excluded |
| Paired Devices | `com.apple.PairedDevices` | Excluded |
| Panel Editor | `com.apple.AssistiveControl.editor` | Retained |
| ParentalControls | `com.apple.familycontrols.useragent` | Excluded |
| Pass Viewer | `com.apple.Pass-Viewer` | Excluded |
| PassViewer | `com.apple.PassViewer` | Excluded |
| Passwords | `com.apple.Passwords` | Excluded |
| PasswordsMenuBarExtra | `com.apple.Passwords.MenuBarExtra` | Excluded |
| PeopleMessageService | `com.apple.PeopleMessageService` | Excluded |
| PeopleViewService | `com.apple.PeopleViewService` | Retained |
| Phone | `com.apple.mobilephone` | Retained |
| Photo Booth | `com.apple.PhotoBooth` | Excluded |
| Photos | `com.apple.Photos` | Retained |
| PIPAgent | `com.apple.PIPAgent` | Excluded |
| PlatformSSOUIAgent | `com.apple.PlatformSSO.PlatformSSOUIAgent` | Excluded |
| PluginIM | `com.apple.inputmethod.PluginIM` | Retained |
| Podcasts | `com.apple.podcasts` | Retained |
| PowerChime | `com.apple.PowerChime` | Excluded |
| PressAndHold | `com.apple.PAH-Container` | Retained |
| Preview | `com.apple.Preview` | Retained |
| PreviewShell | `com.apple.PreviewShell` | Retained |
| PreviewShellMac | `com.apple.PreviewShellMac` | Retained |
| Print Center | `com.apple.printcenter` | Excluded |
| privatecloudcomputed | `com.apple.privatecloudcomputed` | Retained |
| Pro Display Calibrator | `com.apple.displaycalibrator` | Retained |
| Problem Reporter | `com.apple.ProblemReporter` | Retained |
| ProfileHelper | `com.apple.mcx.ProfileHelper` | Excluded |
| qlmanage | `com.apple.quicklook.qlmanage` | Retained |
| Quick Look Simulator | `com.apple.quicklook.QuickLookSimulator` | Retained |
| quicklookd | `com.apple.QuickLookDaemon` | Retained |
| QuickLookUIHelper | `com.apple.quicklook.ui.helper` | Retained |
| QuickTime Player | `com.apple.QuickTimePlayerX` | Retained |
| RapportUIAgent | `com.apple.RapportUIAgent` | Excluded |
| rcd | `com.apple.rcd` | Retained |
| Recents | `com.apple.finder.Open-Recents` | Excluded |
| Recursive File Processing Droplet | `com.apple.ScriptEditor.id.file-processing-droplet-template` | Retained |
| Recursive Image File Processing Droplet | `com.apple.ScriptEditor.id.image-file-processing-droplet-template` | Retained |
| RegisterPluginIMApp | `com.apple.pluginIM.pluginIMRegistrator` | Retained |
| Reminders | `com.apple.reminders` | Retained |
| Remote Desktop Message | `com.apple.RemoteDesktopMessageAgent` | Retained |
| Rosetta 2 Updater | `com.apple.OAHSoftwareUpdateApp` | Excluded |
| Safari | `com.apple.Safari` | Retained |
| SCIM | `com.apple.SCIM-Container` | Retained |
| Screen Sharing | `com.apple.ScreenSharing` | Excluded |
| Screen Time | `com.apple.ScreenTimeWidgetApplication` | Excluded |
| screencaptureui | `com.apple.screencaptureui` | Excluded |
| ScreenReaderUIServer | `com.apple.ScreenReaderUIServer` | Retained |
| ScreenSaverEngine | `com.apple.ScreenSaver.Engine` | Excluded |
| Screenshot | `com.apple.screenshot.launcher` | Excluded |
| Script Editor | `com.apple.ScriptEditor2` | Retained |
| Script Menu | `com.apple.ScriptMenuApp` | Retained |
| ScriptMonitor | `com.apple.ScriptMonitor` | Retained |
| SettingsPlaceholder | `com.apple.Settings` | Excluded |
| Setup Assistant | `com.apple.SetupAssistant` | Excluded |
| Share Screen Request | `com.apple.VNCGuestRequest` | Excluded |
| Shared Screen Viewer | `com.apple.ARDForcedViewer` | Retained |
| ShortcutDroplet | `com.apple.shortcuts.droplet` | Retained |
| Shortcuts Events | `com.apple.shortcuts.events` | Retained |
| Shortcuts | `com.apple.shortcuts` | Retained |
| ShortcutsActions | `com.apple.ShortcutsActions` | Retained |
| Siri AI | `com.apple.campo` | Retained |
| Siri | `com.apple.siri.launcher` | Retained |
| Siri | `com.apple.Siri` | Retained |
| sociallayerd | `com.apple.sociallayerd` | Retained |
| Software Update | `com.apple.SoftwareUpdate` | Excluded |
| SoftwareUpdateLauncher | `com.apple.SoftwareUpdateLauncher` | Excluded |
| SoftwareUpdateNotificationManager | `com.apple.SoftwareUpdateNotificationManager` | Excluded |
| SpacesTouchBarAgent | `com.apple.SpacesTouchBarAgent` | Excluded |
| SpeechDataInstallerd | `com.apple.speech.SpeechDataInstallerd` | Retained |
| SpeechRecognitionServer | `com.apple.speech.SpeechRecognitionServer` | Retained |
| Spotlight | `com.apple.Spotlight` | Excluded |
| SSAssistanceCursor | `com.apple.SSAssistanceCursor` | Retained |
| SSDragHelper | `com.apple.VNCDragHelper` | Retained |
| SSInvitationAgent | `com.apple.ssinvitationagent` | Retained |
| SSMenuAgent | `com.apple.SSMenuAgent` | Retained |
| StageManagerOnboarding | `com.apple.windowmanager.StageManagerOnboarding` | Excluded |
| Stickies | `com.apple.Stickies` | Retained |
| STMUIHelper | `com.apple.STMFramework.UIHelper` | Retained |
| Stocks | `com.apple.stocks` | Excluded |
| storeuid | `com.apple.storeuid` | Retained |
| Summary Service | `com.apple.SummaryService` | Retained |
| SyncServer | `com.apple.syncserver` | Retained |
| syncuid | `com.apple.syncservices.syncuid` | Retained |
| System Events | `com.apple.systemevents` | Retained |
| System Information | `com.apple.SystemProfiler` | Excluded |
| System Settings | `com.apple.systempreferences` | Excluded |
| System Speech | `com.apple.speech.synthesis.SpeechSynthesisServer` | Retained |
| SystemIntents | `com.apple.SystemIntents` | Retained |
| SystemUIServer | `com.apple.systemuiserver` | Excluded |
| TamilIM | `com.apple.inputmethod.Tamil` | Retained |
| TCIM | `com.apple.TCIM-Container` | Retained |
| Terminal | `com.apple.Terminal` | Paused |
| TextEdit | `com.apple.TextEdit` | Retained |
| TextInputMenuAgent | `com.apple.TextInputMenuAgent` | Excluded |
| TextInputSwitcher | `com.apple.TextInputSwitcher` | Excluded |
| ThermalTrap | `com.apple.ThermalTrap` | Excluded |
| Ticket Viewer | `com.apple.Ticket-Viewer` | Excluded |
| Time Machine | `com.apple.backup.launcher` | Excluded |
| Tips | `com.apple.helpviewer` | Excluded |
| TipsSpotlightHandler | `com.apple.tips` | Excluded |
| TMHelperAgent | `com.apple.timemachine.HelperAgent` | Excluded |
| TrackpadIM | `com.apple.TrackpadIM-Container` | Retained |
| TransliterationIM | `com.apple.TransliterationIM-Container` | Retained |
| TV | `com.apple.TV` | Retained |
| TYIM | `com.apple.TYIM-Container` | Retained |
| UASharedPasteboardProgressUI | `com.apple.coreservices.UASharedPasteboardProgressUI` | Excluded |
| UIKitSystem | `com.apple.UIKitSystemApp` | Retained |
| universalAccessAuthWarn | `com.apple.accessibility.universalAccessAuthWarn` | Retained |
| UniversalAccessControl | `com.apple.UniversalAccessControl` | Excluded |
| UniversalControl | `com.apple.universalcontrol` | Retained |
| UnmountAssistantAgent | `com.apple.UnmountAssistantAgent` | Excluded |
| UserNotificationCenter | `com.apple.UserNotificationCenter` | Excluded |
| VietnameseIM | `com.apple.VIM-Container` | Retained |
| Virtual Machine Accessories | `com.apple.accessoryaccess.uiagent` | Retained |
| VoiceMemos | `com.apple.VoiceMemos` | Retained |
| VoiceOver Quickstart | `com.apple.VoiceOverQuickstart` | Excluded |
| VoiceOver Utility | `com.apple.VoiceOverUtility` | Excluded |
| VoiceOver | `com.apple.VoiceOver` | Retained |
| VoiceOverUtilityCacheBuilder | `com.apple.VoiceOverUtilityCacheBuilder` | Excluded |
| WallpaperAgent | `com.apple.wallpaper.agent` | Retained |
| WatchFaceAlert | `com.apple.WatchFaceAlert` | Excluded |
| Weather | `com.apple.weather` | Excluded |
| WeatherMenu | `com.apple.weather.menu` | Excluded |
| webdav_cert_ui | `com.apple.WebDAVFS.webdav-cert-ui` | Excluded |
| WidgetKit Simulator | `com.apple.widgetkit.simulator` | Retained |
| WidgetRenderer_Activities | `com.apple.chrono.WidgetRenderer-Activities` | Retained |
| WiFiAgent | `com.apple.wifi.WiFiAgent` | Excluded |
| WindowManager | `com.apple.WindowManager` | Excluded |
| Wireless Diagnostics | `com.apple.wifi.diagnostics` | Excluded |
| Wish | `com.tcltk.wish` | Retained |
| WorkoutAlert-Mac | `com.apple.WorkoutAlert-Mac` | Excluded |
| XProtect | `com.apple.XProtectFramework.XProtect` | Excluded |

</details>
