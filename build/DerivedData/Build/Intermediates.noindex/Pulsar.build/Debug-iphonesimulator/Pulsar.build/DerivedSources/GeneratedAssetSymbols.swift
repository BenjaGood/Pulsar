import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "AmazfitHelioRingDevice" asset catalog image resource.
    static let amazfitHelioRingDevice = DeveloperToolsSupport.ImageResource(name: "AmazfitHelioRingDevice", bundle: resourceBundle)

    /// The "AppleWatchDevice" asset catalog image resource.
    static let appleWatchDevice = DeveloperToolsSupport.ImageResource(name: "AppleWatchDevice", bundle: resourceBundle)

    /// The "PulsarLogoDark" asset catalog image resource.
    static let pulsarLogoDark = DeveloperToolsSupport.ImageResource(name: "PulsarLogoDark", bundle: resourceBundle)

    /// The "PulsarLogoLight" asset catalog image resource.
    static let pulsarLogoLight = DeveloperToolsSupport.ImageResource(name: "PulsarLogoLight", bundle: resourceBundle)

    /// The "PulsarLogoRed" asset catalog image resource.
    static let pulsarLogoRed = DeveloperToolsSupport.ImageResource(name: "PulsarLogoRed", bundle: resourceBundle)

    /// The "PulsarWordmarkDark" asset catalog image resource.
    static let pulsarWordmarkDark = DeveloperToolsSupport.ImageResource(name: "PulsarWordmarkDark", bundle: resourceBundle)

    /// The "PulsarWordmarkLight" asset catalog image resource.
    static let pulsarWordmarkLight = DeveloperToolsSupport.ImageResource(name: "PulsarWordmarkLight", bundle: resourceBundle)

    /// The "PulsarWordmarkTailDark" asset catalog image resource.
    static let pulsarWordmarkTailDark = DeveloperToolsSupport.ImageResource(name: "PulsarWordmarkTailDark", bundle: resourceBundle)

    /// The "PulsarWordmarkTailLight" asset catalog image resource.
    static let pulsarWordmarkTailLight = DeveloperToolsSupport.ImageResource(name: "PulsarWordmarkTailLight", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "AmazfitHelioRingDevice" asset catalog image.
    static var amazfitHelioRingDevice: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .amazfitHelioRingDevice)
#else
        .init()
#endif
    }

    /// The "AppleWatchDevice" asset catalog image.
    static var appleWatchDevice: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appleWatchDevice)
#else
        .init()
#endif
    }

    /// The "PulsarLogoDark" asset catalog image.
    static var pulsarLogoDark: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarLogoDark)
#else
        .init()
#endif
    }

    /// The "PulsarLogoLight" asset catalog image.
    static var pulsarLogoLight: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarLogoLight)
#else
        .init()
#endif
    }

    /// The "PulsarLogoRed" asset catalog image.
    static var pulsarLogoRed: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarLogoRed)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkDark" asset catalog image.
    static var pulsarWordmarkDark: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarWordmarkDark)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkLight" asset catalog image.
    static var pulsarWordmarkLight: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarWordmarkLight)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkTailDark" asset catalog image.
    static var pulsarWordmarkTailDark: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarWordmarkTailDark)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkTailLight" asset catalog image.
    static var pulsarWordmarkTailLight: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pulsarWordmarkTailLight)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "AmazfitHelioRingDevice" asset catalog image.
    static var amazfitHelioRingDevice: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .amazfitHelioRingDevice)
#else
        .init()
#endif
    }

    /// The "AppleWatchDevice" asset catalog image.
    static var appleWatchDevice: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appleWatchDevice)
#else
        .init()
#endif
    }

    /// The "PulsarLogoDark" asset catalog image.
    static var pulsarLogoDark: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarLogoDark)
#else
        .init()
#endif
    }

    /// The "PulsarLogoLight" asset catalog image.
    static var pulsarLogoLight: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarLogoLight)
#else
        .init()
#endif
    }

    /// The "PulsarLogoRed" asset catalog image.
    static var pulsarLogoRed: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarLogoRed)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkDark" asset catalog image.
    static var pulsarWordmarkDark: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarWordmarkDark)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkLight" asset catalog image.
    static var pulsarWordmarkLight: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarWordmarkLight)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkTailDark" asset catalog image.
    static var pulsarWordmarkTailDark: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarWordmarkTailDark)
#else
        .init()
#endif
    }

    /// The "PulsarWordmarkTailLight" asset catalog image.
    static var pulsarWordmarkTailLight: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pulsarWordmarkTailLight)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

