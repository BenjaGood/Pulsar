import SwiftUI

struct SleepBalanceThreeColumnLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        let proportions = proportions(for: width)
        let height = subviews.indices.reduce(CGFloat.zero) { currentHeight, index in
            let columnWidth = width * proportion(at: index, in: proportions)
            let size = subviews[index].sizeThatFits(
                ProposedViewSize(width: columnWidth, height: proposal.height)
            )
            return max(currentHeight, size.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        let proportions = proportions(for: bounds.width)

        for index in subviews.indices {
            let columnWidth = bounds.width * proportion(at: index, in: proportions)
            let columnProposal = ProposedViewSize(
                width: columnWidth,
                height: bounds.height
            )
            let size = subviews[index].sizeThatFits(columnProposal)

            subviews[index].place(
                at: CGPoint(
                    x: x,
                    y: bounds.midY - (size.height / 2)
                ),
                anchor: .topLeading,
                proposal: columnProposal
            )
            x += columnWidth
        }
    }

    private func proportion(at index: Int, in proportions: [CGFloat]) -> CGFloat {
        index < proportions.count ? proportions[index] : 0
    }

    private func proportions(for width: CGFloat) -> [CGFloat] {
        width < 330
            ? [0.32, 0.36, 0.32]
            : [0.34, 0.30, 0.36]
    }
}
