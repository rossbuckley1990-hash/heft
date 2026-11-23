import Foundation
import AppKit
import HeftCore

@MainActor
enum StudioLauncher {
    static func launch(workspacePath: String?, verificationCommand: String?, gainDB: Double) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let resolvedPath = workspacePath ?? prepareInteractiveSandbox()
        let delegate = StudioAppDelegate(
            workspacePath: resolvedPath,
            verificationCommand: verificationCommand,
            gainDB: gainDB,
            isBuiltInSandbox: workspacePath == nil
        )
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    /// Seeds a 3-file interactive Swift workspace so users can immediately feel Titanium, Cast Lead,
    /// and Cracked Ceramic states + Force Touch Z-Axis `RENAME_SWAP` on first launch.
    static func prepareInteractiveSandbox() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sandbox = home.appendingPathComponent(".heft-playground")
        let orderFile = sandbox.appendingPathComponent("OrderEngine.swift")
        if !FileManager.default.fileExists(atPath: orderFile.path) {
            try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
            resetSandboxToTitanium(at: sandbox)
        }
        return sandbox.path
    }

    static func resetSandboxToTitanium(at sandbox: URL) {
        let orderEngine = """
        import Foundation

        /// Core pricing engine coupled with CheckoutController.swift and BatchReconciler.swift.
        /// Type here to feel Machined Titanium keystrokes, or trigger presets above!
        public func calculateInvoiceTotal(cents: [Int], taxBasisPoints: Int) -> Int {
            let blockedAmounts: Set<Int> = [0, -1]
            var subtotal = 0
            for amount in cents {
                if blockedAmounts.contains(amount) { continue }
                subtotal += amount
            }
            return subtotal + (subtotal * taxBasisPoints) / 10_000
        }
        """

        let checkout = """
        import Foundation

        public struct CheckoutController {
            public func submitCart(lineItems: [Int]) -> Int {
                return calculateInvoiceTotal(cents: lineItems, taxBasisPoints: 825)
            }
        }
        """

        let reconciler = """
        import Foundation

        public struct BatchReconciler {
            public func auditDay(ledgers: [[Int]]) -> Int {
                var grandTotal = 0
                for ledger in ledgers {
                    grandTotal += calculateInvoiceTotal(cents: ledger, taxBasisPoints: 500)
                }
                return grandTotal
            }
        }
        """

        try? orderEngine.write(to: sandbox.appendingPathComponent("OrderEngine.swift"), atomically: true, encoding: .utf8)
        try? checkout.write(to: sandbox.appendingPathComponent("CheckoutController.swift"), atomically: true, encoding: .utf8)
        try? reconciler.write(to: sandbox.appendingPathComponent("BatchReconciler.swift"), atomically: true, encoding: .utf8)
    }

    static let castLeadPreset = """
    import Foundation

    /// O(n^2) CAST LEAD DEMO: `blockedAmounts` is now an Array scanned linearly inside a hot loop!
    /// Type on line 9 or scroll/glide across it: feel heavy 420 Hz keystrokes & viscous trackpad detents.
    public func calculateInvoiceTotal(cents: [Int], taxBasisPoints: Int) -> Int {
        let blockedAmounts: [Int] = [0, -1, -999, 404]
        var subtotal = 0
        for amount in cents {
            if blockedAmounts.first(where: { $0 == amount }) != nil { continue }
            subtotal += amount
        }
        return subtotal + (subtotal * taxBasisPoints) / 10_000
    }
    """

    static let fracturedPreset = """
    import Foundation

    /// FRACTURED CERAMIC DEMO: Added required `currency: String` parameter without a default!
    /// Downstream callers in CheckoutController.swift & BatchReconciler.swift just fractured.
    /// -> Glide over line 6 to feel 6pt fracture grit. Force-Press (Stage 2) or press ⌘⏎ to peel Z-axis & RENAME_SWAP!
    public func calculateInvoiceTotal(cents: [Int], taxBasisPoints: Int, currency: String) -> Int {
        let blockedAmounts: Set<Int> = [0, -1]
        var subtotal = 0
        for amount in cents {
            if blockedAmounts.contains(amount) { continue }
            subtotal += amount
        }
        return subtotal + (subtotal * taxBasisPoints) / 10_000
    }
    """
}

// MARK: - Studio App Delegate & Main Workbench Controller

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    private let workspacePath: String
    private let isBuiltInSandbox: Bool
    private var lightCone: APFSLightCone!
    private let audioEngine: ModalAudioEngine
    private let tribology = TribologyEngine()

    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var filePopup: NSPopUpButton!
    private var materialBadge: NSTextField!
    private var metricsLabel: NSTextField!
    private var lineFeelLabel: NSTextField!
    private var peelStatusBanner: NSTextField!
    private var gutterView: ImpedanceGutterView!
    private var editorView: HeftSensorimotorTextView!
    private var zPeelOverlay: ZAxisOverlayView!

    private var currentSnapshot: WorkspaceStressSnapshot?
    private var currentBranches: [CounterfactualBranch] = []
    private var activeRelativeFile: String = ""
    private var saveWorkItem: DispatchWorkItem?
    private var previousFracture: Double = 0.0

    init(workspacePath: String, verificationCommand: String?, gainDB: Double, isBuiltInSandbox: Bool) {
        self.workspacePath = workspacePath
        self.isBuiltInSandbox = isBuiltInSandbox
        self.audioEngine = ModalAudioEngine(gainDB: gainDB)
        super.init()
        self.lightCone = try? APFSLightCone(workspacePath: workspacePath, verificationCommand: verificationCommand)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = audioEngine.start()
        setupMenuBar()
        setupStatusBarItem()
        setupWindow()
        reloadFileList()
        evaluateWorkspaceNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - UI Construction

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let peelItem = NSMenuItem(title: "Toggle Z-Axis Counterfactual Peel", action: #selector(toggleZPeelAction), keyEquivalent: "\r")
        peelItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(peelItem)

        let swapItem = NSMenuItem(title: "Atomic RENAME_SWAP Best Timeline", action: #selector(swapPrimaryBranchAction), keyEquivalent: "s")
        swapItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(swapItem)

        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Heft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◆ HEFT"
        item.button?.target = self
        item.button?.action = #selector(bringWindowToFront)
        self.statusItem = item
    }

    @objc private func bringWindowToFront() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupWindow() {
        let rect = NSRect(x: 0, y: 0, width: 1060, height: 700)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Heft — Causal Impedance Workbench (\(URL(fileURLWithPath: workspacePath).lastPathComponent))"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
        window.center()

        let root = NSView(frame: rect)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        // Top Telemetry Header
        let header = NSView(frame: NSRect(x: 0, y: rect.height - 96, width: rect.width, height: 96))
        header.autoresizingMask = [.width, .minYMargin]
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0).cgColor
        root.addSubview(header)

        filePopup = NSPopUpButton(frame: NSRect(x: 18, y: 16, width: 230, height: 28), pullsDown: false)
        filePopup.target = self
        filePopup.action = #selector(fileSelectionChanged)
        header.addSubview(filePopup)

        materialBadge = NSTextField(labelWithString: "◆ MACHINED TITANIUM")
        materialBadge.frame = NSRect(x: 262, y: 18, width: 230, height: 24)
        materialBadge.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        materialBadge.textColor = NSColor.systemCyan
        header.addSubview(materialBadge)

        metricsLabel = NSTextField(labelWithString: "Mass 0%  ·  Tension 0%  ·  Fracture 0%  ·  Coherence 100%")
        metricsLabel.frame = NSRect(x: 500, y: 19, width: 540, height: 22)
        metricsLabel.autoresizingMask = [.width]
        metricsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        metricsLabel.textColor = NSColor(calibratedWhite: 0.82, alpha: 1.0)
        header.addSubview(metricsLabel)

        // Interactive Preset & Z-Axis Action Strip
        if isBuiltInSandbox {
            let b1 = makePillButton("1 · Clean Titanium", x: 18, y: 50, width: 145, action: #selector(loadTitaniumPreset))
            let b2 = makePillButton("2 · Inject O(n²) Lead", x: 171, y: 50, width: 162, action: #selector(loadCastLeadPreset))
            let b3 = makePillButton("3 · Fracture Contract", x: 341, y: 50, width: 168, action: #selector(loadFracturePreset))
            header.addSubview(b1)
            header.addSubview(b2)
            header.addSubview(b3)
        }

        let peelBtn = makePillButton("Peel Z-Axis Cones (Force Press / ⌘⏎)", x: rect.width - 295, y: 50, width: 277, action: #selector(toggleZPeelAction))
        peelBtn.autoresizingMask = [.minXMargin]
        header.addSubview(peelBtn)

        // Editor Area (Left Impedance Gutter + Sensorimotor TextView)
        let bodyHeight = rect.height - 96 - 38
        gutterView = ImpedanceGutterView(frame: NSRect(x: 0, y: 38, width: 48, height: bodyHeight))
        gutterView.autoresizingMask = [.height]
        root.addSubview(gutterView)

        let scrollView = NSScrollView(frame: NSRect(x: 48, y: 38, width: rect.width - 48, height: bodyHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)

        editorView = HeftSensorimotorTextView(frame: NSRect(x: 0, y: 0, width: rect.width - 64, height: bodyHeight))
        editorView.minSize = NSSize(width: 0, height: bodyHeight)
        editorView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editorView.isVerticallyResizable = true
        editorView.isHorizontallyResizable = false
        editorView.autoresizingMask = [.width]
        editorView.textContainer?.containerSize = NSSize(width: rect.width - 68, height: CGFloat.greatestFiniteMagnitude)
        editorView.textContainer?.widthTracksTextView = true
        editorView.isRichText = false
        editorView.isAutomaticQuoteSubstitutionEnabled = false
        editorView.isAutomaticDashSubstitutionEnabled = false
        editorView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        editorView.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
        editorView.textColor = NSColor(calibratedWhite: 0.93, alpha: 1.0)
        editorView.insertionPointColor = NSColor.systemCyan
        editorView.delegate = self

        editorView.onKeystroke = { [weak self] keyCode, line in
            self?.handleKeystroke(keyCode: keyCode, oneBasedLine: line)
        }
        editorView.onHoverLine = { [weak self] point, line in
            self?.handleCursorHover(point: point, oneBasedLine: line)
        }
        editorView.onInertialScroll = { [weak self] dx, dy, line in
            self?.handleInertialScroll(dx: dx, dy: dy, oneBasedLine: line) ?? dy
        }
        editorView.onForceDepthChange = { [weak self] stage, pressure, deltaX in
            self?.handleForceDepth(stage: stage, pressure: pressure, horizontalSlide: deltaX)
        }

        scrollView.documentView = editorView
        root.addSubview(scrollView)

        // Bottom Tactile Telemetry Footer
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: rect.width, height: 38))
        footer.autoresizingMask = [.width, .maxYMargin]
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0).cgColor
        root.addSubview(footer)

        lineFeelLabel = NSTextField(labelWithString: "Glide cursor across lines to feel spatial trackpad friction · Force-press (Stage 2) to peel counterfactual APFS realities")
        lineFeelLabel.frame = NSRect(x: 16, y: 10, width: rect.width - 310, height: 18)
        lineFeelLabel.autoresizingMask = [.width]
        lineFeelLabel.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        lineFeelLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1.0)
        footer.addSubview(lineFeelLabel)

        peelStatusBanner = NSTextField(labelWithString: String(format: "HAL %.2f ms (<12 ms Haas)", audioEngine.bufferLatencyMilliseconds))
        peelStatusBanner.frame = NSRect(x: rect.width - 285, y: 10, width: 270, height: 18)
        peelStatusBanner.alignment = .right
        peelStatusBanner.autoresizingMask = [.minXMargin]
        peelStatusBanner.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        peelStatusBanner.textColor = NSColor.systemTeal
        footer.addSubview(peelStatusBanner)

        // Z-Axis Counterfactual Peel Overlay (hidden until Force Press Stage 2 or ⌘⏎)
        zPeelOverlay = ZAxisOverlayView(frame: NSRect(x: 72, y: 66, width: rect.width - 110, height: bodyHeight - 56))
        zPeelOverlay.autoresizingMask = [.width, .height]
        zPeelOverlay.isHidden = true
        zPeelOverlay.onSelectSwap = { [weak self] branchID in
            self?.performTimelineSwap(branchID: branchID)
        }
        zPeelOverlay.onDismiss = { [weak self] in
            self?.zPeelOverlay.isHidden = true
        }
        root.addSubview(zPeelOverlay)

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
    }

    private func makePillButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.frame = NSRect(x: x, y: y, width: width, height: 26)
        btn.bezelStyle = .rounded
        btn.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
        return btn
    }

    // MARK: - File Management & Presets

    private func reloadFileList() {
        let analyzer = StructuralAnalyzer()
        let rootURL = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let urls = analyzer.collectSourceFiles(under: rootURL).sorted { $0.path < $1.path }
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        filePopup.removeAllItems()
        for u in urls {
            let rel = u.path.hasPrefix(rootPrefix) ? String(u.path.dropFirst(rootPrefix.count)) : u.lastPathComponent
            filePopup.addItem(withTitle: rel)
        }

        if let preferredIdx = filePopup.itemTitles.firstIndex(of: "OrderEngine.swift") {
            filePopup.selectItem(at: preferredIdx)
        }
        loadSelectedFileIntoEditor()
    }

    @objc private func fileSelectionChanged() {
        saveActiveEditorToDisk()
        loadSelectedFileIntoEditor()
        refreshUIFromSnapshot()
    }

    private func loadSelectedFileIntoEditor() {
        guard let selected = filePopup.selectedItem?.title else { return }
        activeRelativeFile = selected
        let fileURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(selected)
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            editorView.string = content
        }
    }

    private func saveActiveEditorToDisk() {
        guard !activeRelativeFile.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(activeRelativeFile)
        try? editorView.string.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    @objc private func loadTitaniumPreset() {
        StudioLauncher.resetSandboxToTitanium(at: URL(fileURLWithPath: workspacePath))
        loadSelectedFileIntoEditor()
        evaluateWorkspaceNow()
    }

    @objc private func loadCastLeadPreset() {
        StudioLauncher.resetSandboxToTitanium(at: URL(fileURLWithPath: workspacePath))
        let orderURL = URL(fileURLWithPath: workspacePath).appendingPathComponent("OrderEngine.swift")
        try? StudioLauncher.castLeadPreset.write(to: orderURL, atomically: true, encoding: .utf8)
        if let idx = filePopup.itemTitles.firstIndex(of: "OrderEngine.swift") {
            filePopup.selectItem(at: idx)
        }
        loadSelectedFileIntoEditor()
        evaluateWorkspaceNow()
        audioEngine.triggerKeystroke(stress: StressVector(mass: 0.78, tension: 0.4, fracture: 0), keyCode: 36)
    }

    @objc private func loadFracturePreset() {
        // Ensure a clean crystallized checkpoint exists right before fracturing!
        StudioLauncher.resetSandboxToTitanium(at: URL(fileURLWithPath: workspacePath))
        evaluateWorkspaceNow()

        let orderURL = URL(fileURLWithPath: workspacePath).appendingPathComponent("OrderEngine.swift")
        try? StudioLauncher.fracturedPreset.write(to: orderURL, atomically: true, encoding: .utf8)
        if let idx = filePopup.itemTitles.firstIndex(of: "OrderEngine.swift") {
            filePopup.selectItem(at: idx)
        }
        loadSelectedFileIntoEditor()
        evaluateWorkspaceNow()
        audioEngine.triggerKeystroke(stress: StressVector(mass: 0.1, tension: 0.6, fracture: 1.0), keyCode: 36)
    }

    // MARK: - Live Sensorimotor Loop

    func textDidChange(_ notification: Notification) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveActiveEditorToDisk()
            self?.evaluateWorkspaceNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(90), execute: item)
    }

    private func evaluateWorkspaceNow() {
        guard let cone = lightCone, let res = try? cone.evaluateLightCone() else { return }
        let newFracture = res.snapshot.stress.fracture
        if previousFracture >= 0.25 && newFracture < 0.25 {
            audioEngine.triggerCrystallization()
            tribology.fireCrystallizationSnap()
        }
        previousFracture = newFracture
        currentSnapshot = res.snapshot
        currentBranches = res.branches
        refreshUIFromSnapshot()
    }

    private func refreshUIFromSnapshot() {
        guard let snap = currentSnapshot else { return }
        let s = snap.stress

        let color = Self.color(for: s.material)
        materialBadge.stringValue = "◆ \(s.material.shortLabel)"
        materialBadge.textColor = color
        statusItem?.button?.title = "◆ \(s.material.shortLabel) \(HeftMain.pct(s.coherence))"

        metricsLabel.stringValue = String(
            format: "Mass %@  ·  Tension %@  ·  Fracture %@  ·  Coherence %@  ·  %llu µs",
            HeftMain.pct(s.mass),
            HeftMain.pct(s.tension),
            HeftMain.pct(s.fracture),
            HeftMain.pct(s.coherence),
            snap.analysisMicroseconds
        )

        let fileReport = snap.files.first { $0.relativePath == activeRelativeFile }
        let lineCount = max(1, editorView.string.components(separatedBy: .newlines).count)
        gutterView.update(report: fileReport, totalLines: lineCount)
        zPeelOverlay.update(snapshot: snap, branches: currentBranches)
    }

    private func stressForLine(_ oneBasedLine: Int) -> (StressVector, LineImpedance?) {
        guard let snap = currentSnapshot else { return (.zero, nil) }
        if let fileReport = snap.files.first(where: { $0.relativePath == activeRelativeFile }),
           let lineImp = fileReport.impedance(atLine: oneBasedLine) {
            return (lineImp.stress, lineImp)
        }
        return (snap.stress, nil)
    }

    private func handleKeystroke(keyCode: UInt16, oneBasedLine: Int) {
        let (stress, _) = stressForLine(oneBasedLine)
        audioEngine.triggerKeystroke(stress: stress, keyCode: keyCode)
    }

    private func handleCursorHover(point: NSPoint, oneBasedLine: Int) {
        let (stress, imp) = stressForLine(oneBasedLine)
        let pulse = tribology.processCursorMove(to: point, stress: stress)
        if let imp, let reason = imp.reasons.first {
            let pulseTag = pulse != nil ? " [TAPTIC]" : ""
            lineFeelLabel.stringValue = "Line \(oneBasedLine) · \(imp.stress.material.shortLabel)\(pulseTag) — \(reason)"
            lineFeelLabel.textColor = Self.color(for: imp.stress.material)
        } else {
            lineFeelLabel.stringValue = "Line \(oneBasedLine) · Frictionless glass (\(stress.material.rawValue))"
            lineFeelLabel.textColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
        }
    }

    private func handleInertialScroll(dx: CGFloat, dy: CGFloat, oneBasedLine: Int) -> CGFloat {
        let (stress, _) = stressForLine(oneBasedLine)
        let res = tribology.processScrollDelta(dx: dx, dy: dy, stress: stress)
        return res.scaledDY
    }

    private func handleForceDepth(stage: Int, pressure: Float, horizontalSlide: CGFloat) {
        if stage >= 2 {
            if zPeelOverlay.isHidden {
                tribology.fireCrystallizationSnap()
                zPeelOverlay.isHidden = false
            }
            let normalized = CGFloat(min(1.0, max(0.2, pressure)))
            zPeelOverlay.alphaValue = 0.88 + 0.12 * normalized
            peelStatusBanner.stringValue = String(format: "Z-AXIS STAGE 2 (%.0f%%) · Slide → to Swap", pressure * 100)

            // Horizontal finger slide while deep-pressing triggers instant RENAME_SWAP!
            if abs(horizontalSlide) > 52, let best = preferredSwapBranch() {
                performTimelineSwap(branchID: best.id)
            }
        }
    }

    @objc private func toggleZPeelAction() {
        zPeelOverlay.isHidden.toggle()
        if !zPeelOverlay.isHidden {
            tribology.fireCrystallizationSnap()
            zPeelOverlay.update(snapshot: currentSnapshot, branches: currentBranches)
        }
    }

    @objc private func swapPrimaryBranchAction() {
        guard let best = preferredSwapBranch() else { return }
        performTimelineSwap(branchID: best.id)
    }

    private func preferredSwapBranch() -> CounterfactualBranch? {
        currentBranches.first(where: { $0.kind == .contractRepair })
            ?? currentBranches.first(where: { !$0.deltas.isEmpty })
            ?? currentBranches.first
    }

    private func performTimelineSwap(branchID: String) {
        saveActiveEditorToDisk()
        guard let receipt = try? lightCone.swapTimeline(branchID: branchID) else { return }
        zPeelOverlay.isHidden = true
        loadSelectedFileIntoEditor()
        evaluateWorkspaceNow()
        audioEngine.triggerCrystallization()
        tribology.fireCrystallizationSnap()
        peelStatusBanner.stringValue = "⚡ RENAME_SWAP in \(receipt.swapMicroseconds) µs (\(receipt.branchID))"
    }

    static func color(for material: MaterialState) -> NSColor {
        switch material {
        case .titanium: return NSColor.systemCyan
        case .tautSteel: return NSColor.systemOrange
        case .castLead: return NSColor(calibratedRed: 0.68, green: 0.52, blue: 1.0, alpha: 1.0)
        case .crackedCeramic: return NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.38, alpha: 1.0)
        }
    }
}

// MARK: - Sensorimotor NSTextView (Keystrokes, Hover Tribology, Inertial Scroll, Force Touch Stage 2)

final class HeftSensorimotorTextView: NSTextView {
    var onKeystroke: ((UInt16, Int) -> Void)?
    var onHoverLine: ((NSPoint, Int) -> Void)?
    var onInertialScroll: ((CGFloat, CGFloat, Int) -> CGFloat)?
    var onForceDepthChange: ((Int, Float, CGFloat) -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var stage2AnchorX: CGFloat?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func keyDown(with event: NSEvent) {
        let line = insertionOneBasedLine()
        onKeystroke?(event.keyCode, line)
        super.keyDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let line = lineNumber(at: local)
        onHoverLine?(local, line)
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onForceDepthChange?(2, 1.0, 0)
            return
        }
        stage2AnchorX = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if event.stage >= 2 {
            let x = event.locationInWindow.x
            if stage2AnchorX == nil { stage2AnchorX = x }
            let deltaX = x - (stage2AnchorX ?? x)
            onForceDepthChange?(event.stage, event.pressure, deltaX)
            return
        }
        super.mouseDragged(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        if event.stage >= 2 {
            if stage2AnchorX == nil {
                stage2AnchorX = event.locationInWindow.x
            }
            let deltaX = event.locationInWindow.x - (stage2AnchorX ?? event.locationInWindow.x)
            onForceDepthChange?(event.stage, event.pressure, deltaX)
        } else {
            stage2AnchorX = nil
        }
        super.pressureChange(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let line = lineNumber(at: local)
        if let scaledDY = onInertialScroll?(event.scrollingDeltaX, event.scrollingDeltaY, line),
           let clipView = enclosingScrollView?.contentView {
            var origin = clipView.bounds.origin
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            origin.y = max(0, origin.y - scaledDY * multiplier)
            clipView.scroll(to: origin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
            return
        }
        super.scrollWheel(with: event)
    }

    private func insertionOneBasedLine() -> Int {
        let loc = min(selectedRange().location, (string as NSString).length)
        let prefix = (string as NSString).substring(to: loc)
        return max(1, prefix.components(separatedBy: .newlines).count)
    }

    private func lineNumber(at point: NSPoint) -> Int {
        guard let lm = layoutManager, let tc = textContainer else { return 1 }
        let containerPt = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIdx = lm.glyphIndex(for: containerPt, in: tc)
        let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
        let clamped = min(charIdx, (string as NSString).length)
        let prefix = (string as NSString).substring(to: clamped)
        return max(1, prefix.components(separatedBy: .newlines).count)
    }
}

// MARK: - Left Physical Impedance Gutter

final class ImpedanceGutterView: NSView {
    private var report: FileStressReport?
    private var totalLines: Int = 1

    override var isFlipped: Bool { true }

    func update(report: FileStressReport?, totalLines: Int) {
        self.report = report
        self.totalLines = max(1, totalLines)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).setFill()
        dirtyRect.fill()

        let lineHeight: CGFloat = 17.0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1.0)
        ]

        for line in 1...min(totalLines, 300) {
            let y = CGFloat(line - 1) * lineHeight + 2.0
            let numStr = String(format: "%3d", line) as NSString
            numStr.draw(at: NSPoint(x: 6, y: y), withAttributes: attrs)

            if let imp = report?.impedance(atLine: line) {
                let c = StudioAppDelegate.color(for: imp.stress.material)
                c.setFill()
                let barWidth = max(3.0, CGFloat(imp.stress.compositeHeft) * 9.0)
                NSRect(x: bounds.width - barWidth - 2, y: y + 2, width: barWidth, height: lineHeight - 3).fill()
            }
        }
    }
}

// MARK: - Z-Axis Counterfactual Light-Cone Peel Overlay

final class ZAxisOverlayView: NSView {
    var onSelectSwap: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let stackContainer = NSView()
    private var activeBranches: [CounterfactualBranch] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.16, alpha: 0.97).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.systemCyan.withAlphaComponent(0.55).cgColor

        stackContainer.frame = bounds
        stackContainer.autoresizingMask = [.width, .height]
        addSubview(stackContainer)
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: WorkspaceStressSnapshot?, branches: [CounterfactualBranch]) {
        activeBranches = branches
        stackContainer.subviews.forEach { $0.removeFromSuperview() }

        let w = bounds.width
        var cursorY = bounds.height - 46

        let title = NSTextField(labelWithString: "Z-AXIS COUNTERFACTUAL LIGHT-CONE  ·  APFS Zero-Copy Parallel Realities")
        title.frame = NSRect(x: 22, y: cursorY, width: w - 130, height: 24)
        title.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
        title.textColor = NSColor.systemCyan
        stackContainer.addSubview(title)

        let closeBtn = NSButton(title: "Close (Esc)", target: self, action: #selector(closeTapped))
        closeBtn.frame = NSRect(x: w - 108, y: cursorY - 2, width: 90, height: 26)
        closeBtn.bezelStyle = .rounded
        stackContainer.addSubview(closeBtn)

        cursorY -= 32
        if let snap = snapshot, !snap.fractures.isEmpty {
            let faultText = snap.fractures.prefix(2).map { "✦ \($0.relativeFile):\($0.line) — \($0.detail)" }.joined(separator: "\n")
            let faultLabel = NSTextField(labelWithString: faultText)
            faultLabel.frame = NSRect(x: 22, y: cursorY - 18, width: w - 44, height: 38)
            faultLabel.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
            faultLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.45, alpha: 1.0)
            stackContainer.addSubview(faultLabel)
            cursorY -= 48
        }

        if branches.isEmpty {
            let empty = NSTextField(labelWithString: "No counterfactual branches diverge yet — make an edit to spawn parallel APFS timelines.")
            empty.frame = NSRect(x: 22, y: cursorY - 20, width: w - 44, height: 24)
            empty.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            empty.textColor = .secondaryLabelColor
            stackContainer.addSubview(empty)
            return
        }

        for (idx, branch) in branches.prefix(3).enumerated() {
            let cardHeight: CGFloat = 112
            cursorY -= (cardHeight + 12)
            guard cursorY >= 12 else { break }

            let card = NSView(frame: NSRect(x: 20, y: cursorY, width: w - 40, height: cardHeight))
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.21, alpha: 1.0).cgColor
            card.layer?.cornerRadius = 10
            card.layer?.borderWidth = 1
            card.layer?.borderColor = StudioAppDelegate.color(for: branch.stress.material).withAlphaComponent(0.6).cgColor

            let header = NSTextField(labelWithString: "[\(branch.id)] \(branch.title)  ·  \(branch.stress.material.shortLabel)  ·  clonefile \(branch.cloneMicroseconds) µs")
            header.frame = NSRect(x: 14, y: cardHeight - 30, width: card.bounds.width - 210, height: 20)
            header.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)
            header.textColor = StudioAppDelegate.color(for: branch.stress.material)
            card.addSubview(header)

            let swapBtn = NSButton(title: "⚡ Atomic RENAME_SWAP", target: self, action: #selector(swapButtonClicked(_:)))
            swapBtn.tag = idx
            swapBtn.frame = NSRect(x: card.bounds.width - 188, y: cardHeight - 34, width: 174, height: 26)
            swapBtn.bezelStyle = .rounded
            card.addSubview(swapBtn)

            let sub = NSTextField(labelWithString: branch.explanation)
            sub.frame = NSRect(x: 14, y: cardHeight - 54, width: card.bounds.width - 28, height: 18)
            sub.font = NSFont.systemFont(ofSize: 12)
            sub.textColor = NSColor(calibratedWhite: 0.80, alpha: 1.0)
            card.addSubview(sub)

            let deltaPreview: String
            if let d = branch.deltas.first {
                deltaPreview = "\(d.relativePath):  \(d.previewBefore)   →   \(d.previewAfter)"
            } else {
                deltaPreview = "(Identical to current clean workspace state)"
            }
            let diffField = NSTextField(labelWithString: deltaPreview)
            diffField.frame = NSRect(x: 14, y: 12, width: card.bounds.width - 28, height: 32)
            diffField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            diffField.textColor = NSColor.systemGreen
            diffField.lineBreakMode = .byTruncatingMiddle
            card.addSubview(diffField)

            stackContainer.addSubview(card)
        }
    }

    @objc private func swapButtonClicked(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < activeBranches.count else { return }
        onSelectSwap?(activeBranches[idx].id)
    }

    @objc private func closeTapped() {
        onDismiss?()
    }
}
