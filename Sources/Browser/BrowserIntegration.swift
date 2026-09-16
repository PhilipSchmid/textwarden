import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class BrowserIntegration: ObservableObject {
    static let shared = BrowserIntegration()
    @Published private(set) var connectedBrowsers: Set<String> = []
    var isConnected: Bool {
        !connectedBrowsers.isEmpty
    }

    @Published private(set) var isListening = false
    private var listener: DispatchSourceRead?
    private var safariListener: DispatchSourceRead?
    private var connections: [UUID: BrowserConnection] = [:]
    private var snapshots: [String: BrowserMessage] = [:]
    private var owners: [String: UUID] = [:]
    private var styleResults: [String: [StyleSuggestionModel]] = [:]
    private var styleLoadingSession: String?
    private var results: [String: [GrammarErrorModel]] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var revisions: [String: Int] = [:]
    private var shownSession: String?
    private var activeSession: String?
    private var observers: Set<AnyCancellable> = []
    private var pendingApply: (session: String, revision: Int, expected: String, continuation: CheckedContinuation<Void, Never>)?
    private var applyTimeout: Task<Void, Never>?
    private var toolTarget: BrowserMessage?
    private var toolTask: Task<Void, Never>?
    private var toolID: UUID?
    private lazy var readability: ReadabilityPopover = {
        let view = ReadabilityPopover()
        view.onHide = { [weak self] in
            if self?.toolTarget?.kind == "readability" { self?.cancelTool() }
        }
        return view
    }()

    private lazy var compose: TextGenerationPopover = {
        let view = TextGenerationPopover()
        view.onGenerate = { instruction, style, context, seed in
            guard #available(macOS 26.0, *) else {
                throw FoundationModelsError.analysisError("AI Compose requires macOS 26 or later")
            }
            let engine = FoundationModelsEngine()
            engine.checkAvailability()
            guard engine.status.isAvailable else { throw FoundationModelsError.notAvailable(engine.status) }
            return try await engine.generateText(instruction: instruction, context: context, style: style, variationSeed: seed)
        }
        view.onInsertText = { [weak self] text in
            guard let self, let target = toolTarget else { return }
            let id = toolID
            toolTask = Task {
                defer { if self.toolID == id { self.cancelTool() } }
                await self.replaceSelection(text, target: target)
            }
        }
        view.onHide = { [weak self] in
            guard let self, toolTarget?.kind == "compose", toolTask == nil else { return }
            cancelTool()
        }
        return view
    }()

    private lazy var popover: SuggestionPopover = {
        let view = SuggestionPopover()
        view.onApplySuggestion = { [weak self] error, replacement in await self?.apply(error, replacement: replacement) }
        view.onIgnoreRule = { [weak self] rule in
            UserPreferences.shared.ignoreRule(rule)
            self?.refreshShownSession()
        }
        view.onAddToDictionary = { [weak self] error in
            guard let self, let session = shownSession, let text = snapshots[session]?.text,
                  let range = TextIndexConverter.scalarRangeToUTF16CFRange(start: error.start, end: error.end, in: text)
            else { return }
            UserPreferences.shared.addToCustomDictionary((text as NSString).substring(with: NSRange(location: range.location, length: range.length)))
            refreshShownSession()
        }
        view.onDismissError = { [weak self, weak view] error in
            guard let self, let session = shownSession else { return }
            results[session]?.removeAll { $0 === error }
            sendResults(session)
            view?.hide()
        }
        view.onAcceptStyleSuggestion = { [weak self] suggestion in
            Task { await self?.applyStyle(suggestion) }
        }
        view.onRejectStyleSuggestion = { [weak self] suggestion, _ in
            guard let self, let session = shownSession else { return }
            styleResults[session]?.removeAll { $0.id == suggestion.id }
            sendResults(session)
        }
        view.onGetValidSuggestions = { [weak self] in
            guard let self, let session = shownSession else { return [] }
            return styleResults[session] ?? []
        }
        view.onRegenerateStyleSuggestion = { [weak self] suggestion in
            await self?.regenerateStyle(suggestion)
        }
        return view
    }()

    func start() {
        guard listener == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        do {
            try BrowserSetup.register()
            listener = try listen(in: BrowserWire.directory)
            isListening = true
            if let directory = BrowserWire.safariDirectory {
                do {
                    safariListener = try listen(in: directory)
                } catch {
                    Logger.error("Could not start Safari browser connection", category: Logger.lifecycle)
                }
            }
            UserPreferences.shared.objectWillChange
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] in
                    guard let self else { return }
                    cancelTool(); styleResults.removeAll(); popover.hide()
                    for connection in connections.values {
                        connection.send(BrowserMessage(kind: "status", action: "policyChanged"))
                    }
                    for session in snapshots.keys {
                        analyze(session)
                    }
                }.store(in: &observers)
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          ![browserID(for: activeSession ?? toolTarget?.session), Bundle.main.bundleIdentifier].contains(app.bundleIdentifier)
                    else { return }
                    cancelTool(); popover.hide()
                }.store(in: &observers)
            Logger.info("Browser connection available", category: Logger.lifecycle)
        } catch {
            Logger.error("Could not start browser connection", category: Logger.lifecycle)
        }
    }

    private func listen(in directory: URL) throws -> DispatchSourceRead {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
        else { throw BrowserWireError.invalidMessage }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("bridge.sock").path
        if FileManager.default.fileExists(atPath: path) {
            let old = try FileManager.default.attributesOfItem(atPath: path)
            guard old[.type] as? FileAttributeType == .typeSocket else { throw BrowserWireError.invalidMessage }
            try FileManager.default.removeItem(atPath: path)
        }
        var address = try BrowserSocket.address(path: path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BrowserWireError.disconnected }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(descriptor, 16) == 0 else {
            Darwin.close(descriptor)
            throw BrowserWireError.disconnected
        }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptConnection(descriptor)
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }

    func stop() {
        finishApply(success: false)
        observers.removeAll()
        cancelTool()
        popover.hide(); shownSession = nil
        listener?.cancel(); listener = nil
        safariListener?.cancel(); safariListener = nil
        isListening = false
        connectedBrowsers.removeAll()
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll(); snapshots.removeAll(); owners.removeAll(); results.removeAll(); styleResults.removeAll(); revisions.removeAll()
        setActiveSession(nil)
    }

    private func browserID(for session: String?) -> String {
        guard let session, let owner = owners[session] else { return "" }
        return connections[owner]?.browserBundleID ?? ""
    }

    private func isBrowserFrontmost(_ session: String?) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browserID(for: session)
    }

    var hasActiveEditor: Bool {
        (activeSession != nil || toolTarget != nil) && isBrowserFrontmost(activeSession ?? toolTarget?.session)
    }

    func requestTool(_ action: String) -> Bool {
        guard hasActiveEditor, let session = activeSession ?? toolTarget?.session,
              let owner = owners[session], let connection = connections[owner]
        else { return false }
        if ["grammar", "style"].contains(action), popover.isVisible { popover.hide(); return true }
        if action == "compose", compose.isVisible { cancelTool(); return true }
        if action == "rewrite", toolTask != nil { cancelTool(); return true }
        if action == "readability", readability.isVisible { cancelTool(); return true }
        connection.send(BrowserMessage(kind: "request", session: session, action: action))
        return true
    }

    private func setActiveSession(_ session: String?) {
        guard activeSession != session else { return }
        activeSession = session
        AnalysisCoordinator.shared.browserFocusChanged()
    }

    private func acceptConnection(_ descriptor: Int32) {
        let peer = accept(descriptor, nil, nil)
        guard peer >= 0 else { return }
        guard connections.count < 16, BrowserSocket.sameUser(peer) else { Darwin.close(peer); return }
        let connection = BrowserConnection(descriptor: peer)
        connections[connection.id] = connection
        let id = connection.id
        connection.readMessages(onMessage: { [self] message in
            Task { @MainActor in receive(message, from: id) }
        }, onClose: { [self] in
            Task { @MainActor in disconnect(id) }
        })
    }

    private func disconnect(_ id: UUID) {
        connections.removeValue(forKey: id)
        connectedBrowsers = Set(connections.values.compactMap(\.browserBundleID))
        for session in owners.filter({ $0.value == id }).map(\.key) {
            release(session)
        }
    }

    private func release(_ session: String) {
        if pendingApply?.session == session { finishApply(success: false) }
        if toolTarget?.session == session { cancelTool() }
        tasks.removeValue(forKey: session)?.cancel()
        styleResults.removeValue(forKey: session)
        snapshots.removeValue(forKey: session); results.removeValue(forKey: session); owners.removeValue(forKey: session)
        revisions.removeValue(forKey: session)
        if activeSession == session { setActiveSession(nil) }
        if shownSession == session { popover.hide(); shownSession = nil }
    }

    private func receive(_ message: BrowserMessage, from connection: UUID) {
        guard let client = connections[connection], let browser = message.browserBundleID,
              client.browserBundleID == nil || client.browserBundleID == browser
        else { return }
        client.browserBundleID = browser
        connectedBrowsers.insert(browser)
        if message.kind == "configuration" {
            configure(message, from: connection)
            return
        }
        guard let session = message.session,
              connections[connection] != nil,
              owners[session] == nil || owners[session] == connection
        else { return }
        switch message.kind {
        case "pausePage":
            guard owners.count < 16 || owners[session] != nil else { return }
            owners[session] = connection
            if isBrowserFrontmost(session) { setActiveSession(session) }
        case "snapshot", "compose", "rewrite", "readability":
            guard owners.count < 16 || owners[session] != nil,
                  let revision = message.revision, revision >= (revisions[session] ?? -1)
            else { return }
            owners[session] = connection
            if isBrowserFrontmost(session) { setActiveSession(session) }
            revisions[session] = revision
            if snapshots[session]?.text != message.text || snapshots[session]?.revision != revision {
                styleResults.removeValue(forKey: session)
                if toolTarget?.session == session { cancelTool() }
            }
            snapshots[session] = message
            if message.kind == "snapshot" {
                analyze(session)
            } else {
                openTool(message)
            }
        case "invalidate":
            if pendingApply?.session == session { finishApply(success: false) }
            guard owners.count < 16 || owners[session] != nil,
                  let revision = message.revision, revision >= (revisions[session] ?? -1)
            else { return }
            owners[session] = connection
            if isBrowserFrontmost(session) { setActiveSession(session) }
            if toolTarget?.session == session { cancelTool() }
            revisions[session] = revision
            tasks.removeValue(forKey: session)?.cancel()
            snapshots.removeValue(forKey: session); results.removeValue(forKey: session); styleResults.removeValue(forKey: session)
            if shownSession == session { popover.hide(); shownSession = nil }
        case "applied":
            guard let previous = snapshots[session], let revision = message.revision,
                  message.status == "ok", let text = message.text,
                  revision == (previous.revision ?? -1) + 1
            else {
                if pendingApply?.session == session { finishApply(success: false) }
                return
            }
            if let pending = pendingApply, pending.session == session,
               pending.expected != text || pending.revision + 1 != revision
            {
                finishApply(success: false); return
            }
            styleResults.removeValue(forKey: session)
            snapshots[session] = BrowserMessage(kind: "snapshot", session: session, revision: revision,
                                                origin: previous.origin, pageURL: previous.pageURL, text: text)
            revisions[session] = revision
            analyze(session)
        case "release": release(session)
        case "focus":
            if owners[session] != nil, isBrowserFrontmost(session) { setActiveSession(session) }
        case "blur":
            if activeSession == session, !popover.isVisible, pendingApply == nil, toolTarget == nil { setActiveSession(nil) }
        case "selection":
            if let target = toolTarget, target.isInvalidated(bySelection: message) {
                cancelTool()
            }
        case "hoverEnd": if shownSession == session, pendingApply == nil { popover.scheduleHide() }
        case "hoverKeep": if shownSession == session { popover.cancelHide() }
        case "show":
            if message.action == "style" || message.action == "styleHover" {
                guard let snapshot = snapshots[session], snapshot.revision == message.revision,
                      pendingApply == nil,
                      message.action != "styleHover" || UserPreferences.shared.enableHoverPopover
                else { return }
                openStyle(snapshot, indicator: message.indicator)
                return
            }
            guard let snapshot = snapshots[session], snapshot.revision == message.revision,
                  let errors = results[session], let index = message.errorID, errors.indices.contains(index)
            else {
                connections[connection]?.send(BrowserMessage(kind: "status", session: session, status: "The text changed. Wait for updated suggestions."))
                return
            }
            guard isBrowserFrontmost(session) else {
                connections[connection]?.send(BrowserMessage(kind: "status", session: session, status: "Return to your browser to open this suggestion."))
                return
            }
            if pendingApply != nil { return }
            let fromIndicator = message.action == "indicator" || message.action == "indicatorHover"
            if message.action == "hover" || message.action == "indicatorHover" {
                guard UserPreferences.shared.enableHoverPopover else { return }
                if shownSession == session, popover.isVisible, popover.openedFromIndicator == fromIndicator, popover.currentStyleSuggestion == nil,
                   fromIndicator || popover.currentError === errors[index]
                {
                    popover.cancelHide(); return
                }
            }
            cancelTool()
            shownSession = session
            if fromIndicator {
                guard let placement = indicatorPlacement(message.indicator, session: session) else { return }
                popover.showUnified(errors: errors, styleSuggestions: [], at: placement.point, openDirection: placement.direction,
                                    constrainToWindow: placement.viewport, sourceText: snapshot.text ?? "")
            } else {
                popover.show(error: errors[index], allErrors: errors, at: NSEvent.mouseLocation, sourceText: snapshot.text ?? "")
            }
            if !popover.isVisible {
                connections[connection]?.send(BrowserMessage(kind: "status", session: session, status: "Close the open dialog, then try this suggestion again."))
            }
        default: break
        }
    }

    private func configure(_ message: BrowserMessage, from id: UUID) {
        guard let connection = connections[id], let session = message.session, let browser = connection.browserBundleID else { return }
        let preferences = UserPreferences.shared
        let url = (message.pageURL ?? message.origin).flatMap(URL.init(string:))
        // Only the extension popup sends configuration; background editor ports reject this kind.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser {
            switch message.action {
            case "pauseSite":
                if let url, let key = UserPreferences.siteKey(url) { preferences.disableWebsite(key, duration: message.pause.flatMap(PauseDuration.init(rawValue:)) ?? .indefinite) }
            case "resumeSite":
                if let url, let key = UserPreferences.siteKey(url) { preferences.enableWebsite(key) }
            case "pausePageRule":
                if let url, let key = UserPreferences.pageKey(url) { preferences.disableWebsite(key) }
            case "resumePage":
                if let url, let key = UserPreferences.pageKey(url) { preferences.enableWebsite(key) }
            case "pauseBrowser": preferences.setPauseDuration(for: browser, duration: .indefinite)
            case "resumeBrowser": preferences.setPauseDuration(for: browser, duration: .active)
            case "browserPause", "globalPause":
                if let value = message.pause, let duration = PauseDuration(rawValue: value) {
                    preferences.setPauseDuration(duration, for: message.action == "browserPause" ? .application(browser) : .global)
                }
            case "settings", "websites":
                PreferencesWindowController.shared.selectTab(message.action == "websites" ? .websites : .browser)
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow(selectedTab:)), to: nil, from: self)
            default: break
            }
        }
        let siteURL = url.flatMap { UserPreferences.siteKey($0) }.flatMap(URL.init(string:))
        let siteEnabled = siteURL.map { candidate in
            !preferences.disabledWebsites.contains { rule in
                guard preferences.isWebsiteDisabled(rule) else { return false }
                if rule.contains("://"), URLComponents(string: rule)?.path.isEmpty != true { return false }
                return UserPreferences.websiteRuleMatches(rule, url: candidate)
            }
        } ?? true
        let pageEnabled = url.map { preferences.isEnabled(forURL: $0) } ?? true
        let inherited = !siteEnabled && !(siteURL.map { preferences.isWebsiteDisabled($0.absoluteString) } ?? false)
        connection.send(BrowserMessage(kind: "configuration", session: session, origin: message.origin, pageURL: message.pageURL, pageEnabled: pageEnabled, action: "status",
                                       siteEnabled: siteEnabled, sitePausedUntil: siteURL.flatMap { UserPreferences.siteKey($0) }.flatMap { preferences.websitePausedUntil[$0]?.timeIntervalSince1970 }, siteInherited: inherited,
                                       appPaused: preferences.getPauseDuration(for: browser) != .active,
                                       globalPaused: !preferences.isEnabled, theme: preferences.appTheme,
                                       appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                       appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                                       browserPause: preferences.getPauseDuration(for: browser).rawValue,
                                       globalPause: preferences.pauseDuration.rawValue, browserBundleID: browser))
    }

    private func cancelTool() {
        let loadingSession = styleLoadingSession
        styleLoadingSession = nil
        let hadTarget = toolTarget != nil
        toolTask?.cancel(); toolTask = nil
        toolTarget = nil; toolID = nil
        compose.hide(); readability.hide()
        if let loadingSession { sendResults(loadingSession) }
        if hadTarget, activeSession == nil { AnalysisCoordinator.shared.browserFocusChanged() }
    }

    private func status(_ message: String, session: String) {
        guard let owner = owners[session] else { return }
        connections[owner]?.send(BrowserMessage(kind: "status", session: session, status: message))
    }

    private func isCurrent(_ target: BrowserMessage) -> Bool {
        guard let session = target.session, let current = snapshots[session],
              toolTarget?.session == session, toolTarget?.revision == target.revision,
              toolTarget?.start == target.start, toolTarget?.end == target.end,
              current.revision == target.revision, current.text == target.text,
              let origin = current.pageURL ?? current.origin, let url = URL(string: origin)
        else { return false }
        return UserPreferences.shared.isEnabled(for: browserID(for: session)) && UserPreferences.shared.isEnabled(forURL: url)
    }

    private func indicatorPlacement(_ geometry: BrowserIndicatorGeometry?, session: String) -> (point: CGPoint, direction: PopoverOpenDirection, viewport: CGRect)? {
        guard let geometry,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == browserID(for: session),
              let pageURL = snapshots[session]?.pageURL,
              let frame = AccessibilityBridge.focusedWebAreaFrame(processID: app.processIdentifier, pageURL: pageURL),
              frame.width > 0, frame.height > 0
        else {
            Logger.warning("Browser pill placement unavailable; waiting for editor geometry", category: Logger.ui)
            return nil
        }
        let viewport = CoordinateMapper.toCocoaCoordinates(frame)
        let anchor = Self.indicatorAnchor(geometry, viewport: viewport)
        return (anchor.point, anchor.direction, viewport)
    }

    static func indicatorAnchor(_ geometry: BrowserIndicatorGeometry, viewport: CGRect) -> (point: CGPoint, direction: PopoverOpenDirection) {
        let rect = CGRect(x: viewport.minX + geometry.x * viewport.width,
                          y: viewport.maxY - (geometry.y + geometry.height) * viewport.height,
                          width: geometry.width * viewport.width, height: geometry.height * viewport.height)
        // Match the native indicator's inward edge and 25pt gap.
        switch geometry.edge {
        case "left": return (CGPoint(x: rect.maxX + 25, y: rect.midY), .right)
        case "top": return (CGPoint(x: rect.midX, y: rect.minY - 25), .bottom)
        case "bottom": return (CGPoint(x: rect.midX, y: rect.maxY + 25), .top)
        default: return (CGPoint(x: rect.minX - 25, y: rect.midY), .left)
        }
    }

    private func openStyle(_ snapshot: BrowserMessage, indicator: BrowserIndicatorGeometry?) {
        guard let session = snapshot.session, let text = snapshot.text,
              isBrowserFrontmost(session),
              UserPreferences.shared.enableStyleChecking
        else { return }
        if styleLoadingSession == session { return }
        guard let placement = indicatorPlacement(indicator, session: session) else { return }
        cancelTool()
        toolTarget = snapshot
        guard isCurrent(snapshot) else { cancelTool(); return }
        let wasShown = shownSession == session
        shownSession = session
        if let suggestions = styleResults[session] {
            cancelTool()
            if wasShown, popover.isVisible, popover.currentStyleSuggestion != nil {
                popover.cancelHide()
            } else {
                popover.showUnified(errors: [], styleSuggestions: suggestions, at: placement.point, openDirection: placement.direction, constrainToWindow: placement.viewport, sourceText: text)
            }
            return
        }
        guard #available(macOS 26.0, *) else { status("Apple Intelligence requires macOS 26 or later.", session: session); cancelTool(); return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= GenerationContext.maximumSelectionBytes
        else { status("Use a shorter passage for Style & Clarity.", session: session); cancelTool(); return }
        let engine = FoundationModelsEngine()
        engine.checkAvailability()
        guard engine.status.isAvailable else { status(engine.status.userMessage, session: session); cancelTool(); return }
        let preferences = UserPreferences.shared
        let style = WritingStyle.allCases.first { $0.displayName == preferences.selectedWritingStyle } ?? .default
        let preset = StyleTemperaturePreset(rawValue: preferences.styleTemperaturePreset) ?? .balanced
        let vocabulary = CustomVocabulary.shared.allWords()
        popover.hide()
        styleLoadingSession = session
        sendResults(session)
        let id = UUID()
        toolID = id
        toolTask = Task { [weak self] in
            guard let self else { return }
            defer { if toolID == id { cancelTool() } }
            do {
                let suggestions = try await engine.analyzeStyle(text, style: style, temperaturePreset: preset, customVocabulary: vocabulary)
                try Task.checkCancellation()
                guard isCurrent(snapshot) else { return }
                let coordinator = AnalysisCoordinator.shared
                let sensitivity = StyleSensitivity(rawValue: preferences.styleSensitivity) ?? .balanced
                let filtered = suggestions.filter {
                    coordinator.suggestionTracker.shouldShowStyleSuggestion(originalText: $0.originalText, confidence: $0.confidence,
                                                                            impact: $0.impact, source: "appleIntelligence",
                                                                            isManualCheck: true, sensitivity: sensitivity)
                }
                let valid = coordinator.filterStyleSuggestionsNotOverlappingGrammarErrors(filtered, grammarErrors: results[session] ?? [])
                styleResults[session] = valid
                styleLoadingSession = nil
                sendResults(session)
                guard isBrowserFrontmost(session) else { return }
                popover.showUnified(errors: [], styleSuggestions: valid, at: placement.point, openDirection: placement.direction, constrainToWindow: placement.viewport, sourceText: text)
            } catch {
                guard !Task.isCancelled else { return }
                status(QuickRewriteStatus.failureMessage(for: error, cancelled: false), session: session)
            }
        }
    }

    private func applyStyle(_ suggestion: StyleSuggestionModel) async {
        guard let session = shownSession, let snapshot = snapshots[session], let text = snapshot.text,
              styleResults[session]?.contains(where: { $0.id == suggestion.id }) == true,
              let origin = snapshot.pageURL ?? snapshot.origin, let url = URL(string: origin),
              UserPreferences.shared.isEnabled(for: browserID(for: session)), UserPreferences.shared.isEnabled(forURL: url),
              UserPreferences.shared.enableStyleChecking,
              [browserID(for: session), Bundle.main.bundleIdentifier].contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
              let range = TextIndexConverter.scalarRangeToUTF16CFRange(start: suggestion.originalStart, end: suggestion.originalEnd, in: text),
              (text as NSString).substring(with: NSRange(location: range.location, length: range.length)) == suggestion.originalText,
              let owner = owners[session], let connection = connections[owner]
        else { return }
        await applyRange(range, replacement: suggestion.suggestedText, snapshot: snapshot, connection: connection)
    }

    private func regenerateStyle(_ suggestion: StyleSuggestionModel) async -> StyleSuggestionModel? {
        guard #available(macOS 26.0, *), let session = shownSession, let snapshot = snapshots[session],
              let text = snapshot.text, styleResults[session]?.contains(where: { $0.id == suggestion.id }) == true
        else { return nil }
        cancelTool()
        toolTarget = snapshot
        let id = UUID()
        toolID = id
        defer { if toolID == id { cancelTool() } }
        guard isCurrent(snapshot), UserPreferences.shared.enableStyleChecking else { return nil }
        do {
            let engine = FoundationModelsEngine()
            engine.checkAvailability()
            guard let regenerated = try await engine.regenerateStyleSuggestion(originalText: text, previousSuggestion: suggestion,
                                                                               style: suggestion.style, customVocabulary: CustomVocabulary.shared.allWords()),
                toolID == id, isCurrent(snapshot), UserPreferences.shared.enableStyleChecking,
                let index = styleResults[session]?.firstIndex(where: { $0.id == suggestion.id })
            else { return nil }
            styleResults[session]?[index] = regenerated
            return regenerated
        } catch {
            status(QuickRewriteStatus.failureMessage(for: error, cancelled: false), session: session)
            return nil
        }
    }

    private func openTool(_ target: BrowserMessage) {
        cancelTool(); popover.hide()
        guard let session = target.session, let text = target.text, let start = target.start, let end = target.end,
              let range = Range(NSRange(location: start, length: end - start), in: text),
              isBrowserFrontmost(session)
        else { return }
        toolTarget = target
        toolID = UUID()
        var opened = false
        defer { if !opened { cancelTool() } }
        guard isCurrent(target) else { status("TextWarden is paused for this page.", session: session); cancelTool(); return }
        let selected = String(text[range])
        let preferences = UserPreferences.shared
        if target.kind == "readability" {
            guard preferences.readabilityEnabled else { status("Enable Readability in TextWarden settings.", session: session); return }
            let audience = TargetAudience(fromDisplayName: preferences.selectedTargetAudience) ?? .general
            guard let analysis = ReadabilityCalculator.shared.analyzeForTargetAudience(selected.isEmpty ? text : selected, targetAudience: audience) else {
                status("Add more text to calculate readability.", session: session); return
            }
            guard let placement = indicatorPlacement(target.indicator, session: session) else { return }
            readability.show(at: placement.point, direction: placement.direction, result: analysis.overallResult, analysis: analysis, fromIndicator: true)
            opened = true
            status("Readability: \(analysis.overallResult.displayScore) · \(analysis.overallResult.label)", session: session)
            return
        }
        guard #available(macOS 26.0, *) else { status("Apple Intelligence requires macOS 26 or later.", session: session); return }
        guard preferences.enableStyleChecking else { status("Enable Style checking in TextWarden settings.", session: session); return }
        guard selected.utf8.count <= GenerationContext.maximumSelectionBytes else { status("Select a shorter passage for Apple Intelligence.", session: session); return }
        let engine = FoundationModelsEngine()
        engine.checkAvailability()
        guard engine.status.isAvailable else { status(engine.status.userMessage, session: session); return }
        if target.kind == "compose" {
            let context = GenerationContext(selectedText: selected.isEmpty ? nil : selected, surroundingText: nil,
                                            fullTextLength: text.count, cursorPosition: start, source: selected.isEmpty ? .none : .selection)
            guard let placement = indicatorPlacement(target.indicator, session: session) else { return }
            compose.show(at: placement.point, direction: placement.direction, context: context, fromIndicator: true)
            opened = true
            return
        }
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status("Select text to rewrite.", session: session); return }
        let style = WritingStyle.allCases.first { $0.displayName == preferences.selectedWritingStyle } ?? .default
        let preset = StyleTemperaturePreset(rawValue: preferences.styleTemperaturePreset) ?? .balanced
        let vocabulary = CustomVocabulary.shared.allWords().filter { selected.localizedCaseInsensitiveContains($0) }
        status("Rewriting locally…", session: session)
        let id = toolID
        opened = true
        toolTask = Task { [weak self] in
            guard let self else { return }
            defer { if toolID == id { cancelTool() } }
            do {
                let rewrite = try await engine.rewriteSelection(selected, style: style, preset: preset, customVocabulary: vocabulary)
                try Task.checkCancellation()
                guard isCurrent(target) else { return }
                guard rewrite.hasChanges(comparedTo: selected) else { status("No rewrite suggested.", session: session); return }
                guard await QuickRewriteStatus.shared.confirmReplacement(original: selected, proposed: rewrite.text, reason: rewrite.reason) else {
                    status("Rewrite cancelled.", session: session); return
                }
                await replaceSelection(rewrite.text, target: target)
            } catch {
                guard !Task.isCancelled else { return }
                status(QuickRewriteStatus.failureMessage(for: error, cancelled: error is CancellationError), session: session)
            }
        }
    }

    private func replaceSelection(_ replacement: String, target: BrowserMessage) async {
        guard isCurrent(target), !Task.isCancelled, UserPreferences.shared.enableStyleChecking,
              let session = target.session, let owner = owners[session], let connection = connections[owner],
              replacement.utf16.count <= 20000,
              [browserID(for: session), Bundle.main.bundleIdentifier].contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: browserID(for: session)).first?.activate()
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard isCurrent(target), !Task.isCancelled,
              isBrowserFrontmost(session)
        else { return }
        connection.send(BrowserMessage(kind: "replace", session: session, revision: target.revision, text: target.text,
                                       replacement: replacement, start: target.start, end: target.end, selectionRequired: true))
    }

    private func analyze(_ session: String) {
        tasks.removeValue(forKey: session)?.cancel()
        guard let snapshot = snapshots[session], let text = snapshot.text, let origin = snapshot.pageURL ?? snapshot.origin,
              let url = URL(string: origin), let owner = owners[session], let connection = connections[owner]
        else { return }
        let preferences = UserPreferences.shared
        guard preferences.isEnabled(for: browserID(for: session)), preferences.isEnabled(forURL: url) else {
            results.removeValue(forKey: session)
            connection.send(BrowserMessage(kind: "result", session: session, revision: snapshot.revision, errors: [], status: "TextWarden is paused for this page.", theme: preferences.overlayTheme, checkingEnabled: false))
            return
        }
        tasks[session] = Task { [weak self] in
            let result = await GrammarEngine.shared.analyzeText(text,
                                                                dialect: preferences.selectedDialect,
                                                                enableInternetAbbrev: preferences.enableInternetAbbreviations,
                                                                enableGenZSlang: preferences.enableGenZSlang,
                                                                enableITTerminology: preferences.enableITTerminology,
                                                                enableBrandNames: preferences.enableBrandNames,
                                                                enablePersonNames: preferences.enablePersonNames,
                                                                enableLastNames: preferences.enableLastNames,
                                                                enableLanguageDetection: preferences.enableLanguageDetection,
                                                                excludedLanguages: Array(preferences.excludedLanguages),
                                                                enforceOxfordComma: preferences.enforceOxfordComma,
                                                                checkEllipsis: preferences.checkEllipsis,
                                                                checkUnclosedQuotes: preferences.checkUnclosedQuotes,
                                                                checkDashes: preferences.checkDashes)
            guard let self, !Task.isCancelled,
                  snapshots[session]?.revision == snapshot.revision,
                  snapshots[session]?.text == text
            else { return }
            results[session] = GrammarErrorFilter.filter(errors: result.errors, sourceText: text,
                                                         config: .fromPreferences(preferences), customVocabulary: CustomVocabulary.shared)
            sendResults(session)
            if pendingApply?.session == session {
                if popover.currentStyleSuggestion != nil {
                    popover.hide()
                } else {
                    popover.syncErrorsAfterReplacement(results[session] ?? [])
                }
                finishApply(success: true)
            }
            tasks.removeValue(forKey: session)
        }
    }

    private func sendResults(_ session: String) {
        guard let snapshot = snapshots[session], let text = snapshot.text,
              let owner = owners[session], let connection = connections[owner]
        else { return }
        let issues = (results[session] ?? []).enumerated().compactMap { index, error -> BrowserIssue? in
            guard let range = TextIndexConverter.scalarRangeToUTF16CFRange(start: error.start, end: error.end, in: text) else { return nil }
            var issue = BrowserIssue(id: index, start: range.location, end: range.location + range.length, message: error.message, suggestions: error.suggestions)
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let color = ErrorOverlayWindow.underlineColor(for: error.category).usingColorSpace(.sRGB) {
                    let rgb = "\(color.redComponent * 255),\(color.greenComponent * 255),\(color.blueComponent * 255)"
                    issue.underlineColor = "rgb(\(rgb))"
                    issue.highlightColor = "rgba(\(rgb),\(UnderlineView.highlightOpacity))"
                }
            }
            return issue
        }
        let preferences = UserPreferences.shared
        let showUnderlines = preferences.showUnderlines && preferences.areUnderlinesEnabled(for: browserID(for: session))
            && issues.count <= preferences.maxErrorsForUnderlines
        connection.send(BrowserMessage(kind: "result", session: session, revision: snapshot.revision, errors: issues,
                                       showUnderlines: showUnderlines, underlineThickness: min(5, max(1, preferences.underlineThickness)), theme: preferences.overlayTheme, checkingEnabled: true,
                                       presentation: browserPresentation(session: session, errors: results[session] ?? [])))
    }

    private func browserPresentation(session: String, errors: [GrammarErrorModel]) -> BrowserPresentation {
        let preferences = UserPreferences.shared
        let color = if errors.isEmpty {
            "green"
        } else if errors.contains(where: { ["Spelling", "Typo"].contains($0.category) }) {
            "red"
        } else if errors.contains(where: { ["Grammar", "Agreement", "Punctuation"].contains($0.category) }) {
            "orange"
        } else {
            "blue"
        }
        return BrowserPresentation(width: UIConstants.capsuleWidth, sectionHeight: UIConstants.capsuleSectionHeight,
                                   cornerRadius: UIConstants.capsuleCornerRadius,
                                   hoverEnabled: preferences.enableHoverPopover, hoverDelay: min(10000, max(0, preferences.popoverHoverDelayMs)),
                                   styleEnabled: preferences.enableStyleChecking, alwaysShow: preferences.alwaysShowCapsule, grammarColor: color,
                                   styleCount: styleResults[session]?.count, styleLoading: styleLoadingSession == session)
    }

    private func refreshShownSession() {
        guard let session = shownSession else { return }
        popover.hide(); analyze(session)
    }

    private func finishApply(success: Bool) {
        guard let pending = pendingApply else { return }
        pendingApply = nil; applyTimeout?.cancel(); applyTimeout = nil
        if !success { popover.hide(); shownSession = nil }
        pending.continuation.resume()
    }

    private func apply(_ error: GrammarErrorModel, replacement: String) async {
        guard let session = shownSession, let snapshot = snapshots[session], let text = snapshot.text,
              let origin = snapshot.pageURL ?? snapshot.origin, let url = URL(string: origin),
              UserPreferences.shared.isEnabled(for: browserID(for: session)), UserPreferences.shared.isEnabled(forURL: url),
              results[session]?.contains(where: { $0 === error }) == true,
              error.suggestions.contains(replacement),
              let owner = owners[session], let connection = connections[owner],
              let range = TextIndexConverter.scalarRangeToUTF16CFRange(start: error.start, end: error.end, in: text),
              let frontmost = NSWorkspace.shared.frontmostApplication,
              [browserID(for: session), Bundle.main.bundleIdentifier].contains(frontmost.bundleIdentifier)
        else { return }
        await applyRange(range, replacement: replacement, snapshot: snapshot, connection: connection)
    }

    private func applyRange(_ range: CFRange, replacement: String, snapshot: BrowserMessage, connection: BrowserConnection) async {
        guard pendingApply == nil, let session = snapshot.session, let text = snapshot.text else { return }
        let expected = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: replacement)
        popover.cancelHide()
        await withCheckedContinuation { continuation in
            pendingApply = (session, snapshot.revision ?? 0, expected, continuation)
            applyTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finishApply(success: false)
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: browserID(for: session)).first?.activate()
            connection.send(BrowserMessage(kind: "replace", session: session, revision: snapshot.revision, text: text, replacement: replacement, start: range.location, end: range.location + range.length))
        }
    }
}
