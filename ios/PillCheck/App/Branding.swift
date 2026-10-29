import SwiftUI

struct PillCheckMark: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(Theme.accent)
            Capsule()
                .fill(.white)
                .overlay { Rectangle().fill(Theme.accent).frame(width: size * 0.045) }
                .frame(width: size * 0.67, height: size * 0.31)
                .rotationEffect(.degrees(-45))
                .offset(x: -size * 0.065, y: -size * 0.045)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.23, weight: .heavy))
                .foregroundStyle(Theme.navy)
                .frame(width: size * 0.40, height: size * 0.40)
                .background(Color(red: 0.66, green: 0.95, blue: 0.83), in: Circle())
                .overlay { Circle().strokeBorder(Theme.accent, lineWidth: size * 0.04) }
                .offset(x: size * 0.25, y: size * 0.25)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct PillCheckWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            PillCheckMark()
            (Text("Pill").foregroundStyle(Theme.ink) + Text("Check").foregroundStyle(Theme.accent))
                .font(.system(.headline, weight: .bold)).tracking(-0.5)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PillCheck")
        .accessibilityAddTraits(.isHeader)
    }
}

private enum BrandPalette {
    static func top(_ progress: Double) -> Color {
        Color(red: 0.87 - 0.04 * progress, green: 0.91 + 0.04 * progress, blue: 1 - 0.07 * progress)
    }
    static func base(_ progress: Double) -> Color {
        Color(red: 0.96 - 0.01 * progress, green: 0.97 + 0.01 * progress, blue: 0.99 - 0.02 * progress)
    }
}

struct BrandBackdrop: View {
    var progress = 0.0
    var body: some View {
        LinearGradient(stops: [
            .init(color: BrandPalette.top(progress), location: 0),
            .init(color: BrandPalette.base(progress), location: 0.72),
            .init(color: BrandPalette.base(progress), location: 1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ScrollTone {
    static let steps = 24
    static func step(for offset: CGFloat) -> Int {
        // Quantize the first 600 points: small background updates, no per-pixel
        // state changes in medication rows or the store.
        Int((min(max(offset, 0), 600) / 600 * CGFloat(steps)).rounded())
    }
}

/// Owns scroll decoration state locally; content is built by the parent and
/// remains unchanged while the background responds to scrolling. iOS 17+.
struct BrandScrollView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var progress: Double { reduceMotion ? 0 : Double(step) / Double(ScrollTone.steps) }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: Int.self) { proxy in
                    ScrollTone.step(for: -proxy.frame(in: .scrollView(axis: .vertical)).minY)
                } action: { value in
                    if !reduceMotion && step != value { step = value }
                }
        }
        .background {
            BrandBackdrop(progress: progress)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: step)
        }
        .toolbarBackground(BrandPalette.top(progress), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
