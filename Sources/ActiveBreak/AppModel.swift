import ActiveBreakCore
import AppKit
import CoreGraphics
import Foundation
import ServiceManagement
@preconcurrency import UserNotifications

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published private(set) var data: PersistedData
    @Published private(set) var now = Date()
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var persistenceError: String?

    private let store: HistoryStore
    private var reducer: TimerReducer
    private var timer: Timer?
    private var activityDetector = IdleActivityDetector()
    private var persistenceBlocked: Bool

    override init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let stateURL = StateFileLocator.url(
            environment: ProcessInfo.processInfo.environment,
            applicationSupport: applicationSupport
        )
        let store = HistoryStore(url: stateURL)
        let loaded: PersistedData
        let loadError: String?
        do {
            loaded = try store.load()
            loadError = nil
        } catch {
            loaded = PersistedData()
            loadError = error.localizedDescription
        }
        self.store = store
        self.data = loaded
        self.reducer = TimerReducer(state: loaded.timer)
        self.persistenceError = loadError
        self.persistenceBlocked = loadError != nil
        super.init()

        apply(reducer.restore(
            savedAt: loaded.savedAt,
            savedSystemUptime: loaded.savedSystemUptime,
            now: now,
            systemUptime: ProcessInfo.processInfo.systemUptime
        ))
        save()
        configureLaunchAtLogin(enabled: data.settings.launchAtLogin)
        timer = Timer.scheduledTimer(
            timeInterval: PermissionlessHIDPolicy.pollInterval,
            target: self,
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    var settings: BreakSettings { data.settings }
    var history: [HistoryRecord] { data.history }
    var isPaused: Bool { reducer.state.mode == .paused }
    var remaining: TimeInterval { reducer.remaining(at: now, defaultSettings: data.settings) }
    var isOverdue: Bool { reducer.state.mode == .active && remaining <= 0 }
    var statusText: String {
        isPaused ? "Paused" : CountdownFormatter.string(seconds: remaining)
    }

    @objc private func poll() {
        now = Date()
        processHIDActivity()
        save()
    }

    @objc private func didWake() {
        now = Date()
        activityDetector = IdleActivityDetector()
        apply(reducer.wake(at: now))
        save()
    }

    func togglePause() {
        now = Date()
        if isPaused {
            reducer.resume()
            activityDetector.baseline(at: now)
        } else {
            apply(reducer.pause(at: now))
        }
        syncAndSave()
    }

    func updateSettings(_ settings: BreakSettings) {
        let loginChanged = settings.launchAtLogin != data.settings.launchAtLogin
        data.settings = settings
        if loginChanged {
            configureLaunchAtLogin(enabled: settings.launchAtLogin)
        }
        save()
    }

    func deleteAllHistory() {
        data.history.removeAll()
        save()
    }

    func export(format: ExportFormat, from start: Date, before end: Date) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "ActiveBreak-\(format.rawValue).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bytes = try format == .json
                ? HistoryExporter.json(data.history, from: start, before: end)
                : HistoryExporter.csv(data.history, from: start, before: end)
            try bytes.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func prepareToQuit() {
        now = Date()
        processHIDActivity()
        save()
    }

    private func apply(_ effects: [TimerEffect]) {
        for effect in effects {
            switch effect {
            case let .log(record):
                data.history.append(record)
            case let .notify(sound):
                sendNotification(sound: sound)
            case .playSound:
                NSSound.beep()
            }
        }
        data.timer = reducer.state
    }

    private func sendNotification(sound: Bool) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Time for a break"
            content.body = "You reached your ActiveBreak work threshold."
            content.sound = sound ? .default : nil
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func configureLaunchAtLogin(enabled: Bool) {
        guard ProcessInfo.processInfo.environment["ACTIVEBREAK_DISABLE_LOGIN_ITEM_MUTATION"] != "1" else {
            return
        }
        let service = SMAppService.mainApp
        do {
            switch LaunchAtLoginPolicy.action(enabled: enabled, status: service.status.activeBreak) {
            case .register:
                try service.register()
            case .unregister:
                try service.unregister()
            case .none:
                break
            }
            launchAtLoginError = LaunchAtLoginPolicy.errorMessage(
                enabled: enabled,
                status: service.status.activeBreak
            )
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    private func syncAndSave() {
        data.timer = reducer.state
        save()
    }

    private func processHIDActivity() {
        let idle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        apply(PermissionlessHIDPolicy.processSample(
            now: now,
            idleSeconds: idle,
            detector: &activityDetector,
            reducer: &reducer,
            settings: data.settings
        ))
    }

    private func save() {
        guard !persistenceBlocked else { return }
        data.savedAt = now
        data.savedSystemUptime = ProcessInfo.processInfo.systemUptime
        do {
            try store.save(data)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

private extension SMAppService.Status {
    var activeBreak: LaunchAtLoginStatus {
        switch self {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }
}
