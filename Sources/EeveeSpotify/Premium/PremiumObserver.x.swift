import Foundation
import Orion
import ObjectiveC.runtime

// Read-only sources for PremiumGate from the product state Spotify keeps
// in-app (SPTCoreProductState). Nothing is modified: every hook calls the
// original and passes values through untouched; only "type"/"catalogue" are
// read. Each entry point is its own group and is activated only if the method
// exists, so a renamed selector on a new Spotify build can't take the rest down.
//
// Diagnostics go to tmp/eeveespotify_boot.txt (always written, readable over
// USB from the app container) because iOS redacts Swift NSLog output.

enum PremiumDiag {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    private static var seenPaths = Set<String>()

    static func note(_ message: String) {
        eeveeBreadcrumb("[PG] " + message)
    }

    // Logs only the first few calls of each hook.
    static func hit(_ via: String, _ detail: @autoclosure () -> String) {
        lock.lock()
        let n = (counts[via] ?? 0) + 1
        counts[via] = n
        lock.unlock()
        if n <= 3 { note("hit \(via) #\(n): \(detail())") }
    }

    // First distinct API paths the network hooks see (no query strings).
    static func seen(_ url: URL) {
        let key = (url.host ?? "?") + url.path
        lock.lock()
        let fresh = seenPaths.count < 60 && seenPaths.insert(key).inserted
        lock.unlock()
        if fresh { note("net \(key)") }
    }
}

private enum ObservedPlan {
    static let lock = NSLock()
    static var lastType: String?
    static var lastCatalogue: String?

    // Getters run constantly; only forward actual changes to PremiumGate.
    static func report(type: String?, catalogue: String?, via: String) {
        guard type != nil || catalogue != nil else { return }
        lock.lock()
        let changed = (type != nil && type != lastType) || (catalogue != nil && catalogue != lastCatalogue)
        if let type { lastType = type }
        if let catalogue { lastCatalogue = catalogue }
        lock.unlock()
        guard changed else { return }
        PremiumDiag.note("plan via \(via): type=\(type ?? "-") catalogue=\(catalogue ?? "-")")
        PremiumGate.record(accountType: type, catalogue: catalogue, source: .productState)
    }
}

private func observe(_ dict: NSDictionary?, _ via: String) {
    guard let dict else { return }
    let type = dict["type"] as? String
    let catalogue = dict["catalogue"] as? String
    PremiumDiag.hit(via, "keys=\(dict.count) type=\(type ?? "-")")
    ObservedPlan.report(type: type, catalogue: catalogue, via: via)
}

private func observe(key: NSString, value: Any?, _ via: String) {
    let k = key as String
    guard k == "type" || k == "catalogue" else { return }
    let v = (value as? String) ?? (value as? NSString).map { $0 as String }
    PremiumDiag.hit(via, "\(k)=\(v ?? "nil")")
    if k == "type" { ObservedPlan.report(type: v, catalogue: nil, via: via) }
    else { ObservedPlan.report(type: nil, catalogue: v, via: via) }
}

private let productStateClass = "SPTCoreProductState"

struct PSSetOriginalGroup: HookGroup { }
struct PSSetOverridesGroup: HookGroup { }
struct PSInitGroup: HookGroup { }
struct PSStringForKeyGroup: HookGroup { }
struct PSSubscriptGroup: HookGroup { }
struct PSValuesGroup: HookGroup { }

class PSSetOriginalHook: ClassHook<NSObject> {
    typealias Group = PSSetOriginalGroup
    static let targetName = productStateClass
    func setOriginalValues(_ dict: NSDictionary) {
        observe(dict, "setOriginalValues")
        orig.setOriginalValues(dict)
    }
}

class PSSetOverridesHook: ClassHook<NSObject> {
    typealias Group = PSSetOverridesGroup
    static let targetName = productStateClass
    func setOverrides(_ dict: NSDictionary) {
        observe(dict, "setOverrides")
        orig.setOverrides(dict)
    }
}

class PSInitHook: ClassHook<NSObject> {
    typealias Group = PSInitGroup
    static let targetName = productStateClass
    func initWithValuesDict(_ dict: NSDictionary, scheduler: UnsafeRawPointer) -> Any {
        observe(dict, "initWithValuesDict")
        return orig.initWithValuesDict(dict, scheduler: scheduler)
    }
}

class PSStringForKeyHook: ClassHook<NSObject> {
    typealias Group = PSStringForKeyGroup
    static let targetName = productStateClass
    func stringForKey(_ key: NSString) -> NSString? {
        let value = orig.stringForKey(key)
        observe(key: key, value: value, "stringForKey")
        return value
    }
}

class PSSubscriptHook: ClassHook<NSObject> {
    typealias Group = PSSubscriptGroup
    static let targetName = productStateClass
    func objectForKeyedSubscript(_ key: NSString) -> Any? {
        let value = orig.objectForKeyedSubscript(key)
        observe(key: key, value: value, "subscript")
        return value
    }
}

class PSValuesHook: ClassHook<NSObject> {
    typealias Group = PSValuesGroup
    static let targetName = productStateClass
    func values() -> NSDictionary {
        let dict = orig.values()
        observe(dict, "values")
        return dict
    }
}

func activatePremiumObserver() {
    guard let cls = NSClassFromString(productStateClass) else {
        PremiumDiag.note("\(productStateClass) class MISSING")
        return
    }

    // One-time dump of the class's selectors so a future Spotify rename is visible.
    var count: UInt32 = 0
    if let list = class_copyMethodList(cls, &count) {
        let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(list[$0])) }.sorted()
        free(list)
        PremiumDiag.note("\(productStateClass) methods(\(count)): " + names.joined(separator: " "))
    }

    let hooks: [(String, () -> Void)] = [
        ("setOriginalValues:", { PSSetOriginalGroup().activate() }),
        ("setOverrides:", { PSSetOverridesGroup().activate() }),
        ("initWithValuesDict:scheduler:", { PSInitGroup().activate() }),
        ("stringForKey:", { PSStringForKeyGroup().activate() }),
        ("objectForKeyedSubscript:", { PSSubscriptGroup().activate() }),
        ("values", { PSValuesGroup().activate() }),
    ]
    var active: [String] = []
    for (selector, activate) in hooks where class_getInstanceMethod(cls, NSSelectorFromString(selector)) != nil {
        activate()
        active.append(selector)
    }
    PremiumDiag.note("observer active on: " + (active.isEmpty ? "NONE" : active.joined(separator: " ")))
}
