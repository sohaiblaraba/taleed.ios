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

    private var entries: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
                }
                Button {
                    chosen = item
                    isPresented = false
                } label: {
                    Text(item.title)
                        .taleedFont(TaleedFont.bodyLarge)
                        .foregroundStyle(item.isDestructive ? TaleedColor.feedbackError : TaleedColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TaleedSpacing.s16)
                        .padding(.vertical, TaleedSpacing.s12)
                        .frame(minHeight: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
