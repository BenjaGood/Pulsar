# Pulsar Watch Install Diagnostics

Last verified: 2026-05-14.

## Device Check

- iPhone: Benjamin's iPhone, iPhone 14 Pro Max, iOS 26.5.
- Apple Watch: Benjamin's Apple Watch, Apple Watch Series 7, watchOS 26.5.
- Pulsar watchOS deployment target: 10.0, compatible with the paired watch.

## Final Bundle Identifiers

- iOS app: `aetherial.Pulsar`
- Watch app: `aetherial.Pulsar.watchkitapp`
- Watch extension: not present. Pulsar uses the Xcode 14+ single-target watchOS app structure, valid for watchOS 7 and later.

The Watch app bundle id is nested under the iOS app bundle id. There is no separate `WKAppBundleIdentifier` relationship because there is no WatchKit extension target.

## Final Built Structure

The clean rebuilt iPhone product contains:

```text
Pulsar.app/
  Watch/
    Pulsar Watch App.app/
      Info.plist
      Pulsar Watch App
      Assets.car
      embedded.mobileprovision
      _CodeSignature/
```

There is intentionally no:

```text
Pulsar Watch App.app/PlugIns/*.appex
```

Apple's current WatchKit model supports single-target watchOS apps in Xcode 14 and later. Adding an empty WatchKit extension would create a mismatched package unless the whole watch app were converted back to the legacy app-plus-extension architecture.

## Info.plist Checks

Watch app plist:

- `CFBundleIdentifier = aetherial.Pulsar.watchkitapp`
- `CFBundleExecutable = Pulsar Watch App`
- `CFBundlePackageType = APPL`
- `CFBundleDisplayName = Pulsar Watch App`
- `WKApplication = true`
- `WKCompanionAppBundleIdentifier = aetherial.Pulsar`
- `WKBackgroundModes = workout-processing, location`
- `MinimumOSVersion = 10.0`
- `UIDeviceFamily = 4`

The Watch app now uses explicit plist file `PulsarWatchApp-Info.plist`.

## Signing And Entitlements

Team:

- iOS app target: `8Q8WHNEQP8`
- Watch app target: `8Q8WHNEQP8`
- Widget extension target: `8Q8WHNEQP8`

Signing style:

- Automatic signing on all app/widget/watch targets.

iOS app signed entitlements:

- `application-identifier = 8Q8WHNEQP8.aetherial.Pulsar`
- `com.apple.developer.healthkit = true`
- `com.apple.security.application-groups = group.aetherial.Pulsar`
- `com.apple.developer.team-identifier = 8Q8WHNEQP8`

Watch app signed entitlements:

- `application-identifier = 8Q8WHNEQP8.aetherial.Pulsar.watchkitapp`
- `com.apple.developer.healthkit = true`
- `com.apple.developer.team-identifier = 8Q8WHNEQP8`

Provisioning profiles decoded with `openssl smime` include the connected iPhone UDID and paired Apple Watch UDID.

## Build Phase Checks

- iOS target has `Embed Watch Content`.
- `Embed Watch Content` copies only `Pulsar Watch App.app` into `$(CONTENTS_FOLDER_PATH)/Watch`.
- The Watch app is not embedded in iOS `Copy Bundle Resources`.
- No Watch extension is embedded directly in the iOS app.
- No duplicate or stale Watch products are listed in build phases.

## App Icon Checks

- Watch icon `Contents.json` is valid.
- All referenced Watch icon PNGs are present.
- PNG dimensions match their declared pixel slots: 48, 55, 58, 66, 80, 87, 88, 92, 100, 102, 108, 172, 196, 216, 234, 258, and 1024.

## Xcode Settings Changed

- Watch product output changed to `Pulsar Watch App.app`.
- Watch target `PRODUCT_NAME = Pulsar Watch App`.
- Watch target `SKIP_INSTALL = NO`.
- Watch target uses explicit `INFOPLIST_FILE = PulsarWatchApp-Info.plist`.
- Watch target keeps `SUPPORTED_PLATFORMS = watchos watchsimulator`.
- Watch target keeps `ARCHS = arm64 arm64_32`.

## Verification Performed

Commands completed successfully:

```sh
xcodebuild build via Xcode MCP
xcrun devicectl device install app --device 52B8297E-A600-503C-B226-2DD91F2E9FD1 ".../Pulsar.app"
xcrun devicectl device install app --device 7B77DB01-E152-57AD-883B-E9A8FEE6DF17 ".../Pulsar.app/Watch/Pulsar Watch App.app"
xcrun devicectl device process launch --device 7B77DB01-E152-57AD-883B-E9A8FEE6DF17 aetherial.Pulsar.watchkitapp
xcrun devicectl device info apps --device 7B77DB01-E152-57AD-883B-E9A8FEE6DF17 --filter "bundleIdentifier == 'aetherial.Pulsar.watchkitapp'"
```

Results:

- iPhone app installed with bundle id `aetherial.Pulsar`.
- Watch app installed with bundle id `aetherial.Pulsar.watchkitapp`.
- Watch app launched successfully by bundle id.
- Apple Watch installed app list reports `Pulsar Watch App`, version `1.0`, build `1`.

Install logs were written to:

- `/private/tmp/pulsar-iphone-install-clean.log`
- `/private/tmp/pulsar-watch-install-clean.log`
- `/private/tmp/pulsar-watch-launch-clean.log`

## Debug Commands

Print the embedded Watch app structure:

```sh
find "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Watch" -maxdepth 3 -print
```

Print bundle identifiers:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Watch/Pulsar Watch App.app/Info.plist"
```

Print Watch app install keys:

```sh
plutil -p "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Watch/Pulsar Watch App.app/Info.plist"
codesign -d --entitlements - "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Watch/Pulsar Watch App.app"
```

Directly verify install on the paired Watch:

```sh
xcrun devicectl device install app --device 7B77DB01-E152-57AD-883B-E9A8FEE6DF17 "$HOME/Library/Developer/Xcode/DerivedData/Pulsar-dsekvsrpmmtmirgtrnyrxbzmpaei/Build/Products/Debug-iphoneos/Pulsar.app/Watch/Pulsar Watch App.app"
xcrun devicectl device process launch --device 7B77DB01-E152-57AD-883B-E9A8FEE6DF17 aetherial.Pulsar.watchkitapp
```

## Clean Reinstall Steps

1. Delete Pulsar from iPhone.
2. Delete Pulsar from Apple Watch if it appears.
3. In Xcode, choose Product > Clean Build Folder.
4. Delete the `Pulsar-*` folder in `~/Library/Developer/Xcode/DerivedData`.
5. Restart iPhone and Apple Watch if the Watch app still shows stale install state.
6. Reconnect the iPhone by cable, unlock it, and keep Apple Watch unlocked/on wrist.
7. Build and run the iOS `Pulsar` target on the physical iPhone.
8. Open the iPhone Watch app and confirm `Pulsar Watch App` is installed, or install it manually.
9. If manual install still fails, capture the install log from Console.app using predicates for `installd`, `mobile_installation_proxy`, `appstored`, `companionappd`, and `watchappd`.
