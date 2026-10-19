import SwiftUI

/// The wardrobe tab (screens.md §2 G5 screen 3, §7 G5): "9 articles" and "Filtrer", then the product
/// grid (Figma "Home" grid, two columns) page by page. Reserved and sold items show their strips.
struct MemberWardrobeSection: View {
    let model: MemberProfileViewModel
    let onFilter: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(FavoriteStore.self) private var favorites

    var body: some View {
        let list = model.wardrobe
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            if (model.profile?.wardrobeTotal ?? 0) > 0 { toolbar }
            if list.hasLoaded {
                let items = list.items.filter { !favorites.removedIds.contains($0.id) }
                if items.isEmpty {
                    EmptyState(title: emptyTitle, icon: .storefront)
                } else {
                    ListingGrid(listings: items)
                    PaginationFooter(list: list)
                }
            } else if let error = list.error {
                SectionErrorView(error: error) { Task { await list.reload() } }
            } else {
                SkeletonProductGrid(count: 4)
                    .padding(.horizontal, TaleedLayout.screenMargin)
            }
        }
        .padding(.vertical, TaleedSpacing.s16)
        // A new filter gives a new list: load its first page.
        .task(id: ObjectIdentifier(list)) { await list.loadIfNeeded() }
    }

    /// "Aucune annonce active.", or "Aucune annonce dans la catégorie « Sacs »." with a category.
    private var emptyTitle: String {
        guard let slug = model.wardrobeQuery.category,
              let categories = model.profile?.wardrobeCategories,
              let category = categories.first(where: { $0.slug == slug }) else {
            return l10n.string(.memberNoListings)
        }
        return l10n.format(.memberNoListingsInCategory, WardrobeFilterRules.label(for: category, among: categories))
    }

    private var toolbar: some View {
        HStack(spacing: TaleedSpacing.s8) {
            Text(l10n.format(.memberItemsCount, model.wardrobeCount))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            FilterChip(title: l10n.string(.memberFilter), icon: .slidersHorizontal,
                       tone: model.wardrobeQuery.isFiltered ? .brand : .neutral, action: onFilter)
                .accessibilityIdentifier("member.filter")
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }
}

/// The reviews tab (screens.md §2 G5 screen 4): newest first, 20 a page; each with the author, the
/// date, the stars and the comment (none: stars only).
struct MemberReviewsSection: View {
    let list: PagedList<MemberReview>
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if list.hasLoaded {
                if list.items.isEmpty {
                    EmptyState(title: l10n.string(.reviewsNoReviews), icon: .star)
                } else {
                    LazyVStack(spacing: TaleedSpacing.s8) {
                        ForEach(list.items) { MemberReviewRow(review: $0) }
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    PaginationFooter(list: list)
                }
            } else if let error = list.error {
                SectionErrorView(error: error) { Task { await list.reload() } }
            } else {
                ProgressView()
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(l10n.string(.commonLoading))
            }
        }
        .padding(.vertical, TaleedSpacing.s16)
        .task { await list.loadIfNeeded() }
    }
}

/// A review: the author's avatar and handle (opens their profile), the date, the stars, the comment.
struct MemberReviewRow: View {
    let review: MemberReview
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s12) {
            TaleedAvatar(initials: TaleedAvatar.initials(from: review.author.username ?? review.author.displayName), size: 40,
                         imageURL: review.author.avatarURL, isVerified: review.author.isVerified && !review.author.isOfficial)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                    Text(verbatim: review.author.displayName.isolatedLeftToRight)
                        .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                        .foregroundStyle(TaleedColor.textPrimary)
                        .lineLimit(1)
                    if review.author.isOfficial {
                        TaleedIconView(.sealCheck, size: 14, color: TaleedColor.brandPrimary)
                            .accessibilityLabel(l10n.string(.profileOfficial))
                    }
                    Text(MemberProfileText.memberSince(review.createdAt, locale: l10n.language.formattingLocale))
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.textSecondary)
                }
                RatingStarsView(value: review.rating)
                    .accessibilityElement()
                    .accessibilityLabel(l10n.format(.reviewsStars, review.rating))
                if let comment = review.comment {
                    Text(verbatim: comment)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .naturalDirection(of: comment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TaleedSpacing.s16)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { openAuthor() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(review.author.username == nil ? [] : .isButton)
        .accessibilityAction { openAuthor() }
    }

    private func openAuthor() {
        if let username = review.author.username { router.push(.member(username: username)) }
    }
}

/// Five stars, filled up to the rating, left to right in every language (the website's `RatingStars`).
struct RatingStarsView: View {
    let value: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                // Filled up to the rating, outlined after it (the design system's icons have no filled star).
                StarShape()
                    .fill(star <= value ? TaleedColor.warningIcon : Color.clear)
                    .overlay(StarShape().stroke(star <= value ? TaleedColor.warningIcon : TaleedColor.textSecondary.opacity(0.45),
                                                lineWidth: 1))
                    .frame(width: size, height: size)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// A five-pointed star.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        var path = Path()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = Double(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A list inside a screen that failed to load: the message and "Retry", without leaving the screen.
struct SectionErrorView: View {
    let error: ApiError
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            TaleedIconView(error == .network ? .wifiHigh : .warningCircle, size: 28,
                           color: error == .network ? TaleedColor.textSecondary : TaleedColor.feedbackError)
                .accessibilityHidden(true)
            Text(l10n.message(for: error))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .multilineTextAlignment(.center)
            TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium, action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(TaleedSpacing.s24)
    }
}
