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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    var body: some Scene {
        WindowGroup {
            ContentView(downloadStore: downloadStore)
                .onAppear {
                    appDelegate.stopRuntime = {
                        downloadStore.stopRuntime()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            FileMenuCommands()
        }
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
