#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "PulsarLogoDark" asset catalog image resource.
static NSString * const ACImageNamePulsarLogoDark AC_SWIFT_PRIVATE = @"PulsarLogoDark";

/// The "PulsarLogoLight" asset catalog image resource.
static NSString * const ACImageNamePulsarLogoLight AC_SWIFT_PRIVATE = @"PulsarLogoLight";

/// The "PulsarWordmarkDark" asset catalog image resource.
static NSString * const ACImageNamePulsarWordmarkDark AC_SWIFT_PRIVATE = @"PulsarWordmarkDark";

/// The "PulsarWordmarkLight" asset catalog image resource.
static NSString * const ACImageNamePulsarWordmarkLight AC_SWIFT_PRIVATE = @"PulsarWordmarkLight";

/// The "PulsarWordmarkTailDark" asset catalog image resource.
static NSString * const ACImageNamePulsarWordmarkTailDark AC_SWIFT_PRIVATE = @"PulsarWordmarkTailDark";

/// The "PulsarWordmarkTailLight" asset catalog image resource.
static NSString * const ACImageNamePulsarWordmarkTailLight AC_SWIFT_PRIVATE = @"PulsarWordmarkTailLight";

#undef AC_SWIFT_PRIVATE
