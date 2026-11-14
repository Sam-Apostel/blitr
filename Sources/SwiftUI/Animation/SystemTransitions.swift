// The built-in animations of system UI, in one place so they can be calibrated against recordings.
//
// They run whenever a capture shows the change, with or without `withAnimation` (as on iOS), unless the
// transaction disables animations.

enum SystemTransitions {
    /// Sheet presentation and dismissal: the card slides up from the bottom edge, the presenter is pushed back.
    /// UIKit drives it with a critically damped spring of about 0.5 s.
    static let sheet = Animation.spring(response: 0.5, dampingFraction: 1.0)
    static let sheetDismiss = Animation.spring(response: 0.42, dampingFraction: 1.0)
    /// Full-screen cover: slides up like a sheet, without a backdrop.
    static let cover = Animation.spring(response: 0.5, dampingFraction: 1.0)
    /// Alert: fades in while scaling down from `alertInitialScale`; fades out on dismissal.
    static let alertPresent = Animation.easeOut(duration: 0.3)
    static let alertDismiss = Animation.easeIn(duration: 0.2)
    static let alertInitialScale: CGFloat = 1.15
    /// Confirmation dialog (action sheet): slides up from the bottom edge, the backdrop fades.
    static let dialog = Animation.spring(response: 0.4, dampingFraction: 1.0)
    /// Navigation push and pop: the new screen slides in from the trailing edge over the old one, which
    /// moves a third of the way out and dims.
    static let navigation = Animation.spring(response: 0.5, dampingFraction: 1.0)
    static let navigationParallax: CGFloat = 0.3
    static let navigationDim = 0.1
    /// Switching tabs is immediate on iOS.
    static let tabSwitch: Animation? = nil
    /// `scroll` steps: UIScrollView's deceleration (`.normal`, 0.998 per ms) towards the target offset,
    /// as an exponential ease-out that settles within `scrollDuration`.
    static let scrollDuration = 0.8
    static let scrollRate = 0.998
}
