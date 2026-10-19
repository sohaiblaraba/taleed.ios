import SwiftUI

/// The bundle builder (screens.md §2 G10 screen 4 and §7 G10; website `member/bundle-shop.tsx`):
/// "Sélectionne les articles de ton lot" over the seller's wardrobe, "Ajouter" / "Retirer" under each
/// item (items not for sale cannot be added), at most 20, and "Voir le lot (N articles)" at the bottom,
/// which saves the selection and opens the review. No total on the device (decision 7): the review shows
/// the server's.
///
/// States: loading, error with Retry (offline included), "no longer available", a seller the member
/// cannot bundle with, an empty wardrobe, pagination and pull-to-refresh.
struct BundleBuilderView: View {
    @State private var model: BundleBuilderViewModel
    @State private var hasAppeared = false
    let route: AppRoute
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shellTab) private var shellTab

    init(username: String, route: AppRoute, dependencies: BundleDependencies) {
        self.route = route
        _model = State(initialValue: BundleBuilderViewModel(username: username, members: dependencies.members,
                                                            bundles: dependencies.bundles))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.bundleBannerTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            reviewBar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if let shellTab { toasts.setBottomBarHeight(height, tab: shellTab, route: route) }
            }
        }
        .task { await model.loadIfNeeded() }
        .onAppear {
            // Back from a listing or the review: the bundle may have changed there.
            if hasAppeared { Task { await model.resync() } }
            hasAppeared = true
        }
        .onChange(of: model.notice) { _, error in
            guard let error else { return }
            model.notice = nil
            toasts.show(error: error)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.load() } }, onBack: { dismiss() })
            }
        } else if let profile = model.profile {
            if model.canBuild {
                PagedListView(list: model.wardrobe) { listings in
                    header(profile)
                    grid(listings)
                } empty: {
                    EmptyState(title: l10n.string(.memberNoListings), icon: .storefront)
                }
                .accessibilityIdentifier("bundle.builder")
            } else {
                MessageStateView(text: l10n.string(.appBundleNotAvailable)) {
                    TaleedButton(title: l10n.string(.listingViewProfile), kind: .tertiary, size: .medium) {
                        router.push(.member(username: profile.username))
                    }
                }
            }
        } else {
            LoadingStateView()
        }
    }

    private func header(_ profile: MemberProfile) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            SellerRow(name: profile.displayName, reputation: l10n.string(.bundleSellerLots), imageURL: profile.avatarURL,
                      isVerified: profile.isVerified || profile.isOfficial,
                      verifiedLabel: l10n.string(profile.isOfficial ? .profileOfficial : .profileVerified)) {
                router.push(.member(username: profile.username))
            }
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                SectionTitle(text: l10n.string(.bundleSelectItems))
                Text(l10n.string(.bundleBannerBody))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isFull {
                InlineAlert(kind: .info, title: l10n.format(.appBundleMaxItems, BundleBuilderRules.maxItems))
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s16)
    }

    private func grid(_ listings: [ListingSummary]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: TaleedLayout.productGridGap, alignment: .top),
                            GridItem(.flexible(), alignment: .top)],
                  spacing: TaleedSpacing.s16) {
            ForEach(listings) { listing in
                BundlePickCard(listing: listing, isSelected: model.isSelected(listing.id), canAdd: model.canAdd(listing)) {
                    model.toggle(listing)
                }
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.bottom, TaleedSpacing.s16)
    }

    @ViewBuilder
    private var reviewBar: some View {
        if model.canBuild, !model.selection.isEmpty {
            BottomActionBar {
                TaleedButton(title: l10n.format(.bundleReview, model.selection.count), kind: .secondary, size: .large,
                             leadingIcon: .storefront, isLoading: model.isSaving, isFullWidth: true) {
                    Task {
                        if let bundleId = await model.review() { router.push(.bundle(id: bundleId)) }
                    }
                }
                .accessibilityIdentifier("bundle.review")
            }
        }
    }
}

/// A wardrobe item in the builder: the listing card (opens the listing), a brand ring when picked, and
/// "Ajouter" / "Retirer" under it. An item not for sale shows its strip and cannot be added.
struct BundlePickCard: View {
    let listing: ListingSummary
    let isSelected: Bool
    let canAdd: Bool
    let toggle: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s8) {
            ListingCardView(listing: listing)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: TaleedSize.productCardRadius, style: .continuous)
                            .strokeBorder(TaleedColor.brandPrimary, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            TaleedButton(title: l10n.string(isSelected ? .bundleRemove : .bundleAdd), kind: isSelected ? .tertiary : .outline,
                         size: .medium, leadingIcon: isSelected ? .check : .plus, isFullWidth: true, action: toggle)
                .disabled(!isSelected && !canAdd)
                .accessibilityLabel("\(l10n.string(isSelected ? .bundleRemove : .bundleAdd)), \(listing.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("bundle.pick")
        }
    }
}
