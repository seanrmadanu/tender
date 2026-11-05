import Foundation

public enum CloudMergeError: Error { case conflict([String]), invalidData }

/// Three-way merge by stable record ID. Conflicting edits stop for review;
/// a remote snapshot is never blindly written over newer phone changes.
public enum CloudLedgerMerge {
    public static func merge(base: Ledger?, local: Ledger, remote: Ledger) throws -> Ledger {
        if local == remote { return local }
        guard let base else {
            let pristine = local.accounts.isEmpty && local.expenses.isEmpty && local.recurring.isEmpty && local.groceries.isEmpty && local.activeFixedExpenses.isEmpty && local.monthlyBudget == 0 && local.categories.map(\.name) == Ledger.empty().categories.map(\.name)
            guard pristine else { throw CloudMergeError.conflict(["Existing phone and cloud ledgers"]) }
            var result = remote
            // Photo bytes remain device-local. Preserve this phone's profile crop.
            result.profilePhoto = local.profilePhoto
            if let name = local.profileName { result.profileName = name }
            return try result.validated()
        }
        func object(_ ledger: Ledger) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder.tender.encode(ledger)) }
        var conflicts: [String] = []
        let result = mergeValue(base: try object(base), local: try object(local), remote: try object(remote), path: "", conflicts: &conflicts)
        guard conflicts.isEmpty else { throw CloudMergeError.conflict(conflicts) }
        guard let result, JSONSerialization.isValidJSONObject(result) else { throw CloudMergeError.invalidData }
        var decoded = try JSONDecoder.tender.decode(Ledger.self, from: JSONSerialization.data(withJSONObject: result))
        decoded.profilePhoto = local.profilePhoto
        return try decoded.validated()
    }
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return (a as? NSObject)?.isEqual(b) == true
    }
    private static func mergeValue(base: Any?, local: Any?, remote: Any?, path: String, conflicts: inout [String]) -> Any? {
        if same(local, remote) { return local }
        if same(local, base) { return remote }
        if same(remote, base) { return local }
        if let l = local as? [String: Any], let r = remote as? [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var result: [String: Any] = [:]
            for key in Set(l.keys).union(r.keys).union(b.keys).sorted() {
                if let value = mergeValue(base: b[key], local: l[key], remote: r[key], path: path.isEmpty ? key : path + "." + key, conflicts: &conflicts) { result[key] = value }
            }
            return result
        }
        if let l = local as? [[String: Any]], let r = remote as? [[String: Any]],
           l.allSatisfy({ $0["id"] is String }), r.allSatisfy({ $0["id"] is String }) {
            let b = base as? [[String: Any]] ?? []
            let li = l.map { $0["id"] as! String }, ri = r.map { $0["id"] as! String }, bi = b.compactMap { $0["id"] as? String }
            guard Set(li).count == li.count, Set(ri).count == ri.count, Set(bi).count == b.count else { conflicts.append(path); return local }
            let lm = Dictionary(uniqueKeysWithValues: zip(li, l)), rm = Dictionary(uniqueKeysWithValues: zip(ri, r)), bm = Dictionary(uniqueKeysWithValues: zip(bi, b))
            // Keep an intentional order change when only one side reordered.
            let surviving = Set(li).intersection(ri).intersection(bi)
            let lo = li.filter(surviving.contains), ro = ri.filter(surviving.contains), bo = bi.filter(surviving.contains)
            if lo != bo && ro != bo && lo != ro { conflicts.append(path + ".order"); return local }
            var order = lo != bo ? li : ri
            order += li.filter { !order.contains($0) }
            var result: [Any] = []
            for id in order {
                if let value = mergeValue(base: bm[id], local: lm[id], remote: rm[id], path: path + "." + id, conflicts: &conflicts) { result.append(value) }
            }
            return result
        }
        conflicts.append(path)
        return local
    }
}

public struct CloudChangeEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: AssistantProvider
    public var createdAt: Date
    public var kind: String
    public var title: String
    public var entityID: String?
}
public struct CloudLedgerSnapshot: Codable, Sendable {
    public var revision: Int
    public var epoch: Int
    public var connected: Bool
    public var ledger: Ledger?
    public var events: [CloudChangeEvent]
}
public struct CloudSyncState: Codable, Sendable {
    public var enabled = false
    public var revision = 0
    public var base: Ledger? = nil
    public var events: [CloudChangeEvent] = []
    public init() {}
}
