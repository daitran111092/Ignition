import AppKit
import SwiftUI
import LiftoffCore

/// The step's illustration (`<dataDir>/illustrations/<step id>.png`, or the chosen variant
/// `<step id>-n.png`) or, until one exists, its SF Symbol in white on a glassy orb with a soft glow.
/// With `onSelectVariant` set and two or more variants on disk, hovering shows a small ‹ 2 / 3 ›
/// switcher at the bottom; the arrows (or a click on the art itself) cross-fade to another variant.
struct StepVisual: View {
    let step: StepDefinition
    let size: CGFloat
    /// The chosen variant (1-based; clamped to what is on disk).
    var variant: Int = 1
    /// Called with the newly chosen variant; nil = no switcher.
    var onSelectVariant: ((Int) -> Void)?

    @Environment(\.showsVariantSwitcher) private var forceSwitcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let count = IllustrationCache.variantCount(for: step.id)
        let current = IllustrationVariants.clamp(variant, count: count)
        if count > 0, let image = IllustrationCache.image(for: step.id, variant: current)
            ?? IllustrationCache.image(for: step.id, variant: 1) {
            let switchable = onSelectVariant != nil && count > 1
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .id(current)
                    .transition(.opacity)
            }
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: current)
            .shadow(color: .black.opacity(0.45), radius: size * 0.08, y: size * 0.06)
            .contentShape(Rectangle())
            .onTapGesture { if switchable { select(IllustrationVariants.next(after: current, count: count)) } }
            .overlay(alignment: .bottom) {
                if switchable, hovering || forceSwitcher {
                    VariantSwitcher(current: current, count: count, height: Self.switcherHeight(for: size),
                                    onPrevious: { select(IllustrationVariants.previous(before: current, count: count)) },
                                    onNext: { select(IllustrationVariants.next(after: current, count: count)) })
                        .padding(.bottom, size * 0.03)
                        .transition(.opacity)
                }
            }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.18)) { hovering = inside }
            }
        } else {
            SymbolOrb(symbol: step.symbol, accent: StepPalette(step).accent, size: size)
        }
    }

    private func select(_ variant: Int) {
        onSelectVariant?(variant)
    }

    /// 20 pt under the notch card's 112 pt art, 28 pt under the fullscreen 320 pt art.
    private static func switcherHeight(for size: CGFloat) -> CGFloat {
        min(28, max(20, size * 0.088))
    }
}

/// ‹ 2 / 3 › on a translucent dark capsule, sized by `height`.
private struct VariantSwitcher: View {
    let current: Int
    let count: Int
    let height: CGFloat
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Previous illustration", action: onPrevious)
            Text("\(current) / \(count)")
                .font(.system(size: height * 0.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                .padding(.horizontal, height * 0.08)
            arrow("chevron.right", label: "Next illustration", action: onNext)
        }
        .frame(height: height)
        .padding(.horizontal, height * 0.12)
        .background(Capsule().fill(.black.opacity(0.42)))
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.6))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: height * 0.42, weight: .bold))
                .frame(width: height * 0.95, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChevronButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct ChevronButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.9))
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ShowsVariantSwitcherKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Shows the variant switcher without hovering (for `--render-*` snapshots).
    var showsVariantSwitcher: Bool {
        get { self[ShowsVariantSwitcherKey.self] }
        set { self[ShowsVariantSwitcherKey.self] = newValue }
    }
}

/// An SF Symbol in white on a glassy orb with a soft glow in `accent`.
struct SymbolOrb: View {
    let symbol: String
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.75), accent.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    // Specular highlight across the top of the glass orb.
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.5, height: size * 0.26)
                        .padding(.top, size * 0.04)
                }
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .shadow(color: .black.opacity(0.35), radius: size * 0.06, y: size * 0.05)
            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .medium))
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.7), radius: size * 0.06)
                .shadow(color: accent.opacity(0.9), radius: size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

/// Decoded illustrations, re-read when a file's modification date changes (and the folder
/// re-listed when it changes) so newly generated art shows up without relaunching.
@MainActor
private enum IllustrationCache {
    private static var images: [String: (modified: Date, image: NSImage)] = [:]
    private static var listing: (modified: Date, names: Set<String>)?

    private static var directory: URL {
        ConfigStore.defaultDirectory.appendingPathComponent("illustrations", isDirectory: true)
    }

    /// Contiguous variants of `id` on disk (0 = none, use the symbol).
    static func variantCount(for id: StepID) -> Int {
        IllustrationVariants.count(for: id, in: fileNames())
    }

    static func image(for id: StepID, variant: Int) -> NSImage? {
        let name = IllustrationVariants.fileName(for: id, variant: variant)
        let url = directory.appendingPathComponent(name)
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            images[name] = nil
            return nil
        }
        if let cached = images[name], cached.modified == modified { return cached.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[name] = (modified, image)
        return image
    }

    private static func fileNames() -> Set<String> {
        let dir = directory
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date else {
            listing = nil
            return []
        }
        if let listing, listing.modified == modified { return listing.names }
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        listing = (modified, names)
        return names
    }
}
