import ActiveBreakCore
import AppKit
import SwiftUI

@main
struct ActiveBreakApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            StatusBarCountdown(status: model.status)
        }
        .menuBarExtraStyle(.menu)

        Window("Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
        .defaultSize(width: 1_300, height: 760)

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct StatusBarCountdown: View {
    @ObservedObject var status: StatusBarModel

    var body: some View {
        Text(status.text)
            .monospacedDigit()
            .foregroundStyle(status.isOverdue ? .red : .primary)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            model.togglePause()
        } label: {
            Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
        }

        Button {
            openSettings()
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings", systemImage: "gear")
        }

        Button {
            openWindow(id: "dashboard")
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            Label("Dashboard", systemImage: "chart.bar")
        }

        Divider()

        Button {
            model.prepareToQuit()
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}
