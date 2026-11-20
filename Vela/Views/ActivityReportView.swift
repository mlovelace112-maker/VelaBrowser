import Charts
import SwiftUI

/// History ▸ Weekly Report (⌥⌘R): your last 7 days in Vela. Time online,
/// the sites you spent it on, your top searches, what the shield blocked,
/// and (if you ask) a short summary from Claude.
struct ActivityReportView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weekEnding = Date()
    @State private var summary = ""
    @State private var isWriting = false
    @State private var summaryError: String?
    @State private var hoveredDay: Date?

    var body: some View {
        let report = ActivitySummary(log: store.activity, endingOn: weekEnding)
        let previous = ActivitySummary(log: store.activity, endingOn: weekEnding.addingTimeInterval(-7 * 86_400))

        VStack(spacing: 0) {
            header(report)
            Rectangle().fill(Nightglass.stroke).frame(height: 1)
            if !store.activity.isEnabled {
                ContentUnavailableView("The activity report is off", systemImage: "chart.bar",
                                       description: Text("Turn it on in Settings ▸ Privacy ▸ Activity report."))
            } else if report.totalMinutes < 1 {
                ContentUnavailableView("Nothing to show yet", systemImage: "chart.bar",
                                       description: Text("Vela adds up your browsing time as you go. Check back in a day or two."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        tiles(report, previous: previous)
                        dailyChart(report)
                        HStack(alignment: .top, spacing: 22) {
                            topSites(report)
                            topSearches(report)
                        }
                        claudeSection(report)
                        Text("Counted only on your Mac. Private tabs are never included. Time counts while you're using a tab (or a video is playing).")
                            .font(.system(size: 11))
                            .foregroundStyle(Nightglass.mutedText)
                    }
                    .padding(22)
                }
            }
        }
        .frame(width: 680, height: 720)
        .background(Nightglass.background)
        .onChange(of: weekEnding) {
            summary = ""
            summaryError = nil
        }
    }

    // MARK: Parts

    private func header(_ report: ActivitySummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your week in Vela").font(.system(size: 18, weight: .semibold))
                if let first = report.dates.first, let last = report.dates.last {
                    Text("\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 12))
                        .foregroundStyle(Nightglass.mutedText)
                }
            }
            Spacer()
            Button { weekEnding = weekEnding.addingTimeInterval(-7 * 86_400) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Previous week")
            Button { weekEnding = min(Date(), weekEnding.addingTimeInterval(7 * 86_400)) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(IconButtonStyle(size: 26))
                .disabled(Calendar.current.isDateInToday(weekEnding))
                .help("Next week")
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
    }

    private func tiles(_ report: ActivitySummary, previous: ActivitySummary) -> some View {
        let change: String? = previous.totalMinutes >= 10
            ? {
                let percent = Int(((report.totalMinutes - previous.totalMinutes) / previous.totalMinutes * 100).rounded())
                return percent == 0 ? "Same as the week before" : "\(percent > 0 ? "↑" : "↓") \(abs(percent))% vs the week before"
            }()
            : nil
        return HStack(spacing: 10) {
            ReportTile(value: ActivitySummary.format(minutes: report.totalMinutes), label: "Time online", note: change)
            ReportTile(value: ActivitySummary.format(minutes: report.totalMinutes / Double(max(report.activeDays, 1))),
                       label: "Per day you browsed", note: "\(report.activeDays) of 7 days")
            ReportTile(value: report.trackersBlocked.formatted(), label: "Trackers blocked",
                       note: report.popupsBlocked > 0 ? "and \(report.popupsBlocked.formatted()) pop-ups" : nil)
            ReportTile(value: report.pagesVisited.formatted(), label: "Pages visited", note: nil)
        }
    }

    private func dailyChart(_ report: ActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time online each day").font(.system(size: 13, weight: .semibold))
            Chart {
                ForEach(report.minutesByDay, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(Nightglass.accent.opacity(hoveredDay == nil || isSameDay(hoveredDay, day.date) ? 1 : 0.45))
                    .cornerRadius(4)
                }
                if let hoveredDay, let day = report.minutesByDay.first(where: { isSameDay($0.date, hoveredDay) }) {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 1) {
                                Text(day.date.formatted(.dateTime.weekday(.wide)))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Nightglass.mutedText)
                                Text(ActivitySummary.format(minutes: day.minutes))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Nightglass.text)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassPanel(cornerRadius: 8)
                        }
                }
            }
            .chartXSelection(value: $hoveredDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .foregroundStyle(Nightglass.mutedText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Nightglass.stroke)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m")
                                .foregroundStyle(Nightglass.mutedText)
                        }
                    }
                }
            }
            .frame(height: 170)
        }
    }

    private func topSites(_ report: ActivitySummary) -> some View {
        let most = report.topSites.first?.minutes ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Top sites").font(.system(size: 13, weight: .semibold))
            ForEach(report.topSites, id: \.site) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        FaviconView(url: URL(string: "https://\(item.site)"), size: 13)
                        Text(item.site).font(.system(size: 12.5)).foregroundStyle(Nightglass.text).lineLimit(1)
                        Spacer()
                        Text(ActivitySummary.format(minutes: item.minutes))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Nightglass.secondaryText)
                            .monospacedDigit()
                    }
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Nightglass.accent)
                            .frame(width: max(3, geometry.size.width * item.minutes / most))
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func topSearches(_ report: ActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top searches").font(.system(size: 13, weight: .semibold))
            if report.topSearches.isEmpty {
                Text("No searches this week.").font(.system(size: 12)).foregroundStyle(Nightglass.mutedText)
            }
            ForEach(report.topSearches, id: \.query) { item in
                HStack {
                    Text(item.query).font(.system(size: 12.5)).foregroundStyle(Nightglass.text).lineLimit(1)
                    Spacer()
                    if item.count > 1 {
                        Text("×\(item.count)").font(.system(size: 11.5)).foregroundStyle(Nightglass.mutedText).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    store.navigateInUsefulTab(item.query)
                }
                .help("Search again")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func claudeSection(_ report: ActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Claude's take", systemImage: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nightglass.claude)
                Spacer()
                Button(summary.isEmpty ? "Write My Summary" : "Write It Again") { writeSummary(report) }
                    .disabled(isWriting)
            }
            if let summaryError {
                Label(summaryError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.caution)
            } else if !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isWriting {
                ProgressView().controlSize(.small)
            } else {
                Text("Sends Claude the totals on this page (sites, times and searches), not the pages themselves.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
    }

    private func writeSummary(_ report: ActivitySummary) {
        summary = ""
        summaryError = nil
        isWriting = true
        let request = ClaudeRequest(
            model: .haiku,
            system: """
            You write a short, friendly weekly recap of someone's web browsing from their browser's own \
            numbers. Two short paragraphs: what the week looked like (where the time went, patterns, what \
            they were curious about based on searches), then 2 or 3 gentle, practical suggestions (for \
            example focus mode for a site that took a lot of time). No judgment, no headings, no lists of \
            raw numbers they can already see. Under 160 words.
            """,
            messages: [["role": "user", "content": report.promptText()]],
            maxTokens: 800,
            effort: "low"
        )
        Task {
            do {
                _ = try await ClaudeClient.stream(request) { piece in summary += piece }
            } catch {
                summaryError = error.localizedDescription
            }
            isWriting = false
        }
    }

    private func isSameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}

private struct ReportTile: View {
    let value: String
    let label: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Nightglass.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Nightglass.secondaryText)
            Text(note ?? " ").font(.system(size: 10.5)).foregroundStyle(Nightglass.mutedText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Settings ▸ Privacy ▸ Activity report.
struct ActivitySettingsSection: View {
    @Environment(BrowserStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        @Bindable var activity = store.activity
        Section {
            Toggle(isOn: $activity.isEnabled) {
                Text("Keep a weekly activity report")
                Text("Adds up time per site, searches and blocked trackers, only on your Mac. Private tabs are never counted.")
            }
            HStack {
                Button("Show Weekly Report") { store.isActivityReportVisible = true }
                Spacer()
                Button("Clear Activity…", role: .destructive) { confirmClear = true }
            }
        } header: {
            Text("Activity report")
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
        .confirmationDialog("Clear all activity?", isPresented: $confirmClear) {
            Button("Clear Activity", role: .destructive) { store.activity.clear() }
        } message: {
            Text("This deletes the time, searches and counts behind the weekly report. Your history stays.")
        }
    }
}

/// Hosts Vela's report-style sheets, so ContentView stays small.
struct ExtraSheets: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: $store.isActivityReportVisible) {
                ActivityReportView().environment(store)
            }
            .background {
                Color.clear.sheet(isPresented: $store.isPageFinderVisible) {
                    PageFinderView().environment(store)
                }
            }
            .background {
                Color.clear.sheet(item: $store.pageTool) { tool in
                    PageToolSheet(initial: tool).environment(store)
                }
            }
            .background {
                Color.clear.sheet(isPresented: $store.isHighlightsVisible) {
                    HighlightsView().environment(store)
                }
            }
            .background {
                Color.clear.sheet(item: Binding(
                    get: { store.editingHighlightID.map(EditingHighlight.init) },
                    set: { store.editingHighlightID = $0?.id }
                )) { editing in
                    HighlightNoteSheet(id: editing.id).environment(store)
                }
            }
    }
}
