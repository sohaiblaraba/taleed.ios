import SwiftUI

/// Tabs (design-system §2.10): equal widths over a 1 pt `border/subtle` line, a 3 pt indicator under
/// the active one. Labels keep one line: when they no longer fit in equal widths (large text), the
/// row scrolls sideways instead of breaking words (Android's TaleedTabs). `horizontalInset` keeps the
/// labels off the screen edges (the page gutter) in both layouts; the line still runs edge to edge.
struct TaleedTabs: View {
    let titles: [String]
    @Binding var selection: Int
    var horizontalInset: CGFloat = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualWidthRow { tabs(labelPadding: TaleedSpacing.s8) }
                .padding(.horizontal, horizontalInset)
            // Too long for equal widths: each tab hugs its label and shares what is left.
            FillRow { tabs(labelPadding: TaleedSpacing.s4) }
                .padding(.horizontal, horizontalInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) { tabs(labelPadding: TaleedSpacing.s8) }
                    .padding(.horizontal, horizontalInset)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: selection)
    }

    private func tabs(labelPadding: CGFloat) -> some View {
        ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
            let isActive = index == selection
            Button {
                selection = index
            } label: {
                VStack(spacing: TaleedSpacing.s12) {
                    Text(title)
                        .taleedFont(TaleedFont.buttonMedium)
                        .foregroundStyle(isActive ? TaleedColor.brandPrimary : TaleedColor.textBody)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, labelPadding)
                    Capsule()
                        .fill(isActive ? TaleedColor.brandPrimary : .clear)
                        .frame(height: 3)
                }
                .padding(.top, TaleedSpacing.s12)
                .frame(maxWidth: .infinity, minHeight: TaleedSize.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        }
    }
}

/// Children of equal width sharing the row. Its ideal width is the widest child times the count, so
/// in a `ViewThatFits` it is chosen only while every child fits its equal share.
private struct EqualWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let count = CGFloat(subviews.count)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest * count
        let share = width / count
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: share, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let share = bounds.width / CGFloat(max(1, subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + share * CGFloat(index), y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: share, height: bounds.height))
        }
    }
}

/// Children at their ideal widths plus an equal share of the room left. Its ideal width is the sum of
/// theirs, so in a `ViewThatFits` it is chosen only while every child fits at its own width.
private struct FillRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? ideal.reduce(0) { $0 + $1.width }
        return CGSize(width: width, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let extra = max(0, bounds.width - widths.reduce(0, +)) / CGFloat(max(1, subviews.count))
        var originX = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: originX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width + extra, height: bounds.height))
            originX += width + extra
        }
    }
}
