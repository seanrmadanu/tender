import Foundation

public struct ReceiptLine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var quantity: Int = 1
    public var total: Int64
}
public struct ReceiptDetails: Codable, Equatable, Sendable {
    public var merchant: String?
    public var total: Int64?
    public var date: Date?
    public var payment: String?
    public var items: [ReceiptLine] = []
    public var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
}
public enum ReceiptParser {
    static func capture(_ pattern: String, _ text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
    public static func parse(_ text: String) -> ReceiptDetails {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var receipt = ReceiptDetails()
        receipt.merchant = lines.prefix(6).first { $0.rangeOfCharacter(from: .letters) != nil &&
            $0.range(of: #"\b(receipt|invoice|welcome|tel|phone|www|http)\b"#, options: .regularExpression.union(.caseInsensitive)) == nil &&
            $0.count < 80 && !$0.contains("@") }
        for (index, line) in lines.enumerated() {
            let amountText = capture(#"\$?\s*(\d{1,7}(?:,\d{3})*\.\d{2})\s*[A-Z]?$"#, line)?.replacingOccurrences(of: ",", with: "")
            let amount = amountText.flatMap(Money.cents)
            let lower = line.lowercased()
            if lower.range(of: #"^(grand\s+total|total|amount\s+due|balance\s+due)(?:\s*:?\s*\$?\s*\d|:?\s*$)"#, options: .regularExpression) != nil {
                receipt.total = amount ?? (index + 1 < lines.count ? capture(#"^\$?\s*(\d+\.\d{2})$"#, lines[index + 1]).flatMap(Money.cents) : nil)
                continue
            }
            // Preserve only payment type and last four digits; never raw card numbers.
            if let kind = capture(#"\b(visa|mastercard|amex|discover|debit|credit|cash)\b"#, line) {
                let lastFour = capture(#"(?:\*{2,}|x{2,}|ending\s*(?:in)?\s*)(\d{4})\b"#, lower)
                receipt.payment = kind.capitalized + (lastFour.map { " ··" + $0 } ?? "")
            }
            if receipt.date == nil, let value = capture(#"\b(\d{1,2}/\d{1,2}/\d{2,4}|\d{4}-\d{2}-\d{2})\b"#, line) {
                for format in ["MM/dd/yyyy", "MM/dd/yy", "yyyy-MM-dd"] {
                    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format; f.isLenient = false
                    if let date = f.date(from: value) { receipt.date = date; break }
                }
            }
            if let amount, amount > 0,
               lower.range(of: #"\b(total|tax|change|cash|visa|mastercard|amex|discover|debit|credit|payment|balance|savings|discount|tender|auth|tip|subtotal)\b"#, options: .regularExpression) == nil,
               let name = capture(#"^(.+?)\s+\$?\d[\d,]*\.\d{2}\s*[A-Z]?$"#, line), name.rangeOfCharacter(from: .letters) != nil {
                let quantity = capture(#"^(\d{1,3})\s*[xX]\s+"#, name).flatMap(Int.init) ?? 1
                let cleanName = name.replacingOccurrences(of: #"^\d{1,3}\s*[xX]\s+"#, with: "", options: .regularExpression)
                receipt.items.append(ReceiptLine(name: cleanName, quantity: max(1, quantity), total: amount))
            }
        }
        return receipt
    }
}
public struct ShelfLabel: Sendable {
    public var name: String?
    public var price: Int64?
    public var unit: String?
    public var needsReview: Bool = true
}
public enum ShelfLabelParser {
    public static func parse(_ text: String) -> ShelfLabel {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Serving fractions on nearby packaging are not multi-buy offers.
        let labelLines = lines.filter { line in
            line.range(of: #"\b(servings?|calories|nutrition|sodium|sugars?|protein|cholesterol|carbohydrates?|saturated|trans\s+fat|daily\s+value)\b|\d\s*(?:/\s*\d)?\s*cups?\b"#,
                       options: .regularExpression.union(.caseInsensitive)) == nil
        }
        let name = productName(in: labelLines)
        let priceLines = labelLines.filter { $0.range(of: #"\b(per|unit price|save)\b|/\s*(oz|lb|kg|100)"#, options: .regularExpression.union(.caseInsensitive)) == nil }
        let pricePattern = try! NSRegularExpression(pattern: #"\$?\b(\d{1,6}\.\d{2})\b"#)
        let amounts = priceLines.flatMap { line in
            pricePattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match -> Int64? in
                guard let range = Range(match.range(at: 1), in: line) else { return nil }
                return Money.cents(String(line[range]))
            }
        }
        // Ambiguous multiple prices and multi-buy deals need explicit selection.
        let deal = labelLines.joined(separator: "\n").range(of: #"\d+\s*(for|/)\s*\$?\d"#, options: .regularExpression.union(.caseInsensitive)) != nil
        return ShelfLabel(name: name, price: Set(amounts).count == 1 && !deal ? amounts.first : nil,
            unit: ReceiptParser.capture(#"\b(\d+(?:\.\d+)?\s*(?:fl\s*oz|oz|lb|kg|ml|liters?|ct))\b"#, text))
    }
    private static func productName(in lines: [String]) -> String? {
        func isCandidate(_ line: String) -> Bool {
            guard line.filter({ $0.isLetter }).count >= 3, line.count <= 100,
                  !line.contains("@"), !line.contains("://") else { return false }
            let metadata = #"\b(unit price|save|member|sale|price|per|barcode|item no|net wt|rbst|gluten free|non.gmo|finance tracker|shopping mode|chatgpt|choose label photo|open image)\b|www\."#
            guard line.range(of: metadata, options: [.regularExpression, .caseInsensitive]) == nil else { return false }
            // Size-only lines belong to package details, not the product title.
            let sizeOnly = #"^[\d\s./×x-]+(?:fl\s*oz|oz|lb|kg|g|ml|liters?|ct|count|pk|pack|loads?|bottles?|btls?)(?:\b.*)?$"#
            return line.range(of: sizeOnly, options: [.regularExpression, .caseInsensitive]) == nil &&
                line.range(of: #"\$\s*\d|\d+\.\d{2}"#, options: .regularExpression) == nil
        }
        guard let first = lines.firstIndex(where: isCandidate) else { return nil }
        var parts = [lines[first]]
        // Shelf titles are often split over successive capitalized OCR lines.
        // Stop at IDs, prices, sizes or mixed-case prose rather than joining them.
        if lines[first] == lines[first].uppercased() {
            for line in lines.dropFirst(first + 1).prefix(2) {
                guard isCandidate(line), line == line.uppercased() else { break }
                parts.append(line)
            }
        }
        return parts.joined(separator: " ")
    }

}
