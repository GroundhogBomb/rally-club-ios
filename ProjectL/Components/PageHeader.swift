import SwiftUI

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.bold))
                .tracking(-0.3)
                .foregroundStyle(Color.inkBrown)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(subtitle)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
