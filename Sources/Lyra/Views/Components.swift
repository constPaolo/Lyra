import SwiftUI
import AppKit

// MARK: - Buttons

/// Capsule button: `.primary` is solid ink, `.secondary` a soft chip.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    /// `true` for the one main call to action on a screen.
    var isLarge = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isLarge ? 16 : 14, weight: isLarge ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(kind == .primary ? Theme.canvas : Theme.ink)
            .padding(.horizontal, isLarge ? 28 : 18)
            .frame(height: isLarge ? 50 : 36)
            .background(
                Capsule().fill(kind == .primary ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.chip))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round icon button. Active state inverts to solid ink.
struct CircleIconButtonStyle: ButtonStyle {
    var isActive = false
    var size: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(isActive ? Theme.canvas : Theme.ink.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(isActive ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.chip)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

/// Bare glyph button for transport controls.
struct GlyphButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.16, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Selectable capsule used for filters and quick navigation.
struct Chip: View {
    let title: String
    var count: Int? = nil
    var isSelected = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Theme.canvas.opacity(0.6) : Theme.tertiary)
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? Theme.canvas : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule().fill(
                    isSelected ? AnyShapeStyle(Theme.ink)
                        : AnyShapeStyle(Theme.ink.opacity(isHovered ? 0.1 : 0.06))
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Tick slider

/// A row of vertical ticks: filled up to `value`, dimmed after. The ticks
/// under the pointer rise, and the span between the playhead and the pointer
/// is shaded to preview where a click would land.
struct TickSlider: View {
    /// 0...1
    let value: Double
    var height: CGFloat = 18
    var tickWidth: CGFloat = 2
    var spacing: CGFloat = 3
    /// Called continuously while dragging.
    var onScrub: ((Double) -> Void)? = nil
    /// Called once when the drag ends.
    var onCommit: ((Double) -> Void)? = nil

    /// Pointer x while hovering or dragging, nil otherwise.
    @State private var pointerX: CGFloat?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let pitch = tickWidth + spacing
                let count = max(2, Int((size.width + spacing) / pitch))
                let head = value * Double(count - 1)
                let pointer = pointerX.map { Double(fraction($0, width: size.width)) * Double(count - 1) }
                for i in 0..<count {
                    let x = Double(i)
                    var lift = 0.0
                    var color = x <= head ? Theme.ink : Theme.ink.opacity(0.16)
                    if let pointer {
                        let d = abs(x - pointer)
                        lift = exp(-(d * d) / 14)
                        // Preview the seek target between the playhead and the pointer.
                        if !isDragging, x > min(head, pointer), x <= max(head, pointer) {
                            color = Theme.ink.opacity(x <= head ? 0.55 : 0.4)
                        }
                    }
                    let rest = 0.62
                    let h = size.height * CGFloat(rest + (1 - rest) * lift)
                    let rect = CGRect(
                        x: CGFloat(i) * pitch,
                        y: (size.height - h) / 2,
                        width: tickWidth,
                        height: h
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: tickWidth / 2), with: .color(color))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        pointerX = g.location.x
                        onScrub?(fraction(g.location.x, width: geo.size.width))
                    }
                    .onEnded { g in
                        isDragging = false
                        onCommit?(fraction(g.location.x, width: geo.size.width))
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointerX = location.x
                case .ended: if !isDragging { pointerX = nil }
                }
            }
        }
        .frame(height: height)
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(max(0, min(x / width, 1)))
    }
}

// MARK: - Text

extension View {
    /// Digits roll when the value changes.
    func rollingDigits(_ value: Double) -> some View {
        self
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.25), value: value)
    }
}

/// Small rounded label above page titles.
struct Kicker: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: NSImage?
    var radius: CGFloat = Theme.Radius.thumb
    var glyph = "music.note"

    var body: some View {
        ZStack {
            if let image {
                Color.clear.overlay(
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                )
            } else {
                Theme.chip
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Search

/// Floating search pill. ⌘K focuses it, Return submits, Escape clears.
struct SearchPill: View {
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
            if text.isEmpty {
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 34)
        .background(Capsule().fill(Theme.tile))
        .background(
            Button("") { isFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.tertiary)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
