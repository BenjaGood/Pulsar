import SwiftUI

struct ProductBowlGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let left = rect.minX + width * 0.08
        let right = rect.maxX - width * 0.08
        let rimY = rect.minY + height * 0.24

        var path = Path()
        path.move(to: CGPoint(x: left, y: rimY))
        path.addLine(to: CGPoint(x: right, y: rimY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.72, y: rect.minY + height * 0.80),
            control: CGPoint(x: rect.minX + width * 0.86, y: rect.minY + height * 0.70)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.28, y: rect.minY + height * 0.80),
            control: CGPoint(x: rect.midX, y: rect.minY + height * 0.88)
        )
        path.addQuadCurve(
            to: CGPoint(x: left, y: rimY),
            control: CGPoint(x: rect.minX + width * 0.14, y: rect.minY + height * 0.70)
        )
        path.addEllipse(
            in: CGRect(
                x: left,
                y: rect.minY + height * 0.10,
                width: right - left,
                height: height * 0.28
            )
        )
        return path
    }
}
