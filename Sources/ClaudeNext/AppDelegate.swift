import AppKit
import SwiftUI

/// Borderless panel that can still take keyboard focus.
final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Resizes its window to whatever SwiftUI actually wants.
final class AutoSizingHostingView<Content: View>: NSHostingView<Content> {
    var onContentSize: ((CGSize) -> Void)?
    private var lastReported: CGSize = .zero

    override func layout() {
        super.layout()
        let fitting = fittingSize
        guard fitting.height > 1 else { return }
        guard abs(fitting.height - lastReported.height) > 0.5
                || abs(fitting.width - lastReported.width) > 0.5 else { return }
        lastReported = fitting
        DispatchQueue.main.async { [weak self] in
            self?.onContentSize?(fitting)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = PromptModel()
    private let server = PromptServer()

    private var statusItem: NSStatusItem!
    private var panel: PromptPanel!
    private var hostingView: AutoSizingHostingView<RootView>!
    private var flagsMonitor: Any?
    /// Top edge stays put while the panel grows and shrinks.
    private var anchorTop: CGFloat = 0
    /// True when the panel opened itself for a request rather than being clicked open.
    private var openedForRequest = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.config = AppConfig.load()

        buildStatusItem()
        buildPanel()
        wireModel()
        startServer()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.optionDown = event.modifierFlags.contains(.option)
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for request in model.pending {
            request.answer(PromptDecision(decision: .pass))
        }
        server.stop()
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(active: false)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "ClaudeNext"
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            showMenu()
        } else if panel.isVisible {
            hidePanel()
        } else {
            openedForRequest = false
            presentPanel(focus: true)
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let count = model.pending.count
        let header = NSMenuItem(
            title: count == 0 ? "No pending requests" : "\(count) request\(count == 1 ? "" : "s") waiting",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: model.paused ? "Resume interception" : "Pause interception",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let rules = NSMenuItem(title: "Open rules…", action: #selector(openRules), keyEquivalent: "")
        rules.target = self
        menu.addItem(rules)

        let config = NSMenuItem(title: "Open config…", action: #selector(openConfig), keyEquivalent: "")
        config.target = self
        menu.addItem(config)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClaudeNext", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() { model.paused.toggle() }
    @objc private func openRules() { model.openRulesFile() }
    @objc private func openConfig() { model.openConfigFile() }

    // MARK: Panel

    private func buildPanel() {
        let root = RootView(model: model)
        hostingView = AutoSizingHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        hostingView.onContentSize = { [weak self] size in
            self?.applyContentSize(size)
        }

        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = hostingView
    }

    private func applyContentSize(_ size: CGSize) {
        guard panel != nil else { return }
        var frame = panel.frame
        frame.size = CGSize(width: max(size.width, 420), height: size.height)
        frame.origin.y = anchorTop - frame.height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func presentPanel(focus: Bool) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        var size = panel.frame.size
        size.height = max(size.height, hostingView.fittingSize.height)

        var x = buttonRect.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        anchorTop = buttonRect.minY - 6

        panel.setFrame(NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height),
                       display: true, animate: false)

        if focus { NSApp.activate() }
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away parks the request; the badge keeps it discoverable.
        hidePanel()
    }

    // MARK: Model + server

    private func wireModel() {
        model.onQueueChange = { [weak self] in
            guard let self else { return }
            refreshStatusItem()
            // Answering the last request closes the panel again, unless the
            // user had opened it themselves to browse.
            if model.pending.isEmpty && panel.isVisible && openedForRequest {
                openedForRequest = false
                hidePanel()
            }
        }
        model.onNewRequest = { [weak self] in
            guard let self else { return }
            if model.config.sound { NSSound(named: "Ping")?.play() }
            if !panel.isVisible { openedForRequest = true }
            presentPanel(focus: model.config.focusOnRequest)
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let count = model.pending.count
        button.image = StatusIcon.image(active: count > 0)
        if count > 1 {
            button.attributedTitle = NSAttributedString(
                string: " \(count)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: StatusIcon.accentColor
                ]
            )
        } else {
            button.title = ""
        }
        button.toolTip = count == 0 ? "ClaudeNext — idle" : "ClaudeNext — \(count) waiting"
    }

    private func startServer() {
        server.onStateChange = { [weak self] error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.model.serverError = error }
            }
        }
        server.statusProvider = { [weak self] done in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let model = self?.model else { return done("{}") }
                    let object: [String: Any] = [
                        "pending": model.pending.count,
                        "paused": model.paused,
                        "decisions": model.recent.count,
                        "current": model.pending.first.map {
                            "\($0.presentation.badge): \($0.presentation.summary)"
                        } ?? ""
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
                    done(String(data: data, encoding: .utf8) ?? "{}")
                }
            }
        }
        do {
            try server.start(port: model.config.port) { [weak self] payload, reply, registerAbandon in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else {
                            reply(PromptDecision(decision: .pass))
                            return
                        }
                        let request = PendingRequest(payload: payload, responder: reply)
                        let id = request.id
                        registerAbandon {
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated { self.model.abandon(id) }
                            }
                        }
                        self.model.enqueue(request)
                    }
                }
            }
        } catch {
            model.serverError = "Could not listen on port \(model.config.port): \(error.localizedDescription)"
        }
    }
}
