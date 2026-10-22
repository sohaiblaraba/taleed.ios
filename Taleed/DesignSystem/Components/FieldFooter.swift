import SwiftUI

/// The line under a field: the helper or error, then a quiet "n / max" counter (read left to right).
struct FieldFooter: View {
    let message: String?
    let color: Color
    let counter: String?

    var body: some View {
        if counter != nil || message != nil {
            HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                if let message {
                    FieldHelper(text: message, color: color)
                } else {
                    Spacer(minLength: 0)
                }
                if let counter {
                    Text(verbatim: counter)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

extension String {
    /// "12 / 80": the field's length as the API counts it (UTF-16 units) against its maximum.
    func fieldCounter(max: Int) -> String { "\(utf16.count) / \(max)" }
}
