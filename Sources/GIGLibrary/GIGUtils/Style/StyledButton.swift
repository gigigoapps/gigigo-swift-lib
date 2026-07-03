import UIKit

/// A `UIButton` that applies a state-aware background colour.
///
/// `UIView.backgroundColor` is not state-aware, so a plain `UIButton` cannot dim its
/// background when disabled without either freezing dynamic colours into an image or
/// leaving a baked-in alpha that sticks after re-enabling (the C027 bug). `StyledButton`
/// solves both: it stores the enabled/disabled colours and swaps `backgroundColor` in
/// `isEnabled`'s `didSet`. Because it assigns a `UIColor` (not a rendered image), a dynamic
/// colour (e.g. `.systemBackground` or an asset colour) keeps re-resolving on light/dark
/// trait changes.
///
/// Style it through `withStyle(_:)` with a `ButtonStyle` whose `disabledBackgroundColor`
/// is set; the colours are wired up automatically.
public final class StyledButton: UIButton {
    private var enabledBackgroundColor: UIColor?
    private var disabledBackgroundColor: UIColor?

    public override var isEnabled: Bool {
        didSet { applyStatefulBackgroundColor() }
    }

    // MARK: - Internal API

    /// Stores the enabled/disabled background colours and immediately applies the one that
    /// matches the current `isEnabled` state. When `disabled` is `nil` the enabled colour is
    /// used for both states (no dimming). Called by `UIButton.withStyle(_:)`.
    func setStatefulBackgroundColors(enabled: UIColor?, disabled: UIColor?) {
        enabledBackgroundColor = enabled
        disabledBackgroundColor = disabled
        applyStatefulBackgroundColor()
    }

    // MARK: - Private Helpers

    private func applyStatefulBackgroundColor() {
        backgroundColor = isEnabled ? enabledBackgroundColor : (disabledBackgroundColor ?? enabledBackgroundColor)
    }
}
