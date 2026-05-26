# App Store Launch Notes

## App Identity

- App name: `Cribble: Markdown Knowledge Base Manager`
- Bundle ID: `com.cribble.reader`
- Version: `1.0.0`
- Minimum macOS version: `15.0`
- Category suggestion: Productivity

## Pricing Model

Use paid app pricing in App Store Connect:

- Price: `$2.49`
- In-app purchases: none
- In-app paywall: none

App Store customers pay before installing and receive regular stable updates
through the Mac App Store. Users with GitHub access can still download and run
the latest signed DMG from GitHub Releases.

The Small Business Program affects Apple's commission rate in App Store Connect.
It does not require code changes in Cribble. Confirm enrollment is active before
the app goes on sale.

## App Store Connect Checklist

- Create the macOS app record with bundle ID `com.cribble.reader`.
- Set the app's paid price to `$2.49`.
- Upload screenshots and app icon assets.
- Fill privacy details: local file access, no account requirement, no first-party analytics unless added later.
- Include review notes explaining that Cribble opens user-selected Markdown folders and stores security-scoped bookmarks.
- Do not enable In-App Purchase unless the business model changes later.

## Build Checklist

- Archive with an Apple Distribution certificate for Mac App Store submission.
- Use `Cribble.entitlements` so the app is sandboxed and can access user-selected folders.
- Keep `script/package_release.sh` for the public GitHub DMG channel.
- Run `swift test` before uploading.

## Current Local Status

- The app has no in-app paywall and no in-app purchases.
- App Store Connect is open in Chrome at `https://appstoreconnect.apple.com/apps`.
- `Cribble.xcworkspace` currently reports no Xcode schemes, so Xcode archive/upload is not ready from this workspace yet.
- Installed signing identities include `Apple Distribution: Aman Pandey (JP4HU7X6G7)` and `Developer ID Application: Aman Pandey (JP4HU7X6G7)`.
- The Transporter command-line helper is not installed; `xcrun iTMSTransporter` asks to install Transporter from the Mac App Store.

Apple's current upload options are Xcode, Swift Playgrounds, `altool`, or
Transporter. The first App Store Connect step is to create the macOS app record;
after that, uploaded builds are associated by bundle ID, version, and build
number.

Sources:

- https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
