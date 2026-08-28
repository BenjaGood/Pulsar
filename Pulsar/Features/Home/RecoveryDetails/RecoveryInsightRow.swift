import SwiftUI

struct RecoveryInsightRow: View {
    var insight: RecoveryInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(RecoveryDetailsDesign.strainBlue)
                .frame(width: 36, height: 36)
                .background(
                    RecoveryDetailsDesign.strainBlue.opacity(0.08),
                    in: .rect(cornerRadius: 12)
                )
                .accessibilityHidden(true)

            Text(insight.text)
                .pulsarTextStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
