import ActiveBreakCore
import Charts
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case json

    var id: Self { self }
    var fileExtension: String { rawValue }
    var contentType: UTType { self == .json ? .json : .commaSeparatedText }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Work threshold") {
                Stepper(
                    value: setting(\.workThreshold),
                    in: 60...86_400,
                    step: 60
                ) {
                    Text("\(Int(model.settings.workThreshold / 60)) min")
                }
            }
            LabeledContent("Dead time") {
                Stepper(
                    value: setting(\.deadTime),
                    in: 60...86_400,
                    step: 60
                ) {
                    Text("\(Int(model.settings.deadTime / 60)) min")
                }
            }
            Toggle("Notifications", isOn: setting(\.notificationsEnabled))
            Toggle("Sound", isOn: setting(\.soundEnabled))
            Toggle("Launch at login", isOn: setting(\.launchAtLogin))
            if let error = model.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let error = model.persistenceError {
                Text("Could not save state: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Text("Timing changes apply to the next work interval.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<BreakSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                var settings = model.settings
                settings[keyPath: keyPath] = $0
                model.updateSettings(settings)
            }
        )
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var period: HistoryPeriod = .daily
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var rangeEnd = Date()
    @State private var showDeleteConfirmation = false

    private var summaries: [HistorySummary] {
        HistoryAggregator.summarize(model.history, period: period)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Period", selection: $period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.rawValue.uppercased()) {
                            model.export(
                                format: format,
                                from: Calendar.current.startOfDay(for: rangeStart),
                                before: nextDayStart(rangeEnd)
                            )
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All History", systemImage: "trash")
                }
                .disabled(model.history.isEmpty)
            }

            HStack {
                DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                DatePicker("Through", selection: $rangeEnd, displayedComponents: .date)
            }

            if summaries.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "chart.bar",
                    description: Text("Completed and paused intervals appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(summaries) { summary in
                    BarMark(
                        x: .value("Date", summary.start),
                        y: .value("Active minutes", summary.activeDuration / 60)
                    )
                    .foregroundStyle(.blue)
                    LineMark(
                        x: .value("Date", summary.start),
                        y: .value("Overtime minutes", summary.overtimeDuration / 60)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                }
                .chartYAxisLabel("Minutes")

                Table(summaries) {
                    TableColumn("Period") { summary in
                        Text(summary.start, format: .dateTime.year().month().day())
                    }
                    TableColumn("Active") { summary in
                        Text(duration(summary.activeDuration))
                    }
                    TableColumn("Overtime") { summary in
                        Text(duration(summary.overtimeDuration))
                    }
                    TableColumn("Breaks") { summary in
                        Text("\(summary.breakCount)")
                    }
                    TableColumn("Average interval") { summary in
                        Text(duration(summary.averageInterval))
                    }
                }
                .frame(minHeight: 170)
            }
        }
        .padding(20)
        .confirmationDialog(
            "Delete all history?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All History", role: .destructive) {
                model.deleteAllHistory()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func nextDayStart(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinute))
    }
}
