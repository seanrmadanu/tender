import Foundation

public struct SubscriptionMailbox: Codable, Identifiable, Equatable, Sendable {
    public var id: String // Gmail profile address, never supplied by an email sender
    public var checkedAt: Date?
}
public struct SubscriptionEmail: Codable, Identifiable, Equatable, Sendable {
    public var id: String // mailbox + Gmail message id, not subject/merchant
    public var mailbox: String
    public var merchant: String
    public var subject: String
    public var received: Date
    public var kind: String // trial, cancellation, renewal
    public var amount: Int64?
    public var date: Date?
    public var cycle: BillingCycle?
    public var reviewed: Bool = false
}
public enum SubscriptionEmailParser {
    public static func parse(id: String, mailbox: String, sender: String, subject: String, body: String, received: Date) -> SubscriptionEmail? {
        let text = String((subject + "\n" + body).prefix(20000))
        let lower = text.lowercased()
        guard lower.range(of: #"\b(subscription|membership|trial|renewal|renews|renewing)\b"#, options: .regularExpression) != nil else { return nil }
        let cancelled = lower.range(of: #"\b(cancelled|canceled|cancellation confirmed|will not renew|won't renew)\b"#, options: .regularExpression) != nil
        let kind = cancelled ? "cancellation" : lower.contains("trial") ? "trial" : "renewal"
        // Read amounts only from renewal/charge context, not arbitrary receipt totals.
        let money = ReceiptParser.capture(#"(?:renew\w*|charg\w*|then|price)[^\n$]{0,80}\$\s*(\d{1,6}\.\d{2})\b"#, text).flatMap(Money.cents)
        let relevantLines = text.components(separatedBy: .newlines).filter {
            $0.range(of: #"trial.{0,30}end|renew|next.{0,15}(bill|charge)|expires"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let dateText = relevantLines.joined(separator: "\n")
        let dates = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue))?
            .matches(in: dateText, range: NSRange(dateText.startIndex..., in: dateText)).compactMap(\.date) ?? []
        let uniqueDates = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let cycle: BillingCycle? = lower.contains("monthly") || lower.contains("per month") || lower.contains("/month") ? .monthly : lower.contains("annually") || lower.contains("per year") || lower.contains("/year") ? .yearly : lower.contains("weekly") || lower.contains("per week") ? .weekly : nil
        let merchant = sender.components(separatedBy: "<").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) ?? sender
        return SubscriptionEmail(id: id, mailbox: mailbox, merchant: String(merchant.prefix(120)), subject: String(subject.prefix(250)), received: received, kind: kind, amount: money, date: uniqueDates.count == 1 ? uniqueDates.first : nil, cycle: cycle)
    }
}
