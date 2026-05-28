import Foundation
import CribbleBundleRedirect

/// SwiftPM's generated `Bundle.module` accessors look for
/// `<.app>/<Name>.bundle` at the app root (which codesign forbids us from
/// populating) and a hard-coded developer `.build/...` path (which only exists
/// on the build machine). On every other Mac both lookups fail and the
/// accessor calls `fatalError("could not load resource bundle…")` — the app
/// "can't be opened."
///
/// The real fix lives in the `CribbleBundleRedirect` Objective-C target: a
/// load-time `__attribute__((constructor))` installs an `NSBundle` redirect to
/// `Contents/Resources/` *before any Swift static initializer runs*, so it
/// covers `Bundle.module` accesses from every module (Cribble, Textual,
/// SwiftUIMath) regardless of which one is touched first.
///
/// This Swift wrapper just forwards to that installer. Calling it is also what
/// guarantees the linker pulls the constructor's object file into the binary.
/// It is idempotent.
enum SPMBundleAccessorFix {
    static func ensureInstalled() {
        cribble_install_bundle_redirect()
    }
}
