//
//  VeloraApp.swift
//  Velora
//
//  Created by Morton Li on 2026/5/16.
//

import SwiftUI
import AppKit

@MainActor
private final class VeloraAppDelegate: NSObject, NSApplicationDelegate {
    var stopRuntime: (() -> Void)?
    var reopenApplication: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenApplication?()
        }

        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopRuntime?()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRuntime?()
    }
}

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(VeloraAppDelegate.self) private var appDelegate
    @StateObject private var downloadStore = DownloadStore()
    @StateObject private var appUpdateChecker = AppUpdateChecker()
    @StateObject private var presentationController = AppPresentationController()

    var body: some Scene {
        Window("Velora", id: "main") {
            MainWindowContent(
                downloadStore: downloadStore,
                appUpdateChecker: appUpdateChecker,
                presentationController: presentationController,
                appDelegate: appDelegate
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            FileMenuCommands()
        }

        Settings {
            SettingsView(presentationController: presentationController) {
                try await downloadStore.restartRuntime()
            }
        }

        MenuBarExtra(isInserted: presentationController.menuBarIconBinding) {
            MenuBarMenu(presentationController: presentationController)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Velora")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MainWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var downloadStore: DownloadStore
    @ObservedObject var appUpdateChecker: AppUpdateChecker
    let presentationController: AppPresentationController
    let appDelegate: VeloraAppDelegate

    var body: some View {
        ContentView(downloadStore: downloadStore, appUpdateChecker: appUpdateChecker)
            .background {
                MainWindowRegistrationView { window in
                    presentationController.registerMainWindow(window)
                }
                .frame(width: 0, height: 0)
            }
            .onAppear {
                presentationController.installOpenMainWindowAction {
                    openWindow(id: "main")
                }

                appDelegate.stopRuntime = {
                    downloadStore.stopRuntime()
                }

                appDelegate.reopenApplication = {
                    presentationController.openMainWindow()
                }
            }
    }
}

private struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var presentationController: AppPresentationController

    var body: some View {
        Button {
            presentationController.openMainWindow(afterMenuCloses: true)
        } label: {
            Label("Open Velora", systemImage: "macwindow")
        }

        Button {
            presentationController.activateApplication()
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Velora", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}

private struct FileMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
    }
}
