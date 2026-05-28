#import "CribbleBundleRedirect.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Saved original implementations of the two NSBundle path initializers.
static IMP sOriginalInitWithPath = NULL;
static IMP sOriginalBundleWithPath = NULL;

/// Given a path of the form `<.app>/<Name>.bundle` (the location SwiftPM's
/// generated accessor probes, which codesign forbids us from populating),
/// return the standard `<.app>/Contents/Resources/<Name>.bundle` path. Returns
/// nil for anything that isn't exactly that shape so unrelated lookups are
/// never disturbed.
static NSString *CribbleRedirectedBundlePath(NSString *path) {
    if (![path isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    if (appPath.length == 0) {
        return nil;
    }
    NSString *prefix = [appPath stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) {
        return nil;
    }
    NSString *suffix = [path substringFromIndex:prefix.length];
    if (suffix.length == 0) {
        return nil;
    }
    // Only a direct child like "Cribble_Cribble.bundle" — never something
    // already nested (e.g. "Contents/Resources/...").
    if ([suffix rangeOfString:@"/"].location != NSNotFound) {
        return nil;
    }
    if (![suffix hasSuffix:@".bundle"]) {
        return nil;
    }
    return [appPath stringByAppendingFormat:@"/Contents/Resources/%@", suffix];
}

// -[NSBundle initWithPath:] replacement. Swift's `Bundle(path:)` funnels
// through this. If the original lookup fails, retry under Contents/Resources.
static id CribbleInitWithPath(id self, SEL _cmd, NSString *path) {
    id (*original)(id, SEL, NSString *) = (id (*)(id, SEL, NSString *))sOriginalInitWithPath;
    id result = original(self, _cmd, path);
    if (result != nil) {
        return result;
    }
    NSString *redirected = CribbleRedirectedBundlePath(path);
    if (redirected == nil) {
        return nil;
    }
    // The failed init above consumed `self`; allocate a fresh instance.
    return original([NSBundle alloc], _cmd, redirected);
}

// +[NSBundle bundleWithPath:] replacement (the class factory).
static id CribbleBundleWithPath(id self, SEL _cmd, NSString *path) {
    id (*original)(id, SEL, NSString *) = (id (*)(id, SEL, NSString *))sOriginalBundleWithPath;
    id result = original(self, _cmd, path);
    if (result != nil) {
        return result;
    }
    NSString *redirected = CribbleRedirectedBundlePath(path);
    if (redirected == nil) {
        return nil;
    }
    return original(self, _cmd, redirected);
}

void cribble_install_bundle_redirect(void) {
    static BOOL installed = NO;
    if (installed) {
        return;
    }
    installed = YES;

    Class bundleClass = [NSBundle class];

    Method initMethod = class_getInstanceMethod(bundleClass, @selector(initWithPath:));
    if (initMethod != NULL) {
        sOriginalInitWithPath = method_getImplementation(initMethod);
        method_setImplementation(initMethod, (IMP)CribbleInitWithPath);
    }

    Method factoryMethod = class_getClassMethod(bundleClass, @selector(bundleWithPath:));
    if (factoryMethod != NULL) {
        sOriginalBundleWithPath = method_getImplementation(factoryMethod);
        method_setImplementation(factoryMethod, (IMP)CribbleBundleWithPath);
    }
}

// Runs at image load — before main(), before any Swift `static let module`
// initializer — guaranteeing the redirect is active no matter which module
// (Cribble, Textual, SwiftUIMath) touches Bundle.module first.
__attribute__((constructor))
static void CribbleBundleRedirectConstructor(void) {
    cribble_install_bundle_redirect();
}
