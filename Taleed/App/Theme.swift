import SwiftUI

/// The one place for the look of the app until the Figma design system arrives.
enum Theme {
    /// Taleed blue, `#0052ff`.
    static let primary = Color(red: 0, green: 0x52 / 255, blue: 1)
    /// The smallest touch target (Apple's 44 pt).
    static let minTouchTarget: CGFloat = 44
}
