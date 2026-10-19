import SwiftUI
import UIKit

/// Text that never cuts or breaks a word: it wraps only between words and grows, and when one word
/// is still wider than the room (very large text in a narrow column), the whole text steps down in
/// size until that word fits (design-system §7, "Condition always explicit", decision D-9). Android
/// does the same in `ConditionTag` and `PriceText`.
///
/// `breakable` says where the text may break: spaces by default. A price passes only the space
/// before the currency, so digit groups and "DA" / "د.ج." stay whole.
struct WordFittingText: View {
    let text: String
    let style: TaleedTextStyle
    var alignment: TextAlignment = .leading
    var monospacedDigits = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    /// The sizes tried, largest first; the smallest is used when nothing fits.
    static let scales: [CGFloat] = [1, 0.92, 0.85, 0.78, 0.71, 0.64, 0.57, 0.5]

    var body: some View {
        let category = UIContentSizeCategory(dynamicTypeSize)
        let widths = Self.scales.map { scale in
            Self.widestWord(in: text, style: style.scaled(by: scale), sizeCategory: category, tracks: !locale.isArabic)
        }
        WidestWordLayout(widestWords: widths) {
            ForEach(Self.scales.indices, id: \.self) { index in
                Text(verbatim: text)
                    .taleedFont(style.scaled(by: Self.scales[index]))
                    .digitsMonospaced(monospacedDigits)
                    .multilineTextAlignment(alignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityRepresentation { Text(verbatim: text) }
    }

    /// The width of the widest word of `text` (split at spaces and line breaks) in `style`.
    @MainActor
    static func widestWord(in text: String, style: TaleedTextStyle, sizeCategory: UIContentSizeCategory,
                           tracks: Bool = true) -> CGFloat {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        // One point of slack so rounding never pushes a word onto two lines.
        return (words.map { style.width(of: String($0), sizeCategory: sizeCategory, tracks: tracks) }.max() ?? 0) + 1
    }
}

private extension View {
    @ViewBuilder
    func digitsMonospaced(_ enabled: Bool) -> some View {
        if enabled { monospacedDigit() } else { self }
    }
}

extension TaleedTextStyle {
    /// The width of `text` on one line in this style at a Dynamic Type size.
    @MainActor
    func width(of text: String, sizeCategory: UIContentSizeCategory, tracks: Bool = true) -> CGFloat {
        let font = uiFont(sizeCategory: sizeCategory)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if tracks, letterSpacing != 0 { attributes[.kern] = letterSpacing * font.pointSize / size }
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    /// The same style at `factor` times the size (line height and letter spacing follow).
    func scaled(by factor: CGFloat) -> TaleedTextStyle {
        guard factor != 1 else { return self }
        return TaleedTextStyle(size: size * factor, weight: weight, lineHeight: lineHeight.map { $0 * factor },
                               letterSpacing: letterSpacing * factor, relativeTo: relativeTo)
    }
}

/// Shows the first of its children (one per size, largest first) whose widest word fits the proposed
/// width; the others are not shown. Without a width (ideal size) it shows the first.
private struct WidestWordLayout: Layout {
    let widestWords: [CGFloat]

    private func chosen(for width: CGFloat?, count: Int) -> Int {
        guard let width, width.isFinite else { return 0 }
        let fitting = widestWords.prefix(count).firstIndex { $0 <= width }
        return fitting ?? max(0, count - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        return subviews[chosen(for: proposal.width, count: subviews.count)].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The same choice as for the size: the proposal, not the (hugging) bounds.
        let index = chosen(for: proposal.width ?? bounds.width, count: subviews.count)
        for (position, subview) in subviews.enumerated() {
            if position == index {
                subview.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
            } else {
                // Parked far outside the screen with no room: never drawn where it can be seen.
                subview.place(at: CGPoint(x: bounds.minX - 100_000, y: bounds.minY), anchor: .topLeading, proposal: .zero)
            }
        }
    }
}
