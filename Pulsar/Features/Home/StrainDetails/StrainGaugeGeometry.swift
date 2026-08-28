import CoreGraphics

struct StrainGaugeGeometry {
    let width: CGFloat
    let targetRange: PulsarSharedStrainTargetRange?

    func position(for value: Int) -> CGFloat {
        guard let targetRange else {
            return width * CGFloat(min(max(Double(value) / 100, 0), 0.91))
        }

        let lower = Double(targetRange.lowerBound)
        let upper = Double(targetRange.upperBound)
        let current = Double(value)

        let normalized: Double
        if current <= lower {
            normalized = lower > 0 ? 0.30 * current / lower : 0
        } else if current <= upper {
            let span = max(upper - lower, 1)
            normalized = 0.30 + (0.30 * (current - lower) / span)
        } else {
            let span = max(100 - upper, 1)
            normalized = 0.60 + (0.31 * (current - upper) / span)
        }

        return width * CGFloat(min(max(normalized, 0), 0.91))
    }

    func labelPosition(for value: Int) -> CGFloat {
        min(max(position(for: value), 12), width - 12)
    }
}
