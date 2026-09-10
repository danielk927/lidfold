import Foundation

/// Visual presets. Each one weights the three effects differently; the user's
/// slider values scale on top of whichever preset is active.
enum FoldStyle: String, CaseIterable {
    case silk   // soft perspective, gentle blur
    case shade  // heavy shadow, minimal blur
    case frost  // blur-forward, flat perspective

    var displayName: String {
        switch self {
        case .silk:  return "Silk"
        case .shade: return "Shade"
        case .frost: return "Frost"
        }
    }

    /// Multipliers applied to (perspective, blur, shadow).
    var weights: (perspective: Double, blur: Double, shadow: Double) {
        switch self {
        case .silk:  return (1.00, 0.60, 0.45)
        case .shade: return (0.70, 0.20, 1.00)
        case .frost: return (0.35, 1.00, 0.30)
        }
    }
}

/// User-tunable settings, persisted in UserDefaults.
final class FoldSettings {
    static let shared = FoldSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let style = "style"
        static let perspective = "perspective"
        static let blur = "blur"
        static let shadow = "shadow"
        static let enabled = "enabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.style: FoldStyle.silk.rawValue,
            // Start near full strength. These multiply through the active
            // style's weights, so mid-range defaults compounded down into a
            // fold barely distinguishable from no fold at all.
            Key.perspective: 0.5,
            Key.blur: 0.85,
            Key.shadow: 0.85,
            Key.enabled: true,
        ])
    }

    var style: FoldStyle {
        get { FoldStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .silk }
        set { defaults.set(newValue.rawValue, forKey: Key.style) }
    }

    /// All three are 0...1 intensities.
    var perspective: Double {
        get { defaults.double(forKey: Key.perspective) }
        set { defaults.set(newValue, forKey: Key.perspective) }
    }

    var blur: Double {
        get { defaults.double(forKey: Key.blur) }
        set { defaults.set(newValue, forKey: Key.blur) }
    }

    var shadow: Double {
        get { defaults.double(forKey: Key.shadow) }
        set { defaults.set(newValue, forKey: Key.shadow) }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Effective intensities with the active style's weighting folded in.
    var effective: (perspective: Double, blur: Double, shadow: Double) {
        let w = style.weights
        return (perspective * w.perspective, blur * w.blur, shadow * w.shadow)
    }
}
