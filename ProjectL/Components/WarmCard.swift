import SwiftUI

/// Open content sections use spacing and a hairline, not nested card surfaces.
struct EditorialSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.appSeparator).frame(height: 1)
            }
    }
}

// I18N-001
// Shared empty, loading, and error states.
struct WarmCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCanvas()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appSeparator, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

struct RepositoryStateView: View {
    let state: RepositoryLoadState
    let retry: (() -> Void)?

    private var copy: AppCopy { AppCopy() }

    var body: some View {
        WarmCard {
            VStack(spacing: 14) {
                switch state {
                case .loading:
                    ProgressView()
                    Text(copy.loadingTitle)
                        .font(.headline)
                        .foregroundStyle(Color.inkBrown)
                case .empty:
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(Color.olive)
                    Text(copy.noDataTitle)
                        .font(.headline)
                        .foregroundStyle(Color.inkBrown)
                    Text(copy.noDataMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                        .multilineTextAlignment(.center)
                case let .failure(failure):
                    Image(systemName: failure.kind == .network ? "wifi.exclamationmark" : "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(Color.warmGold)
                    Text(copy.errorTitle)
                        .font(.headline)
                        .foregroundStyle(Color.inkBrown)
                    Text(copy.loadFailureMessage(failure))
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                        .multilineTextAlignment(.center)
                    if let retry {
                        Button(copy.retryTitle, action: retry)
                            .buttonStyle(AppActionButtonStyle())
                            .tint(Color.olive)
                    }
                case .content:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .loading: copy.loadingTitle
        case .empty: "\(copy.noDataTitle). \(copy.noDataMessage)"
        case .content: ""
        case let .failure(failure): "\(copy.errorTitle). \(copy.loadFailureMessage(failure))"
        }
    }
}
