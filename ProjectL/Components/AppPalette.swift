import SwiftUI

extension Color {
    // Preserve the standard palette, including the fractional action ink RGB values.
    static let warmIvory = paletteHex(0xF7F5F1)
    static let softCream = paletteHex(0xFFFEFC)
    static let olive = paletteHex(0x795A34)
    static let oliveSoft = paletteHex(0xF3E7D3)
    static let warmGold = paletteHex(0xA47A43)
    static let inkBrown = paletteHex(0x262521)
    static let mutedBrown = paletteHex(0x716D65)
    static let actionFill = paletteHex(0xEED7B2)
    static let actionInk = Color(red: 0.20, green: 0.16, blue: 0.11).opacity(1)
    static let appSeparator = paletteHex(0x262521, alpha: 0.08)

    private static func paletteHex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
        .opacity(alpha)
    }
}

// MAINTENANCE-POINT: NAV-001
// System symbols provide the four tab icons and the native selection state.
enum CommunityTabIcon: String {
    case court = "tennis.racket"
    case clubFeed = "bubble.left.and.bubble.right"
    case gameRequest = "figure.cooldown"
    case profile = "person.crop.circle"
}

// MAINTENANCE-POINT: CANVAS-001
// Only backing layers use these values; never apply them to text, icons, or photos.
// CommunityBackdrop supplies the static background.
enum CommunityCanvasStyle {
    static let backdropImageOpacity = 0.62
    static let materialOpacity = 0.20
    static let surfaceTintOpacity = 0.22
    static let detailVeilOpacity = 0.24
    static let tabMaterialOpacity = 0.55
    static let segmentedTrackOpacity = 0.16
    static let segmentedSelectionOpacity = 0.42

    static func tabBackground(reduceTransparency: Bool) -> AnyShapeStyle {
        return reduceTransparency
            ? AnyShapeStyle(Color.softCream)
            : AnyShapeStyle(Material.ultraThin.opacity(tabMaterialOpacity))
    }
}

struct CommunityBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.warmIvory
                Image("ClubBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(CommunityCanvasStyle.backdropImageOpacity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Apply translucency to the backing surface only, never to its content.
struct WarmCanvas: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color.softCream
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(CommunityCanvasStyle.materialOpacity)
                    .overlay { Color.softCream.opacity(CommunityCanvasStyle.surfaceTintOpacity) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func warmCanvas() -> some View { background { WarmCanvas() } }
    func warmSegmentedCanvas() -> some View {
        background { WarmCanvas().clipShape(RoundedRectangle(cornerRadius: 8)) }
    }
}

struct AppActionButtonStyle: ButtonStyle {
    var isPrimary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isEnabled ? (isPrimary ? Color.actionInk : Color.olive) : Color.mutedBrown)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isEnabled ? (isPrimary ? Color.actionFill : Color.oliveSoft) : Color.appSeparator)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

struct AppIconButtonStyle: ButtonStyle {
    var isPrimary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(isPrimary ? Color.actionInk : Color.olive)
            .background {
                Circle().fill(isPrimary ? Color.actionFill : Color.oliveSoft)
            }
            .clipShape(Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}

struct AppReactionButtonStyle: ButtonStyle {
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .foregroundStyle(isActive ? Color.actionInk : Color.olive)
            .background {
                Capsule().fill(isActive ? Color.actionFill : Color.oliveSoft.opacity(0.6))
            }
            .clipShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
