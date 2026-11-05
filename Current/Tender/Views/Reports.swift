import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ReportView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LedgerStore.self) private var store
    @State private var weekly = false
    @State private var monthOffset = 0
    @State private var selectedDay: Date?
    @State private var export = false
    @State private var document = ExportDocument(data: Data())
    private var calendar: Calendar { .current }
    private var month: Date { calendar.date(byAdding: .month, value: monthOffset, to: Date())! }
    private var interval: DateInterval { weekly ? DateInterval(start: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!, end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!) : store.ledger.month(at: month) }
    private var days: [Date] { let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0; return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) } }
    var body: some View {
        let summary = SpendingSummary(entries: store.ledger.spendingEntries(in: interval))
        PaperScreen {
            SectionHeading(title: "See the bigger picture.", subtitle: "Small decisions. A clearer month.")
            Picker("Summary period", selection: $weekly) { Text("Monthly").tag(false); Text("Last 7 days").tag(true) }.pickerStyle(.segmented)
            if !weekly {
                HStack {
                    Button { monthOffset -= 1; selectedDay = nil } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
                    Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                    Button { monthOffset += 1; selectedDay = nil } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(monthOffset >= 0).accessibilityLabel("Next month")
                }
            }
            PaperCard {
                Text("TOTAL SPENT").font(.system(.caption, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
                MoneyText(amount: summary.total).font(.system(.largeTitle, design: .serif)).monospacedDigit().accessibilityIdentifier("activity-total-spent")
                Chart(days, id: \.self) { day in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("USD", Double(summary.days[day] ?? 0) / 100)).foregroundStyle(Ink.accent).cornerRadius(3)
                }.chartXAxis { AxisMarks(values: .stride(by: .day, count: weekly ? 1 : 7)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                    .frame(height: 160).accessibilityLabel("Daily spending in US dollars")
                Text("Daily spending · USD").font(.caption).foregroundStyle(Ink.muted)
            }
            if !weekly { heatmap(summary) }
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Where it went")
                ForEach(store.ledger.categories.sorted { (summary.categories[$0.id] ?? 0) > (summary.categories[$1.id] ?? 0) }) { category in
                    let value = summary.categories[category.id] ?? 0
                    NavigationLink { CategoryReviewView(categoryID: category.id, interval: interval) } label: {
                    HStack(spacing: 12) { CategoryIcon(symbol: category.symbol); VStack(alignment: .leading, spacing: 6) { Text(category.name).font(.subheadline); ProgressView(value: Double(value), total: Double(max(1, summary.total))).tint(Ink.green) }; Spacer(); Text(Money.format(value)).font(.subheadline.weight(.semibold)).monospacedDigit() }
                    }.buttonStyle(.plain).frame(minHeight: 44)
                }
            }
            if summary.unassigned > 0 {
                NavigationLink { MonthlyPaymentsReview(initialMonth: interval.start) } label: { AmountRow(label: "Needs an envelope", amount: summary.unassigned) }.accessibilityIdentifier("activity-unassigned")
            }
            NavigationLink { MonthlyPaymentsReview(initialMonth: interval.start) } label: { Label("Review payments in this month", systemImage: "list.bullet.rectangle") }.accessibilityIdentifier("activity-review-payments")
            PaperCard {
                Label("A note from your ledger", systemImage: "text.book.closed").font(.headline)
                Text(insight(summary)).font(.subheadline).foregroundStyle(Ink.muted)
                Text("Posted bank purchases and recorded expenses").font(.caption).foregroundStyle(Ink.muted)
            }
            Button { document = ExportDocument(data: Data(reportText(summary).utf8)); export = true } label: { Label("Export This Summary", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton())
            Text("Save to iCloud Drive in Files, or share the exported text with Claude or ChatGPT for analysis.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Activity")
            .onChange(of: weekly) { _, _ in selectedDay = nil }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: weekly)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: monthOffset)
            .fileExporter(isPresented: $export, document: document, contentType: .plainText, defaultFilename: "Tender-\(weekly ? "Weekly" : month.formatted(.dateTime.month(.wide)))-Summary.txt") { result in if case .failure = result { store.error = "The summary couldn’t be exported. Try another location in Files." } }
    }
    private func heatmap(_ summary: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Your spending rhythm", subtitle: "Tap a day to see its total.")
            PaperCard {
                let monthDays = days
                let weekdayOffset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
                let symbols = calendar.veryShortStandaloneWeekdaySymbols
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 7) {
                    ForEach(0..<7, id: \.self) { i in Text(symbols[(calendar.firstWeekday - 1 + i) % 7]).font(.caption2).foregroundStyle(Ink.muted) }
                    ForEach((0..<weekdayOffset).map { -$0 - 1 }, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(monthDays, id: \.self) { day in
                        let value = summary.days[day] ?? 0
                        Button { selectedDay = day } label: {
                            Text(day.formatted(.dateTime.day())).font(.caption.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 34)
                                .background(value == 0 ? Ink.paper : Ink.green.opacity(value < 2500 ? 0.15 : value < 6000 ? 0.4 : 0.9), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(value >= 6000 ? Ink.paper : Ink.green)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedDay == day ? Ink.green : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(Money.format(value)) spent")
                    }
                }
                HStack { Text(selectedDay.map { "\($0.formatted(.dateTime.month(.abbreviated).day())) · \(Money.format(summary.days[$0] ?? 0))" } ?? "Darker ink = more spent"); Spacer() }.font(.caption).foregroundStyle(Ink.muted)
            }
        }
    }
    private func insight(_ summary: SpendingSummary) -> String {
        guard summary.total > 0 else { return "No posted spending in this period yet. Bank purchases and manual entries will appear here." }
        guard let top = store.ledger.categories.max(by: { (summary.categories[$0.id] ?? 0) < (summary.categories[$1.id] ?? 0) }), let total = summary.categories[top.id], total > 0 else {
            return "Your posted spending is \(Money.format(summary.total)). Review monthly payments to assign purchases to envelopes."
        }
        let count = summary.entries.filter { $0.categoryID == top.id }.count
        return "\(top.name) is your largest category this period at \(Money.format(total)) across \(count) purchases."
    }
    private func reportText(_ summary: SpendingSummary) -> String {
        var lines = ["Tender — \(weekly ? "Weekly" : "Monthly") Summary", "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(min(interval.end.addingTimeInterval(-1), Date()).formatted(date: .abbreviated, time: .omitted))", store.ledger.isDemo ? "SAMPLE DATA" : "Posted bank purchases and recorded expenses · USD", "", "Spent: \(Money.format(summary.total))"]
        for category in store.ledger.categories { lines.append("\(category.name): \(Money.format(summary.categories[category.id] ?? 0))") }
        lines.append("Needs an envelope: \(Money.format(summary.unassigned))")
        lines.append("\n" + insight(summary))
        return lines.joined(separator: "\n")
    }
}
