import Foundation

/// A step's illustration variants: `<id>.png` is variant 1, then `<id>-2.png`, `<id>-3.png`, …
/// (contiguous; numbering stops at the first missing file). Variants are numbered from 1, the
/// same numbers the switcher shows ("2 / 3") and `LiftoffConfig.illustrationVariants` stores.
public enum IllustrationVariants {
    /// File name of `variant` (1-based) for `id`.
    public static func fileName(for id: StepID, variant: Int) -> String {
        variant <= 1 ? "\(id.rawValue).png" : "\(id.rawValue)-\(variant).png"
    }

    /// How many contiguous variants of `id` are in `fileNames` (a directory listing); 0 when even
    /// `<id>.png` is missing.
    public static func count(for id: StepID, in fileNames: some Sequence<String>) -> Int {
        let names = Set(fileNames)
        var count = 0
        while names.contains(fileName(for: id, variant: count + 1)) { count += 1 }
        return count
    }

    /// `selected` pulled into `1...count` (1 when there are no variants).
    public static func clamp(_ selected: Int, count: Int) -> Int {
        guard count > 0 else { return 1 }
        return min(max(selected, 1), count)
    }

    /// The variant after `selected`, wrapping from the last back to 1.
    public static func next(after selected: Int, count: Int) -> Int {
        guard count > 1 else { return 1 }
        return clamp(selected, count: count) % count + 1
    }

    /// The variant before `selected`, wrapping from 1 to the last.
    public static func previous(before selected: Int, count: Int) -> Int {
        guard count > 1 else { return 1 }
        let current = clamp(selected, count: count)
        return current == 1 ? count : current - 1
    }
}
