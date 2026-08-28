import SwiftUI

/// A single silhouette that joins the tapered blade and pivot orb.
struct StressGlassPointerShape: Shape {
    var bladeLength: CGFloat
    var orbRadius: CGFloat
    var pivot: CGPoint
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = pivot
        let joinX = center.x + orbRadius * 0.78
        let joinOffset = orbRadius * 0.58
        let tipHalfHeight = max(0.8, orbRadius * 0.075)
        let tipRadius = max(2.2, orbRadius * 0.18)
        let tipX = center.x + bladeLength
        let tipCenterY = center.y - orbRadius * 0.16

        var path = Path()
        path.move(to: CGPoint(x: joinX, y: center.y - joinOffset))
        path.addCurve(
            to: CGPoint(x: tipX - tipRadius, y: tipCenterY - tipHalfHeight),
            control1: CGPoint(x: center.x + bladeLength * 0.20, y: center.y - orbRadius * 0.76),
            control2: CGPoint(x: center.x + bladeLength * 0.63, y: center.y - orbRadius * 0.30)
        )
        path.addQuadCurve(
            to: CGPoint(x: tipX - tipRadius, y: tipCenterY + tipHalfHeight),
            control: CGPoint(x: tipX + tipRadius, y: tipCenterY)
        )
        path.addCurve(
            to: CGPoint(x: joinX, y: center.y + joinOffset),
            control1: CGPoint(x: center.x + bladeLength * 0.66, y: center.y + orbRadius * 0.17),
            control2: CGPoint(x: center.x + bladeLength * 0.24, y: center.y + orbRadius * 0.48)
        )

        // The remaining outline follows one uninterrupted, spherical pivot.
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + orbRadius),
            control1: CGPoint(x: center.x + orbRadius * 0.54, y: center.y + orbRadius * 0.92),
            control2: CGPoint(x: center.x + orbRadius * 0.30, y: center.y + orbRadius)
        )
        path.addCurve(
            to: CGPoint(x: center.x - orbRadius, y: center.y),
            control1: CGPoint(x: center.x - orbRadius * 0.55, y: center.y + orbRadius),
            control2: CGPoint(x: center.x - orbRadius, y: center.y + orbRadius * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - orbRadius),
            control1: CGPoint(x: center.x - orbRadius, y: center.y - orbRadius * 0.55),
            control2: CGPoint(x: center.x - orbRadius * 0.55, y: center.y - orbRadius)
        )
        path.addCurve(
            to: CGPoint(x: joinX, y: center.y - joinOffset),
            control1: CGPoint(x: center.x + orbRadius * 0.30, y: center.y - orbRadius),
            control2: CGPoint(x: center.x + orbRadius * 0.54, y: center.y - orbRadius * 0.92)
        )
        path.closeSubpath()

        let radians = angle * .pi / 180
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: radians)
            .translatedBy(x: -center.x, y: -center.y)
        return path.applying(transform)
    }
}
