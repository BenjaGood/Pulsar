# Pulsar Watch Install Debug

Checks performed:

- iOS bundle identifier: `aetherial.Pulsar`.
- Watch app bundle identifier: `aetherial.Pulsar.watchkitapp`.
- Watch companion key: `WKCompanionAppBundleIdentifier = aetherial.Pulsar`.
- iOS target embeds the Watch app in `Embed Watch Content` at `$(CONTENTS_FOLDER_PATH)/Watch`.
- Watch target builds for `watchos watchsimulator`, device architectures `arm64 arm64_32`, and `TARGETED_DEVICE_FAMILY = 4`.
- iOS and Watch targets use automatic signing with team `8Q8WHNEQP8`.
- Watch app has HealthKit entitlement, Health usage strings, Location usage string, Motion usage string, `WKApplication = YES`, and `WKBackgroundModes = workout-processing location`.
- Watch app uses `PulsarWatchApp-Info.plist` as an explicit plist so the packaged companion app includes the required watchOS keys and does not inherit stale generated plist values.
- Watch app icon set contains the required watch notification, companion settings, app launcher, quick look, and marketing PNGs with matching dimensions.
- iOS and Watch targets share `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`.

Clean reinstall steps for device testing:

1. Delete Pulsar from the iPhone.
2. Delete Pulsar from Apple Watch if it is present.
3. In Xcode, choose Product > Clean Build Folder.
4. Delete stale DerivedData for Pulsar from Xcode Settings > Locations, or remove the `Pulsar-*` DerivedData folder.
5. Reconnect the iPhone by cable, unlock it, and keep Apple Watch unlocked and on the wrist.
6. Build and run the iPhone `Pulsar` target on the physical iPhone.
7. Open the iPhone Watch app and install `Pulsar Watch App`, or wait for automatic companion install.
8. If Xcode shows a device tunnel error, unplug/replug the iPhone, trust the computer again if prompted, restart Xcode, and build the iPhone target again.
