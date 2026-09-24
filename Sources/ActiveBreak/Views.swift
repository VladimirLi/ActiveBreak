import ActiveBreakCore
import Foundation
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
    @State private var selectedRange = DashboardRange.default
    @State private var visibleEndDate = Calendar.current.startOfDay(for: .now)
    @State private var selectedSegment: DashboardSegment?
    @State private var showDeleteConfirmation = false

    private var dateRange: DashboardDateRange {
        DashboardDateRange(
            range: selectedRange,
            endingAt: visibleEndDate,
            calendar: .current
        )
    }

    private var dashboard: DashboardProjection {
        DashboardProjection.make(
            records: model.history,
            currentInterval: model.currentInterval,
            range: dateRange,
            calendar: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(dateRange.start, format: .dateTime.month(.abbreviated).day())
                        Text("-")
                        Text(
                            dateRange.end.addingTimeInterval(-1),
                            format: .dateTime.month(.abbreviated).day().year()
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(DashboardRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)

                HStack(spacing: 4) {
                    Button {
                        visibleEndDate = dateRange.shifted(
                            by: -selectedRange.dayCount,
                            calendar: .current
                        ).end.addingTimeInterval(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Previous range")

                    Button("Today") {
                        visibleEndDate = Calendar.current.startOfDay(for: .now)
                    }

                    Button {
                        visibleEndDate = dateRange.shifted(
                            by: selectedRange.dayCount,
                            calendar: .current
                        ).end.addingTimeInterval(-1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help("Next range")
                    .disabled(!dateRange.canNavigateForward(calendar: .current))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 0) {
                MetricView(title: "Active time", value: duration(dashboard.activeDuration))
                Divider()
                MetricView(title: "Overtime", value: duration(dashboard.overtimeDuration))
                Divider()
                MetricView(
                    title: "Longest completed",
                    value: dashboard.longestStretch.map(duration) ?? "-"
                )
                Divider()
                MetricView(title: "Most active", value: mostActiveHour(dashboard.mostActiveHour))
            }
            .frame(height: 72)

            Divider()

            if dashboard.days.allSatisfy({ $0.segments.isEmpty }) {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "clock",
                    description: Text("Completed work in this date range will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        LegendItem(color: .blue, title: "Active work")
                        LegendItem(color: .red, title: "Overtime")
                        LegendItem(color: .secondary, title: "Ongoing", outlined: true)
                        Label("Compressed empty hours", systemImage: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    ActivityTimelineView(
                        dashboard: dashboard,
                        selectedSegment: $selectedSegment
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.rawValue.uppercased()) {
                            model.export(
                                format: format,
                                from: dateRange.start,
                                before: dateRange.end
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
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 760, minHeight: 650)
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

    private func mostActiveHour(_ hour: Int?) -> String {
        guard let hour else { return "-" }
        return String(format: "%02d:00-%02d:00", hour, (hour + 1) % 24)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinute))
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String
    var outlined = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 2)
                .fill(outlined ? Color.clear : color)
                .stroke(
                    outlined ? color : Color.clear,
                    style: StrokeStyle(lineWidth: 1, dash: outlined ? [2, 2] : [])
                )
                .frame(width: 9, height: 9)
        }
        .foregroundStyle(.secondary)
    }
}

private struct ActivityTimelineView: View {
    let dashboard: DashboardProjection
    @Binding var selectedSegment: DashboardSegment?

    private let timelineHeight: CGFloat = 350

    private var dayWidth: CGFloat {
        DashboardLayout.dayWidth(for: dashboard.range.range)
    }

    private var tickOffsets: [Int] {
        let first = Int(ceil(dashboard.scale.expandedStartOffset / 7_200) * 7_200)
        let last = Int(floor(dashboard.scale.expandedEndOffset / 7_200) * 7_200)
        guard first <= last else { return [] }
        return Array(stride(from: first, through: last, by: 7_200))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 42)
                Divider()
                TimelineAxis(
                    scale: dashboard.scale,
                    tickOffsets: tickOffsets,
                    height: timelineHeight
                )
                .frame(height: timelineHeight)
            }
            .frame(width: DashboardLayout.axisWidth)

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(dashboard.days) { day in
                            VStack(spacing: 1) {
                                Text(day.date, format: .dateTime.weekday(.abbreviated))
                                    .font(.caption.weight(.semibold))
                                HStack(spacing: 3) {
                                    Text(day.date, format: .dateTime.day())
                                    if abs(day.duration - 86_400) > 1 {
                                        Text("\(Int(day.duration / 3_600))h")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(width: dayWidth, height: 42)
                            .overlay(alignment: .leading) { Divider() }
                        }
                    }

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(dashboard.days) { day in
                            TimelineDayColumn(
                                day: day,
                                tickOffsets: tickOffsets,
                                width: dayWidth,
                                height: timelineHeight,
                                selectedSegment: $selectedSegment
                            )
                        }
                    }
                }
                .frame(width: DashboardLayout.scrollContentWidth(for: dashboard.range.range))
            }
        }
        .overlay {
            Rectangle()
                .stroke(.separator, lineWidth: 1)
        }
        .popover(item: $selectedSegment, arrowEdge: .trailing) { segment in
            ActivityPopover(segment: segment)
        }
    }
}

private struct TimelineAxis: View {
    let scale: DashboardTimeScale
    let tickOffsets: [Int]
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(tickOffsets, id: \.self) { offset in
                Text(String(format: "%02d:00", offset / 3_600))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .position(
                        x: 23,
                        y: scale.position(for: Double(offset)) * height
                    )
            }
            ForEach(scale.bands.filter(\.isCompressed), id: \.startOffset) { band in
                Image(systemName: "ellipsis")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .position(
                        x: 26,
                        y: (
                            scale.position(for: band.startOffset)
                                + scale.position(for: band.endOffset)
                        ) * height / 2
                    )
            }
        }
    }
}

private struct TimelineDayColumn: View {
    let day: DashboardDay
    let tickOffsets: [Int]
    let width: CGFloat
    let height: CGFloat
    @Binding var selectedSegment: DashboardSegment?

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.015))

            ForEach(tickOffsets, id: \.self) { offset in
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 1)
                    .position(
                        x: width / 2,
                        y: day.scale.position(for: Double(offset)) * height
                    )
            }

            ForEach(day.scale.bands.filter(\.isCompressed), id: \.startOffset) { band in
                let top = day.scale.position(for: band.startOffset)
                let bottom = day.scale.position(for: band.endOffset)
                Rectangle()
                    .fill(Color.secondary.opacity(0.07))
                    .overlay {
                        Rectangle()
                            .stroke(
                                Color.secondary.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                    }
                    .frame(height: max(2, (bottom - top) * height))
                    .position(
                        x: width / 2,
                        y: (top + bottom) * height / 2
                    )
            }

            ForEach(day.segments) { segment in
                let frame = DashboardLayout.segmentFrame(
                    segment,
                    scale: day.scale,
                    height: height
                )
                Button {
                    selectedSegment = segment
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.isOvertime ? Color.red : Color.blue)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(
                                    Color.primary.opacity(segment.isOngoing ? 0.7 : 0.18),
                                    style: StrokeStyle(
                                        lineWidth: segment.isOngoing ? 1.5 : 1,
                                        dash: segment.isOngoing ? [3, 2] : []
                                    )
                                )
                        }
                }
                .buttonStyle(.plain)
                .frame(
                    width: max(18, width - 20),
                    height: max(5, frame.height)
                )
                .position(
                    x: width / 2,
                    y: frame.y + frame.height / 2
                )
                .help(segment.isOngoing ? "\(segment.typeLabel), ongoing" : segment.typeLabel)
                .accessibilityLabel(
                    DashboardPresentation.accessibilityLabel(for: segment, calendar: .current)
                )
                .accessibilityValue(
                    DashboardPresentation.accessibilityValue(for: segment)
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(alignment: .leading) { Divider() }
    }
}

private struct ActivityPopover: View {
    let segment: DashboardSegment

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Start").foregroundStyle(.secondary)
                Text(segment.start, format: .dateTime.weekday(.abbreviated).month().day().hour().minute().second())
            }
            GridRow {
                Text("End").foregroundStyle(.secondary)
                Text(segment.end, format: .dateTime.weekday(.abbreviated).month().day().hour().minute().second())
            }
            GridRow {
                Text("Duration").foregroundStyle(.secondary)
                Text(Duration.seconds(segment.duration).formatted(.time(pattern: .hourMinuteSecond)))
                    .monospacedDigit()
            }
            GridRow {
                Text("Type").foregroundStyle(.secondary)
                Label(
                    segment.typeLabel,
                    systemImage: segment.isOvertime ? "exclamationmark.circle.fill" : "clock.fill"
                )
                .foregroundStyle(segment.isOvertime ? .red : .blue)
            }
            GridRow {
                Text("Status").foregroundStyle(.secondary)
                Text(segment.isOngoing ? "Ongoing" : "Completed")
            }
        }
        .font(.callout)
        .padding(14)
    }
}
