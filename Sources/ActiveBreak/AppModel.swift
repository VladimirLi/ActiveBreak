import ActiveBreakCore
import AppKit
import CoreGraphics
import Foundation
import OSLog
import ServiceManagement
@preconcurrency import UserNotifications

@MainActor
final class StatusBarModel: ObservableObject {
    @Published private(set) var text: String
    @Published private(set) var isOverdue: Bool

    init(text: String, isOverdue: Bool) {
        self.text = text
        self.isOverdue = isOverdue
    }

    func update(text: String, isOverdue: Bool) {
        guard self.text != text || self.isOverdue != isOverdue else { return }
        self.text = text
        self.isOverdue = isOverdue
    }
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published private(set) var data: PersistedData
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var persistenceError: String?
    let status: StatusBarModel

    private let store: HistoryStore
    private var reducer: TimerReducer
    private var timer: Timer?
    private var activityDetector = IdleActivityDetector()
    private var persistenceBlocked: Bool
    private var persistenceCadence: PersistenceCadence
    private var now: Date

    override init() {
        let launchNow = Date()
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
        self.persistenceCadence = PersistenceCadence(lastSavedAt: loaded.savedAt)
        self.now = launchNow
        let remaining = self.reducer.remaining(at: launchNow, defaultSettings: loaded.settings)
        self.status = StatusBarModel(
            text: self.reducer.state.mode == .paused
                ? "Paused"
                : CountdownFormatter.string(seconds: remaining),
            isOverdue: self.reducer.state.mode == .active && remaining <= 0
        )
        super.init()

        log(
            DiagnosticEvent(
                category: .persistence,
                event: "load",
                reason: loadError == nil ? nil : "decode-or-read",
                outcome: loadError == nil ? "success" : "failure"
            ),
            with: Logs.persistence,
            level: loadError == nil ? .info : .error
        )
        let before = reducer.state.mode
        let effects = reducer.restore(
            savedAt: loaded.savedAt,
            savedSystemUptime: loaded.savedSystemUptime,
            now: now,
            systemUptime: ProcessInfo.processInfo.systemUptime
        )
        let changed = apply(effects)
        log(
            DiagnosticEvent(
                category: .lifecycle,
                event: "relaunch",
                reason: "restore",
                stateBefore: before,
                stateAfter: reducer.state.mode,
                effectKinds: effects.map(\.diagnosticKind),
                recordID: effects.compactMap(\.recordID).first,
                outcome: changed ? "updated" : "unchanged"
            ),
            with: Logs.lifecycle
        )
        updateStatus()
        save(changed: changed, force: true)
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
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
        let changed = processHIDActivity(context: "poll")
        updateStatus()
        save(changed: changed)
    }

    @objc private func willSleep() {
        now = Date()
        let before = reducer.state.mode
        let changed = processHIDActivity(context: "sleep")
        log(
            DiagnosticEvent(
                category: .lifecycle,
                event: "sleep",
                stateBefore: before,
                stateAfter: reducer.state.mode,
                outcome: "flushed"
            ),
            with: Logs.lifecycle
        )
        save(changed: changed, force: true)
    }

    @objc private func didWake() {
        now = Date()
        activityDetector = IdleActivityDetector()
        let before = reducer.state.mode
        let effects = reducer.wake(at: now)
        let changed = apply(effects)
        log(
            DiagnosticEvent(
                category: .lifecycle,
                event: "wake",
                reason: "wake-closes-active",
                stateBefore: before,
                stateAfter: reducer.state.mode,
                effectKinds: effects.map(\.diagnosticKind),
                recordID: effects.compactMap(\.recordID).first,
                outcome: changed ? "updated" : "unchanged"
            ),
            with: Logs.lifecycle
        )
        updateStatus()
        save(changed: changed, force: true)
    }

    func togglePause() {
        now = Date()
        if isPaused {
            reducer.resume()
            activityDetector.baseline(at: now)
        } else {
            _ = apply(reducer.pause(at: now))
        }
        let changed = syncTimerState()
        updateStatus()
        log(
            DiagnosticEvent(
                category: .lifecycle,
                event: isPaused ? "pause" : "resume",
                stateAfter: reducer.state.mode,
                outcome: "saved"
            ),
            with: Logs.lifecycle
        )
        save(changed: changed, force: true)
    }

    func updateSettings(_ settings: BreakSettings) {
        let loginChanged = settings.launchAtLogin != data.settings.launchAtLogin
        data.settings = settings
        if loginChanged {
            configureLaunchAtLogin(enabled: settings.launchAtLogin)
        }
        save(changed: true, force: true)
    }

    func deleteAllHistory() {
        data.history.removeAll()
        save(changed: true, force: true)
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
        let before = reducer.state.mode
        let changed = processHIDActivity(context: "quit")
        log(
            DiagnosticEvent(
                category: .lifecycle,
                event: "quit",
                stateBefore: before,
                stateAfter: reducer.state.mode,
                outcome: "flushed"
            ),
            with: Logs.lifecycle
        )
        save(changed: changed, force: true)
    }

    @discardableResult
    private func apply(_ effects: [TimerEffect]) -> Bool {
        let result = TimerEffectProcessor.apply(effects, state: reducer.state, to: data)
        for effect in result.forwardedEffects {
            switch effect {
            case let .notify(sound):
                sendNotification(sound: sound)
            case .playSound:
                NSSound.beep()
            case .log:
                break
            }
        }
        if result.data != data {
            data = result.data
        }
        return result.historyChanged || result.stateChanged
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
            log(
                DiagnosticEvent(
                    category: .loginItem,
                    event: "configure",
                    outcome: "disabled-by-environment"
                ),
                with: Logs.loginItem
            )
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
            log(
                DiagnosticEvent(
                    category: .loginItem,
                    event: "configure",
                    outcome: launchAtLoginError == nil ? "success" : "requires-user-action"
                ),
                with: Logs.loginItem
            )
        } catch {
            launchAtLoginError = error.localizedDescription
            log(
                DiagnosticEvent(
                    category: .loginItem,
                    event: "configure",
                    reason: String(reflecting: type(of: error)),
                    outcome: "failure"
                ),
                with: Logs.loginItem,
                level: .error
            )
        }
    }

    private func syncTimerState() -> Bool {
        guard data.timer != reducer.state else { return false }
        data.timer = reducer.state
        return true
    }

    @discardableResult
    private func processHIDActivity(context: String) -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        let sample = PermissionlessHIDPolicy.processSample(
            now: now,
            idleSeconds: idle,
            detector: &activityDetector,
            reducer: &reducer,
            settings: data.settings
        )
        let changed = apply(sample.effects)
        let interval = reducer.state.interval
        let closureReason: String
        if sample.effects.contains(where: { $0.recordID != nil }) {
            closureReason = sample.inferredEventAt == nil
                ? "dead-time"
                : "activity-after-dead-time"
        } else {
            closureReason = context
        }
        log(
            DiagnosticEvent(
                category: .timer,
                event: "sample",
                reason: closureReason,
                stateBefore: sample.stateBefore.mode,
                stateAfter: sample.stateAfter.mode,
                idleSeconds: idle,
                inferredEventAt: sample.inferredEventAt,
                threshold: interval?.settings.workThreshold ?? data.settings.workThreshold,
                deadTime: interval?.settings.deadTime ?? data.settings.deadTime,
                validated: interval?.validatedActive ?? 0,
                provisional: interval?.provisionalActive(at: now) ?? 0,
                overtime: interval?.overtime ?? 0,
                effectKinds: sample.effects.map(\.diagnosticKind),
                recordID: sample.effects.compactMap(\.recordID).first,
                outcome: changed ? "updated" : "unchanged"
            ),
            with: Logs.timer,
            level: sample.effects.isEmpty ? .debug : .info
        )
        return changed
    }

    private func updateStatus() {
        status.update(text: statusText, isOverdue: isOverdue)
    }

    private func save(changed: Bool, force: Bool = false) {
        guard !persistenceBlocked else { return }
        guard persistenceCadence.shouldSave(at: now, changed: changed, force: force) else {
            return
        }
        var snapshot = data
        snapshot.savedAt = now
        snapshot.savedSystemUptime = ProcessInfo.processInfo.systemUptime
        do {
            try store.save(snapshot)
            persistenceError = nil
            log(
                DiagnosticEvent(
                    category: .persistence,
                    event: "save",
                    stateAfter: reducer.state.mode,
                    outcome: force ? "forced-success" : "success"
                ),
                with: Logs.persistence
            )
        } catch {
            persistenceCadence.markSaveFailed()
            persistenceError = error.localizedDescription
            log(
                DiagnosticEvent(
                    category: .persistence,
                    event: "save",
                    reason: String(reflecting: type(of: error)),
                    stateAfter: reducer.state.mode,
                    outcome: "failure"
                ),
                with: Logs.persistence,
                level: .error
            )
        }
    }

    private func log(
        _ event: DiagnosticEvent,
        with logger: Logger,
        level: OSLogType = .info
    ) {
        logger.log(level: level, "\(event.message, privacy: .public)")
    }
}

private enum Logs {
    private static let subsystem = "com.vladimirli.ActiveBreak"
    static let timer = Logger(subsystem: subsystem, category: "timer")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let loginItem = Logger(subsystem: subsystem, category: "login-item")
}

private extension TimerEffect {
    var recordID: UUID? {
        if case let .log(record) = self { return record.id }
        return nil
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
