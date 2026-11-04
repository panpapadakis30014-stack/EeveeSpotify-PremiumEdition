import Foundation
import Orion

// Opens Search or Your Library instead of Home once Spotify's main UI is up.
// Uses Spotify's own in-app link dispatcher, the same route Custom Tabs use.

struct StartupPageGroup: HookGroup { }

private var didOpenStartupPage = false
private let navigateSelector = NSSelectorFromString("navigateToURI:options:interactionID:")

class StartupPageLinkDispatcherHook: ClassHook<NSObject> {
    typealias Group = StartupPageGroup
    static let targetName = "SPTLinkDispatcherImplementation"

    func setMainUILoaded(_ loaded: Bool) {
        orig.setMainUILoaded(loaded)
        guard loaded, !didOpenStartupPage,
              let uriString = UserDefaults.extrasOptions.startupPage.uri,
              let url = URL(string: uriString) else { return }
        didOpenStartupPage = true

        let dispatcher = target
        // Let Home finish its first layout before switching, or the tab bar can desync.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard dispatcher.responds(to: navigateSelector) else {
                writeDebugLog("[StartupPage] navigateToURI unavailable")
                return
            }
            typealias Navigate = @convention(c) (NSObject, Selector, NSURL, Int64, AnyObject?) -> Void
            unsafeBitCast(dispatcher.method(for: navigateSelector), to: Navigate.self)(
                dispatcher, navigateSelector, url as NSURL, 0, nil
            )
            writeDebugLog("[StartupPage] Opened \(uriString)")
        }
    }
}

func activateStartupPage() {
    guard UserDefaults.extrasOptions.startupPage != .home else { return }
    // The Liquid Glass tab bar has its own launch tab; let it win so the two never fight.
    let glass = LiquidGlass.launchOptions
    if glass.enabled, glass.tabBar, UserDefaults.tabBarOptions.launchTab != nil {
        writeDebugLog("[StartupPage] Skipped: Liquid Glass launch tab is set")
        return
    }
    guard let cls = NSClassFromString(StartupPageLinkDispatcherHook.targetName),
          class_getInstanceMethod(cls, Selector(("setMainUILoaded:"))) != nil else {
        writeDebugLog("[StartupPage] Skipped: link dispatcher API missing")
        return
    }
    StartupPageGroup().activate()
}
