import SwiftUI

/// The orders list (screens.md §2 G12 screen 1 and §7 G12; website `orders/page.tsx`; Figma does not
/// draw it, decision D-12): back and "Commandes", the design-system tabs "Achats (n)" and "Ventes (n)"
/// with the server's counters, then the orders as rows in the list container: photo, title (×n for a
/// bundle), the server's status, "T-000104 · @amina · 4 oct. 2026" and the amount. A row opens the order.
///
/// States per tab: a skeleton while the first page loads, the error (offline included) with Retry, the
/// website's empty text, pull-to-refresh, the pagination footer, a quiet reload after a while in the
/// background, and the new status of an order changed on its screen.
struct OrdersListView: View {
    @State private var model: OrdersListViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(OrderChangeCenter.self) private var orderChanges
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(api: OrdersApi) {
        _model = State(initialValue: OrdersListViewModel(api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.ordersTitle), onBack: { dismiss() })
        } content: {
            VStack(spacing: 0) {
                TaleedTabs(titles: OrdersTab.allCases.map(tabTitle), selection: tabSelection)
                    .accessibilityIdentifier("orders.tabs")
                OrdersTabContent(list: model.list(model.selectedTab), tab: model.selectedTab, refresh: { await model.refresh() })
                    // A fresh scroll position per tab.
                    .id(model.selectedTab)
            }
        }
        .task { await model.load() }
        .onAppear { model.apply(orderChanges) }
        .onChange(of: orderChanges.seq) { _, _ in model.apply(orderChanges) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(get: { model.selectedTab.rawValue }, set: { index in
            guard let tab = OrdersTab(rawValue: index), tab != model.selectedTab else { return }
            Task { await model.select(tab) }
        })
    }

    /// "Achats (10)", as the website's tabs, once the counters are known.
    private func tabTitle(_ tab: OrdersTab) -> String {
        let title = l10n.string(tab == .purchases ? .ordersPurchases : .ordersSales)
        guard let count = model.count(tab) else { return title }
        return l10n.format(.appMyListingsTabCount, title, count)
    }
}

/// One tab: its states, then the rows in the design-system list container.
private struct OrdersTabContent: View {
    let list: PagedList<OrderRow>
    let tab: OrdersTab
    let refresh: () async -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts

    var body: some View {
        Group {
            if list.hasLoaded {
                ScrollView {
                    if list.items.isEmpty {
                        EmptyState(title: l10n.string(tab == .purchases ? .ordersEmptyPurchases : .ordersEmptySales),
                                   icon: tab == .purchases ? .truck : .storefront)
                            .padding(.top, TaleedSpacing.s48)
                            .accessibilityIdentifier("orders.empty")
                    } else {
                        LazyVStack(spacing: TaleedSpacing.s8) {
                            ForEach(list.items) { order in
                                OrderRowView(order: order) { router.push(.order(id: order.id)) }
                            }
                            PaginationFooter(list: list)
                        }
                        .padding(TaleedSpacing.s8)
                        .background(TaleedColor.surfaceGrouped,
                                    in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.vertical, TaleedSpacing.s16)
                    }
                }
                .refreshable { await refresh() }
                .accessibilityIdentifier("orders.scroll")
            } else if let error = list.error {
                ErrorStateView(error: error) { Task { await list.reload() } }
            } else {
                OrdersSkeleton()
            }
        }
        .onChange(of: list.refreshError) { _, error in
            if let error { toasts.show(error: error) }
        }
    }
}

/// A row: the photo (56 x 72, as the checkout item), the title with "×2" for a bundle, the server's
/// status badge, "T-000104 · @amina · 4 oct. 2026", and the amount at the end. From accessibility text
/// sizes on, the row stacks: photo, title (2 lines), badge, amount, then the meta line, so no word breaks.
struct OrderRowView: View {
    let order: OrderRow
    let onTap: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        thumbnail
                        title(lineLimit: 2)
                        badge
                        price
                        metaText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: TaleedSpacing.s12) {
                        thumbnail
                        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                            title(lineLimit: 1)
                            badge
                            metaText
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        price
                            .layoutPriority(1)
                    }
                }
            }
            .padding(TaleedSize.productListRowPadding)
            .background(TaleedColor.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: TaleedSize.productListRowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("orders.row.\(order.number)")
    }

    private var thumbnail: some View {
        RemoteImage(url: order.imageURL)
            .frame(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
    }

    private func title(lineLimit: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
            Text(verbatim: order.title.isolatedByContent)
                .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(lineLimit)
            if order.itemCount > 1 {
                TaleedBadge(title: "×\(order.itemCount)", tone: .neutral)
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize()
            }
        }
    }

    private var badge: some View {
        TaleedBadge(title: order.statusLabel, tone: order.status.badgeTone)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var price: some View {
        PriceText(amount: order.amount, style: TaleedFont.buttonMedium)
    }

    private var metaText: some View {
        Text(meta)
            .taleedFont(TaleedFont.meta)
            .foregroundStyle(TaleedColor.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
    }

    /// "T-000104 · @amina · 4 oct. 2026"; a deleted member reads "Compte supprimé".
    private var meta: String {
        let counterpart = order.counterpart?.displayName.isolatedLeftToRight ?? l10n.string(.ordersDeletedAccount)
        return [order.number.isolatedLeftToRight, counterpart,
                OrderText.date(order.createdAt, locale: l10n.language.formattingLocale)].joined(separator: " · ")
    }
}

/// Rows of the list's shape while the first page loads.
private struct OrdersSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(spacing: TaleedSpacing.s8) {
                ForEach(0 ..< 5, id: \.self) { _ in
                    HStack(spacing: TaleedSpacing.s12) {
                        SkeletonBlock(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight,
                                      radius: TaleedRadius.s)
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock(height: 16)
                            SkeletonBlock(width: 90, height: 18, color: TaleedColor.surfaceSubtle)
                            SkeletonBlock(width: 160, height: 12)
                        }
                        SkeletonBlock(width: 64, height: 16)
                    }
                    .padding(TaleedSize.productListRowPadding)
                    .background(TaleedColor.surfacePrimary,
                                in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
                }
            }
            .padding(TaleedSpacing.s8)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s16)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
    }
}

extension OrderState {
    /// The badge tone of a status, after the website's scale: amber when the buyer still owes an
    /// action or the order is frozen, blue while Taleed holds the money, green once it moved, grey when
    /// closed.
    var badgeTone: TaleedTone {
        switch self {
        case .pendingPayment, .disputed: .warning
        case .paid, .prepared, .shipped: .brand
        case .delivered, .completed: .success
        case .cancelled, .refunded, .unknown: .neutral
        }
    }
}
