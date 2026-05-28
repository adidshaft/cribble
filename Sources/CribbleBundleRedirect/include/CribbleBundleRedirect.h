#ifndef CRIBBLE_BUNDLE_REDIRECT_H
#define CRIBBLE_BUNDLE_REDIRECT_H

/// Installs (once, idempotently) an Objective-C runtime redirect on
/// `-[NSBundle initWithPath:]` and `+[NSBundle bundleWithPath:]` so that
/// SwiftPM's generated `Bundle.module` accessors — which look for
/// `<.app>/<Name>.bundle` at the (codesign-forbidden) app root — resolve to
/// the real location `<.app>/Contents/Resources/<Name>.bundle`.
///
/// This is also invoked from a load-time `__attribute__((constructor))`, so
/// the redirect is active before `main()` and before any Swift `static let
/// module` initializer can run. Calling it again later is a no-op.
void cribble_install_bundle_redirect(void);

#endif /* CRIBBLE_BUNDLE_REDIRECT_H */
