import SwiftUI

/// An overflow menu ("…"): a popover anchored to its button, its entries in the Taleed type (Body/Large,
/// Plus Jakarta Sans with Alexandria for Arabic), a destructive entry in `feedback/error`, each row a
/// 44 pt target. The system `Menu` draws its entries in the system face, and Arabic in a fallback one.
/// An entry runs once the popover is gone, so it can present a sheet. Android: `TaleedOverflowMenu`.
struct TaleedOverflowMenu<Label: View>: View {
    let items: [AppBarMenuItem]
    let accessibilityLabel: String
    @ViewBuilder let label: Label
    @State private var isPresented = false
    @State private var chosen: AppBarMenuItem?
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The entries' icons grow with their labels (20 pt at the default size).
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    var body: some View {
        Button { isPresented = true } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                entries
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(TaleedColor.surfacePrimary)
                    .environment(\.locale, locale)
                    .environment(\.layoutDirection, layoutDirection)
                    .onDisappear {
                        let action = chosen?.action
                        chosen = nil
                        action?()
                    }
            }
    }

    private var hasIcons: Bool { items.contains { $0.icon != nil } }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    // The destructive entries make their own group, after a heavier divider (as system menus).
                    let startsDestructive = item.isDestructive && !items[index - 1].isDestructive
                    Rectangle().fill(startsDestructive ? TaleedColor.surfaceGrouped : TaleedColor.borderSubtle)
                        .frame(height: startsDestructive ? 8 : 1)
                }
                Button {
                    chosen = item
                    isPresented = false
                } label: {
                    let color = item.isDestructive ? TaleedColor.feedbackError : TaleedColor.textPrimary
                    HStack(spacing: TaleedSpacing.s12) {
                        // Entries without an icon keep its place, so the titles line up.
                        if hasIcons {
                            TaleedIconView(item.icon ?? .x, size: min(iconSize, 32), color: color)
                                .opacity(item.icon == nil ? 0 : 1)
                                .accessibilityHidden(true)
                        }
                        Text(item.title)
                            .taleedFont(TaleedFont.bodyLarge)
                            .foregroundStyle(color)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, TaleedSpacing.s16)
                    .padding(.vertical, TaleedSpacing.s12)
                    .frame(minHeight: TaleedSize.touchTargetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .frame(minWidth: 200, idealWidth: dynamicTypeSize.isAccessibilitySize ? 360 : 260, maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
        // As a system menu, the entries stop growing at Accessibility 2, where every word of an entry
        // still fits its line ("Voir l'annonce" broke inside "annonce" at the largest size).
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
