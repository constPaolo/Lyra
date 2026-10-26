import SwiftUI

/// Full-page visualizer driven by the audio spectrum, in two styles:
/// - Sphere: a halftone dot sphere (bass in the middle, highs at the rim)
///   inside a ring of ticks that follow the spectrum, with held peaks and a
///   pulse on each kick.
/// - ASCII: the spectrum as columns of characters, mirrored around the
///   center line, bass in the middle.
struct VisualizerView: View {
    enum Style: String, CaseIterable {
        case sphere, ascii

        var label: String { self == .sphere ? "Sphere" : "ASCII" }
    }

    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lyra.visualizerStyle") private var style: Style = .sphere
    /// Mutated while drawing; a reference so frames don't trigger view updates.
    @State private var dynamics = SpectrumDynamics()

    var body: some View {
        VStack(spacing: 14) {
            header
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion && !vm.isPlaying)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    dynamics.update(levels: vm.visualizerLevels, time: t)
                    switch style {
                    case .sphere: drawSphere(in: &ctx, size: size, time: t)
                    case .ascii: drawAscii(in: &ctx, size: size)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 140)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let track = vm.currentTrack {
                ArtworkView(image: track.thumbnail, radius: 8)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(Style.allCases, id: \.self) { option in
                    Chip(title: option.label, isSelected: style == option) { style = option }
                }
            }
        }
        .frame(maxWidth: 720)
    }

    // MARK: - Sphere

    /// Dots across the sphere's diameter.
    private static let dotsAcross = 36
    private static let ringTicks = 120

    private func drawSphere(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let levels = dynamics.levels
        guard size.width > 10, size.height > 10, !levels.isEmpty else { return }

        let pulse = dynamics.pulse
        let base = min(size.width, size.height) * 0.34
        let radius = base * (1 + 0.04 * dynamics.bass + 0.05 * pulse)
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

        // Ring of ticks: bass at the top, highs toward the bottom, mirrored
        // left and right. Held peaks float just outside each tick.
        let inner = base * 1.14 + 10 * pulse
        let reach = base * 0.30
        let peaks = dynamics.peaks
        var ticks = Path()
        var caps = Path()
        for i in 0..<Self.ringTicks {
            let a = Double(i) / Double(Self.ringTicks) * 2 * .pi
            let side = a <= .pi ? a / .pi : (2 * .pi - a) / .pi   // 0 top → 1 bottom
            let b = min(lastBand, Int(side * Double(lastBand)))
            let energy = pow(Double(max(0, levels[b])), 0.75)
            let dx = sin(a), dy = -cos(a)
            let start = CGPoint(x: center.x + dx * inner, y: center.y + dy * inner)
            let length: Double = 3 + reach * energy
            let end = CGPoint(x: start.x + dx * length, y: start.y + dy * length)
            ticks.move(to: start)
            ticks.addLine(to: end)
            let peakEnergy = pow(Double(max(0, peaks[b])), 0.75)
            let peak = inner + 3 + reach * peakEnergy + 6
            let p = CGPoint(x: center.x + dx * peak, y: center.y + dy * peak)
            caps.addEllipse(in: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8))
        }
        ctx.stroke(ticks, with: .color(Theme.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        ctx.fill(caps, with: .color(Theme.ink.opacity(0.35)))
    }

    // MARK: - ASCII

    /// Sparse to dense.
    private static let ramp: [Character] = [".", ":", "-", "=", "+", "*", "#", "%", "@"]

    private func drawAscii(in ctx: inout GraphicsContext, size: CGSize) {
        let levels = dynamics.levels
        guard size.width > 40, size.height > 40, !levels.isEmpty else { return }

        let fontSize = max(11, min(18, size.width / 60))
        let cell = CGSize(width: fontSize * 0.62, height: fontSize * 1.15)
        let glyphs = Self.ramp.map {
            ctx.resolve(Text(String($0))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.ink))
        }
        let peakGlyph = ctx.resolve(Text("-")
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(Theme.ink))

        let cols = Int(size.width / cell.width)
        let halfRows = Int(size.height / cell.height / 2) - 1
        let midY = size.height / 2
        let left = (size.width - Double(cols) * cell.width) / 2 + cell.width / 2
        let lastBand = levels.count - 1
        let peaks = dynamics.peaks

        for c in 0..<cols {
            // Bass in the middle, highs toward both edges.
            let fromCenter = abs(Double(c) - Double(cols - 1) / 2) / (Double(cols) / 2)
            let b = min(lastBand, Int(fromCenter * Double(lastBand)))
            let energy = pow(Double(max(0, levels[b])), 0.7)
            let height = Int((energy * Double(halfRows)).rounded())
            let x = left + Double(c) * cell.width
            if height > 0 {
                for k in 0..<height {
                    // Densest at the center line, thinning toward the tips.
                    let along: Double = Double(k) / Double(max(1, halfRows))
                    let tip: Double = Double(k) / Double(max(1, height))
                    let density: Double = 1 - tip * 0.85 - along * 0.15
                    let index = Int(density * Double(glyphs.count - 1))
                    let g = glyphs[max(0, min(glyphs.count - 1, index))]
                    ctx.opacity = 0.35 + 0.65 * density
                    let dy: Double = (Double(k) + 0.5) * cell.height
                    ctx.draw(g, at: CGPoint(x: x, y: midY - dy))
                    // The reflection below is fainter.
                    ctx.opacity *= 0.45
                    ctx.draw(g, at: CGPoint(x: x, y: midY + dy))
                }
            }
            let peakEnergy = pow(Double(max(0, peaks[b])), 0.7)
            let peakRow = Int((peakEnergy * Double(halfRows)).rounded())
            if peakRow > height {
                ctx.opacity = 0.45
                ctx.draw(peakGlyph, at: CGPoint(x: x, y: midY - (Double(peakRow) + 0.5) * cell.height))
            }
        }
        ctx.opacity = 1
    }
}

/// Peak hold and kick detection on top of the smoothed levels. Updated from
/// the drawing pass, once per frame.
final class SpectrumDynamics {
    private(set) var levels: [Float] = []
    private(set) var peaks: [Float] = []
    /// Average of the lowest bands, 0...1.
    private(set) var bass: Double = 0
    /// Jumps to 1 on a kick, then fades out.
    private(set) var pulse: Double = 0

    private var bassAverage: Double = 0
    private var lastKick: Double = 0
    private var lastTime: Double = 0

    func update(levels: [Float], time: Double) {
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.1, max(0, time - lastTime))
        lastTime = time
        self.levels = levels
        if peaks.count != levels.count { peaks = levels }
        for i in levels.indices {
            // Peaks hold, then fall slowly.
            peaks[i] = max(levels[i], peaks[i] - Float(dt * 0.35))
        }

        let lows = levels.prefix(6)
        bass = lows.isEmpty ? 0 : Double(lows.reduce(0, +)) / Double(lows.count)
        bassAverage += (bass - bassAverage) * min(1, dt * 2.5)
        if bass > 0.22, bass > bassAverage * 1.3, time - lastKick > 0.22 {
            pulse = 1
            lastKick = time
        } else {
            pulse = max(0, pulse - dt * 3.5)
        }
    }
}
