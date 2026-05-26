import Foundation
import ObjectiveC

/// SwiftPM's generated `Bundle.module` accessor calls
/// `Bundle(path: Bundle.main.bundleURL.appendingPathComponent("<bundle>.bundle").path)`.
/// Inside a wrapped `.app` that path is `<.app>/<bundle>.bundle` — at the
/// .app root, outside `Contents/`. macOS codesign refuses to sign sub-bundles
/// at that location ("unsealed contents present in the bundle root"), so the
/// bundles can't ship there. Standard macOS layout puts them under
/// `Contents/Resources/`, and the packaging script does exactly that.
///
/// This file installs Obj-C runtime hooks on both `-[NSBundle initWithPath:]`
/// (which Swift's `Bundle(path:)` actually calls) and `+[NSBundle
/// bundleWithPath:]` (the class factory). Each hook retries failing lookups
/// under `Contents/Resources/` when the requested path looks like
/// `<.app>/<something>.bundle`. The redirect is strictly additive: paths
/// that already resolve are returned untouched, and paths that don't fit the
/// SwiftPM pattern fall through to the original behavior.
///
/// `ensureInstalled()` is called from `AppDelegate.init` and the top of
/// `applicationDidFinishLaunching` so the hooks are in place before any
/// `Bundle.module` static let is touched.
enum SPMBundleAccessorFix {
    @discardableResult
    static func ensureInstalled() -> Bool { installed }
}

private let installed: Bool = {
    SPMBundleHook.install()
    return true
}()

private typealias ClassBundleWithPathIMP = @convention(c) (AnyClass, Selector, NSString) -> Bundle?
private typealias InstanceInitWithPathIMP = @convention(c) (AnyObject, Selector, NSString) -> Bundle?

private enum SPMBundleHook {

    nonisolated(unsafe) static var originalClassIMP: ClassBundleWithPathIMP?
    nonisolated(unsafe) static var originalInstanceIMP: InstanceInitWithPathIMP?
    static let classSelector: Selector = NSSelectorFromString("bundleWithPath:")
    static let instanceSelector: Selector = NSSelectorFromString("initWithPath:")

    static func install() {
        let bundleClass: AnyClass = Bundle.self

        if let method = class_getClassMethod(bundleClass, classSelector) {
            originalClassIMP = unsafeBitCast(method_getImplementation(method), to: ClassBundleWithPathIMP.self)
            let block: @convention(block) (AnyClass, NSString) -> Bundle? = { cls, path in
                SPMBundleHook.interceptClass(cls: cls, path: path as String)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        if let method = class_getInstanceMethod(bundleClass, instanceSelector) {
            originalInstanceIMP = unsafeBitCast(method_getImplementation(method), to: InstanceInitWithPathIMP.self)
            let block: @convention(block) (AnyObject, NSString) -> Bundle? = { receiver, path in
                SPMBundleHook.interceptInstance(receiver: receiver, path: path as String)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    static func interceptClass(cls: AnyClass, path: String) -> Bundle? {
        guard let originalClassIMP else { return nil }
        if let direct = originalClassIMP(cls, classSelector, path as NSString) {
            return direct
        }
        guard let redirected = resourcesRedirect(for: path) else { return nil }
        return originalClassIMP(cls, classSelector, redirected as NSString)
    }

    static func interceptInstance(receiver: AnyObject, path: String) -> Bundle? {
        guard let originalInstanceIMP else { return nil }
        if let direct = originalInstanceIMP(receiver, instanceSelector, path as NSString) {
            return direct
        }
        guard let redirected = resourcesRedirect(for: path) else { return nil }
        return originalInstanceIMP(receiver, instanceSelector, redirected as NSString)
    }

    private static func resourcesRedirect(for path: String) -> String? {
        let appPath = Bundle.main.bundlePath
        let prefix = appPath + "/"
        guard path.hasPrefix(prefix) else { return nil }

        let suffix = String(path.dropFirst(prefix.count))
        guard !suffix.isEmpty,
              !suffix.contains("/"),
              suffix.hasSuffix(".bundle")
        else { return nil }

        return appPath + "/Contents/Resources/" + suffix
    }
}
