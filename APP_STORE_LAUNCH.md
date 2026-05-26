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
