import Foundation
import Orion

// Second, read-only source for PremiumGate: the product state Spotify keeps
// in-app (same SPTCoreProductState setters upstream hooked on 9.1.x). The
// dictionary is passed through untouched; only "type"/"catalogue" are read.
// Needed because on some Spotify builds the bootstrap request isn't seen by
// the network hooks, which left the gate stuck at "unknown".

struct PremiumObserverGroup: HookGroup { }

private func observe(_ dict: NSDictionary, _ via: String) {
    let type = dict["type"] as? String
    let catalogue = dict["catalogue"] as? String
    guard type != nil || catalogue != nil else { return }
    NSLog("[EeveeSpotify][PremiumGate] product state via %@: type=%@ catalogue=%@",
          via, type ?? "nil", catalogue ?? "nil")
    PremiumGate.record(accountType: type, catalogue: catalogue, source: .productState)
}

class CoreProductStateObserverHook: ClassHook<NSObject> {
    typealias Group = PremiumObserverGroup
    static let targetName = "SPTCoreProductState"

    func setOriginalValues(_ dict: NSDictionary) {
        observe(dict, "setOriginalValues")
        orig.setOriginalValues(dict)
    }

    func setOverrides(_ dict: NSDictionary) {
        observe(dict, "setOverrides")
        orig.setOverrides(dict)
    }
}

func activatePremiumObserver() {
    guard let cls = NSClassFromString(CoreProductStateObserverHook.targetName) else {
        NSLog("[EeveeSpotify][PremiumGate] SPTCoreProductState missing; relying on bootstrap only")
        return
    }
    let hasOriginal = class_getInstanceMethod(cls, Selector(("setOriginalValues:"))) != nil
    let hasOverrides = class_getInstanceMethod(cls, Selector(("setOverrides:"))) != nil
    guard hasOriginal && hasOverrides else {
        NSLog("[EeveeSpotify][PremiumGate] product-state setters missing (orig=%ld overrides=%ld)",
              hasOriginal ? 1 : 0, hasOverrides ? 1 : 0)
        return
    }
    PremiumObserverGroup().activate()
    NSLog("[EeveeSpotify][PremiumGate] product-state observer active")
}
