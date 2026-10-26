import SwiftUI
import AppKit

/// First launch, before there's a music folder. Dropping a folder anywhere on
/// the window works as well as the button, and lifts the wave while dragging.
struct OnboardingView: View {
    let onChooseFolder: () -> Void
    let onDropFolder: (URL) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var appeared = false

    var body: some View {
        // The wave takes whatever height is left under the content, so it
        // never runs behind the text at any window size.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(maxHeight: 12)
            content
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .zIndex(1)
            // Starts behind the (opaque) step cards so it keeps some height
            // in short windows.
            AsciiWaveField(lift: isDropTargeted ? 1 : 0)
                .frame(minHeight: 40, maxHeight: .infinity)
                .padding(.top, -90)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: isDropTargeted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDropFolder(url.hasDirectoryPath ? url : url.deletingLastPathComponent())
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            LyraMark(size: 44)
                .padding(.bottom, 2)
                .reveal(appeared, order: 0)

            Kicker(text: isDropTargeted ? "Drop to add this folder" : "Welcome to Lyra")
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                .reveal(appeared, order: 1)

            Text("Your music,\nwith lyrics in sync.")
                .font(Theme.display(42))
                .tracking(Theme.displayTracking(42))
                .multilineTextAlignment(.center)
                .reveal(appeared, order: 2)

            Text("Pick a folder. Lyra sorts it into artists and albums and finds synced lyrics for every song.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 420)
                .reveal(appeared, order: 3)

            VStack(spacing: 12) {
                Button(action: onChooseFolder) {
                    Label("Choose music folder", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle(isLarge: true))
                Text("or drop a folder anywhere on this window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.top, 10)
            .reveal(appeared, order: 4)

            HStack(spacing: 10) {
                step(1, icon: "folder", title: "Choose a folder", detail: "MP3, FLAC, M4A, AIFF, WAV")
                stepArrow
                step(2, icon: "square.stack", title: "Lyra organizes it", detail: "Artists, albums, covers")
                stepArrow
                step(3, icon: "text.quote", title: "Lyrics in sync", detail: "Found and timed for you")
            }
            .padding(.top, 20)
            .reveal(appeared, order: 5)
        }
    }

    private func step(_ number: Int, icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.raised))
                    .raisedShadow()
                Spacer()
                Text(String(format: "%02d", number))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
        }
        .padding(16)
        .frame(width: 196, alignment: .leading)
        .tileBackground(radius: 22)
    }

    private var stepArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
    }
}

private extension View {
    /// Fades and rises into place, one element after the other.
    func reveal(_ shown: Bool, order: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(Double(order) * 0.07), value: shown)
    }
}

// MARK: - Wave field

/// A wave rising from the bottom, drawn as stepped gradient bands that
/// dissolve upward into ASCII characters. Monochrome ink, so it follows the
/// light and dark appearance. `lift` (0...1) raises the wave.
struct AsciiWaveField: View, @preconcurrency Animatable {
    var lift: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    /// Sparse to dense.
    private static let ramp: [Character] = [" ", ".", "·", ":", "-", "=", "+", "*", "#"]
    private static let bands = 7
    private static let cell = CGSize(width: 8, height: 13)
    /// Rows of characters above the wave's crest.
    private static let asciiRows = 11.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: t)
            }
        }
    }

    /// Height of the wave's crest at `x`, measured from the top.
    private func crest(_ x: Double, size: CGSize, time t: Double) -> Double {
        let u = x / max(size.width, 1) * 2 * .pi
        let base = 0.58 - 0.22 * lift
        let wave = 0.110 * sin(u * 1.1 + t * 0.35)
            + 0.055 * sin(u * 2.7 - t * 0.60 + 1.3)
            + 0.025 * sin(u * 6.3 + t * 1.10)
        return (base + wave * (1 + 0.6 * lift)) * size.height
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time t: Double) {
        guard size.width > 10, size.height > 10 else { return }

        // Stepped gradient: translucent bands stacked under the crest, each
        // a little lower and wider apart, so the ink deepens in steps.
        let step = 6.0
        for k in 0..<Self.bands {
            let offset = size.height * 0.05 * pow(Double(k), 1.35)
            var band = Path()
            band.move(to: CGPoint(x: 0, y: size.height))
            var x = 0.0
            while x <= size.width + step {
                band.addLine(to: CGPoint(x: x, y: crest(x, size: size, time: t) + offset))
                x += step
            }
            band.addLine(to: CGPoint(x: size.width, y: size.height))
            band.closeSubpath()
            ctx.fill(band, with: .color(Theme.ink.opacity(0.035)))
        }

        // ASCII dissolve above the crest: denser close to it, with per-cell
        // noise that flickers a few times a second.
        let glyphs = Self.ramp.map {
            ctx.resolve(Text(String($0))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.ink))
        }
        let cell = Self.cell
        let reach = min(Self.asciiRows * cell.height, size.height * 0.4)
        let columns = Int(size.width / cell.width) + 1
        for c in 0..<columns {
            let x = (Double(c) + 0.5) * cell.width
            let top = crest(x, size: size, time: t)
            let firstRow = max(0, Int((top - reach * 1.8) / cell.height))
            let lastRow = Int(top / cell.height)
            guard firstRow <= lastRow else { continue }
            for r in firstRow...lastRow {
                let y = (Double(r) + 0.5) * cell.height
                let distance = (top - y) / reach
                guard distance >= 0 else { continue }
                let tick = floor(t * 3 + Self.noise(c, r, 0) * 7)
                let jitter = Self.noise(c, r, Int(tick)) - 0.5
                var density = pow(max(0, 1 - distance), 1.7) + jitter * 0.35
                // A few stray characters drift higher up.
                if distance > 1, Self.noise(c, r, Int(tick) + 99) > 0.985 { density = 0.25 }
                let index = Int((min(1, density) * Double(Self.ramp.count - 1)).rounded())
                guard index > 0 else { continue }
                ctx.opacity = 0.14 + 0.4 * min(1, max(0, density))
                ctx.draw(glyphs[index], at: CGPoint(x: x, y: y))
            }
        }
        ctx.opacity = 1
    }

    /// Cheap stable hash of a cell and a time slot, in 0..<1.
    private static func noise(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
        h ^= h >> 33
        h &*= 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}
