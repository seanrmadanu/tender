import Foundation

public struct ShoppingPlanDraft: Sendable {
    public var item: String
    public var store: String
    public var date: Date
    public var hasExplicitTime: Bool
}
public enum ShoppingPlanParser {
    public static func parse(_ phrase: String, now: Date = Date(), calendar: Calendar = .current) -> ShoppingPlanDraft {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        var date = now
        let lower = text.lowercased()
        if lower.contains("tomorrow") { date = calendar.date(byAdding: .day, value: 1, to: now)! }
        else if let weekday = calendar.weekdaySymbols.firstIndex(where: { lower.contains($0.lowercased()) }) {
            date = calendar.nextDate(after: now, matching: DateComponents(weekday: weekday + 1), matchingPolicy: .nextTime) ?? now
        }
        let hourText = ReceiptParser.capture(#"\b(?:at\s+)?(\d{1,2})(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b"#, text)
        let minuteText = ReceiptParser.capture(#"\b\d{1,2}:(\d{2})\s*(?:a\.?m\.?|p\.?m\.?)\b"#, text)
        var explicitTime = false
        if let hour = hourText.flatMap(Int.init), (1...12).contains(hour), let period = ReceiptParser.capture(#"\b\d{1,2}(?::\d{2})?\s*(a\.?m\.?|p\.?m\.?)\b"#, text), (Int(minuteText ?? "0") ?? 99) < 60 {
            date = calendar.date(bySettingHour: hour % 12 + (period.lowercased().hasPrefix("p") ? 12 : 0), minute: Int(minuteText ?? "0") ?? 0, second: 0, of: date) ?? date
            explicitTime = true
        }
        let shop = ReceiptParser.capture(#"(?:\b(?:go|going)\s+(?:to\s+)?|\bat\s+)([A-Za-z][A-Za-z '&-]*?)(?=\s+(?:at\s+\d|tomorrow|today|on\s)|$)"#, text) ?? ""
        var item = text.replacingOccurrences(of: #"^(?:i\s+)?(?:want(?:\s+to)?|need(?:\s+to)?|plan\s+to|remind\s+me\s+to)\s+(?:(?:get|buy|pick\s+up)\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        item = item.components(separatedBy: "\n").first ?? item
        if let range = item.range(of: #"\s+(?:tomorrow|today|when|at|on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#, options: [.regularExpression, .caseInsensitive]) { item = String(item[..<range.lowerBound]) }
        return ShoppingPlanDraft(item: item.trimmingCharacters(in: .whitespacesAndNewlines), store: shop.trimmingCharacters(in: .whitespacesAndNewlines), date: date, hasExplicitTime: explicitTime)
    }
}
