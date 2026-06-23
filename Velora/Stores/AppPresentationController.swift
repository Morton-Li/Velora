import AppKit
import Combine
import SwiftUI

private enum AppPresentationPersistence {
    static let menuBarIconEnabledKey = "presentation.menuBarIconEnabled"

    static func isMenuBarIconEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: menuBarIconEnabledKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: menuBarIconEnabledKey)
    }

    static func saveMenuBarIconEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: menuBarIconEnabledKey)
    }
}

@MainActor
final class AppPresentationController: ObservableObject {
    @Published private var storedMenuBarIconEnabled: Bool

    var isMenuBarIconEnabled: Bool {
        get {
            storedMenuBarIconEnabled
        }
        set {
            guard storedMenuBarIconEnabled != newValue else {
                return
            }

            storedMenuBarIconEnabled = newValue
            AppPresentationPersistence.saveMenuBarIconEnabled(newValue)
            updateApplicationPresentation()
        }
    }

    private var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?
    private var menuDidEndTrackingObserver: NSObjectProtocol?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
    private var openMainWindowAction: (() -> Void)?
    private var shouldBringMainWindowToFront = false
    private var isWaitingForMenuToClose = false
    private var mainWindowLevelBeforePresentation: NSWindow.Level?

    init() {
        storedMenuBarIconEnabled = AppPresentationPersistence.isMenuBarIconEnabled()

        menuDidEndTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuDidEndTracking()
            }
        }

        applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applicationDidBecomeActive()
            }
        }
    }

    var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.isMenuBarIconEnabled ?? true
            },
            set: { [weak self] newValue in
                self?.isMenuBarIconEnabled = newValue
            }
        )
    }

    deinit {
        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }

        if let menuDidEndTrackingObserver {
            NotificationCenter.default.removeObserver(menuDidEndTrackingObserver)
        }

        if let applicationDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(applicationDidBecomeActiveObserver)
        }
    }

    func installOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else {
            bringMainWindowToFrontIfNeeded(window)
            return
        }

        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }

        mainWindow = window
        window.isReleasedWhenClosed = false
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                self?.mainWindowDidClose(window)
            }
        }

        bringMainWindowToFrontIfNeeded(window)
    }

    func openMainWindow(afterMenuCloses: Bool = false) {
        shouldBringMainWindowToFront = true
        isWaitingForMenuToClose = afterMenuCloses

        if !afterMenuCloses {
            beginMainWindowPresentation()
        }

        if afterMenuCloses {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.isWaitingForMenuToClose else {
                    return
                }

                self.isWaitingForMenuToClose = false
                self.beginMainWindowPresentation()
            }
        }
    }

    func activateApplication() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func mainWindowDidClose(_ window: NSWindow?) {
        if let window, mainWindow === window {
            restoreMainWindowLevel(window)
        }

        shouldBringMainWindowToFront = false
        isWaitingForMenuToClose = false

        guard isMenuBarIconEnabled else {
            return
        }

        hideDockIcon()
    }

    private func bringMainWindowToFrontIfNeeded(_ window: NSWindow) {
        guard shouldBringMainWindowToFront, !isWaitingForMenuToClose else {
            return
        }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.shouldBringMainWindowToFront else {
                return
            }

            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            if self.mainWindowLevelBeforePresentation == nil {
                self.mainWindowLevelBeforePresentation = window.level
            }

            window.level = .floating
            NSApplication.shared.unhide(nil)
            window.orderFrontRegardless()
            self.showDockIcon()
            self.activateMainWindowWhenReady(window, attemptsRemaining: 10)
        }
    }

    private func beginMainWindowPresentation() {
        guard shouldBringMainWindowToFront, !isWaitingForMenuToClose else {
            return
        }

        if let mainWindow {
            bringMainWindowToFrontIfNeeded(mainWindow)
            return
        }

        showDockIcon()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldBringMainWindowToFront else {
                return
            }

            self.openMainWindowAction?()
        }
    }

    private func menuDidEndTracking() {
        guard isWaitingForMenuToClose else {
            return
        }

        isWaitingForMenuToClose = false
        beginMainWindowPresentation()
    }

    private func applicationDidBecomeActive() {
        guard shouldBringMainWindowToFront,
              !isWaitingForMenuToClose,
              let mainWindow else {
            return
        }

        completeMainWindowPresentation(mainWindow)
    }

    private func verifyMainWindowIsFront(_ window: NSWindow, attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak window] in
            guard let self, let window, self.shouldBringMainWindowToFront else {
                return
            }

            window.level = .floating
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            self.requestApplicationActivation()

            if NSApplication.shared.isActive, window.isKeyWindow {
                self.completeMainWindowPresentation(window)
            } else if attemptsRemaining > 0 {
                self.verifyMainWindowIsFront(window, attemptsRemaining: attemptsRemaining - 1)
            } else {
                self.shouldBringMainWindowToFront = false
                self.restoreMainWindowLevel(window)
            }
        }
    }

    private func activateMainWindowWhenReady(_ window: NSWindow, attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
            guard let self, let window, self.shouldBringMainWindowToFront else {
                return
            }

            guard NSApplication.shared.activationPolicy() == .regular else {
                if attemptsRemaining > 0 {
                    self.showDockIcon()
                    self.activateMainWindowWhenReady(
                        window,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                } else {
                    self.shouldBringMainWindowToFront = false
                    self.restoreMainWindowLevel(window)
                }
                return
            }

            window.level = .floating
            window.orderFrontRegardless()
            self.requestApplicationActivation()
            window.makeKeyAndOrderFront(nil)
            self.verifyMainWindowIsFront(window, attemptsRemaining: 8)
        }
    }

    private func requestApplicationActivation() {
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.activate()
    }

    private func completeMainWindowPresentation(_ window: NSWindow) {
        guard shouldBringMainWindowToFront else {
            return
        }

        shouldBringMainWindowToFront = false
        showDockIcon()

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else {
                return
            }

            self.restoreMainWindowLevel(window)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func restoreMainWindowLevel(_ window: NSWindow) {
        window.level = mainWindowLevelBeforePresentation ?? .normal
        mainWindowLevelBeforePresentation = nil
    }

    private func updateApplicationPresentation() {
        if isMenuBarIconEnabled, mainWindow?.isVisible != true {
            hideDockIcon()
        } else {
            showDockIcon()
        }
    }

    private func showDockIcon() {
        guard NSApplication.shared.activationPolicy() != .regular else {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
    }

    private func hideDockIcon() {
        guard NSApplication.shared.activationPolicy() != .accessory else {
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

struct MainWindowRegistrationView: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowRegistrationNSView {
        let view = WindowRegistrationNSView()
        view.onWindowAvailable = onWindowAvailable
        return view
    }

    func updateNSView(_ nsView: WindowRegistrationNSView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
    }
}

final class WindowRegistrationNSView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }

        onWindowAvailable?(window)
    }
}
