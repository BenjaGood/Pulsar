import SwiftUI

enum StressLuxuryGaugePalette {
    /// Distributed along the arc angle: green holds through the low band,
    /// bright yellow lands exactly on the 50 crown, red only at the far end.
    static let gradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.11, green: 0.62, blue: 0.33), location: 0.00),
        .init(color: Color(red: 0.24, green: 0.70, blue: 0.33), location: 0.26),
        .init(color: Color(red: 0.62, green: 0.79, blue: 0.27), location: 0.40),
        .init(color: Color(red: 0.96, green: 0.80, blue: 0.26), location: 0.50),
        .init(color: Color(red: 0.95, green: 0.60, blue: 0.24), location: 0.70),
        .init(color: Color(red: 0.93, green: 0.42, blue: 0.27), location: 0.87),
        .init(color: Color(red: 0.88, green: 0.28, blue: 0.24), location: 1.00)
    ]
}
