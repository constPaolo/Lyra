import SwiftUI

/// Halftone dot sphere driven by the audio spectrum. Dot size follows the
/// sphere's shading (larger on the shadow side) plus the level of the band
/// mapped to its distance from the center: bass in the middle, highs at the rim.
struct VisualizerView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dots across the sphere's diameter.
    private static let dotsAcross = 36

    var body: some View {
        VStack(spacing: 6) {
            if let track = vm.currentTrack {
                Text(track.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion && !vm.isPlaying)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    draw(in: &ctx, size: size, time: t)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 140)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let levels = vm.visualizerLevels
        guard size.width > 10, size.height > 10, !levels.isEmpty else { return }

        let bass = Double(levels.prefix(6).reduce(0, +) / 6)
        let radius = min(size.width, size.height) * 0.42 * (1 + 0.05 * bass)
        let n = Self.dotsAcross
        let pitch = radius * 2 / Double(n)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Light from the upper left, drifting slowly so the sphere feels alive.
        let angle = reduceMotion ? 0 : time * 0.15
        var light = (x: -0.55 + 0.15 * cos(angle), y: -0.6 + 0.15 * sin(angle), z: 0.6)
        let len = (light.x * light.x + light.y * light.y + light.z * light.z).squareRoot()
        light = (light.x / len, light.y / len, light.z / len)

        let lastBand = levels.count - 1
        var dots = Path()
        for row in 0..<n {
            for col in 0..<n {
                let nx = (Double(col) + 0.5) / Double(n) * 2 - 1
                let ny = (Double(row) + 0.5) / Double(n) * 2 - 1
                let r2 = nx * nx + ny * ny
                guard r2 <= 1 else { continue }
                let nz = (1 - r2).squareRoot()
                let lit = max(0, nx * light.x + ny * light.y + nz * light.z)

                let band = Double(levels[min(lastBand, Int(r2.squareRoot() * Double(lastBand)))])
                let energy = pow(max(0, band), 0.6)

                let fill = min(1, 0.16 + 0.62 * (1 - lit) + 0.55 * energy)
                let d = pitch * 0.92 * fill
                guard d > 0.6 else { continue }
                let x = center.x + nx * radius
                let y = center.y + ny * radius
                dots.addEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
            }
        }
        ctx.fill(dots, with: .color(Theme.ink))
    }
}
