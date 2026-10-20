#if DEBUG
import SwiftUI

/// §6 Composed patterns and the Item Detail pieces of the wireframes.
struct GalleryComposed: View {
    @State private var query = "Nike jacket"
    @State private var tab: AppTab = .home
    @State private var step = 2
    @State private var photo = 0
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "item-detail", number: "6.3", title: "Item Detail pieces",
                       note: "Spec rows, photo gallery (page dots, count pill, circle buttons), sticky CTA bar.",
                       fullBleed: true) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                specRows(copy)
                photoHero
                    .padding(.horizontal, TaleedLayout.screenMargin)
                VStack(spacing: TaleedSpacing.s16) {
                    ItemDetailActionBar(makeOfferLabel: copy("Faire une offre", "قدّم عرضًا", "Make an offer"), onMakeOffer: {},
                                        buyNowLabel: copy("Acheter", "اشترِ الآن", "Buy now"), onBuyNow: {})
                    ItemDetailActionBar(makeOfferLabel: copy("Faire une offre", "قدّم عرضًا", "Make an offer"), onMakeOffer: {},
                                        buyNowLabel: copy("Acheter", "اشترِ الآن", "Buy now"), onBuyNow: {}, footer: {
                        TaleedBottomNavigation(items: navItems(copy), selection: $tab, isEmbedded: true)
                    })
                }
                .padding(.top, TaleedSpacing.s16)
                .background(TaleedColor.surfaceGrouped)
            }
        }
        GallerySection(id: "search", number: "6.2", title: "Search results pieces",
                       note: "Header with query and filters, saved-search row.", fullBleed: true) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                SearchHeader(text: $query, placeholder: copy("Rechercher un article", "ابحث عن غرض", "Search for an item"),
                             onBack: {}, filters: {
                    ChipRow(spacing: TaleedSpacing.s8) {
                        FilterChip(title: copy("Filtres · 2", "عوامل التصفية · 2", "Filters · 2"), icon: .slidersHorizontal,
                                   tone: .brand) {}
                        FilterChip(title: copy("Alger", "الجزائر", "Algiers"))
                        RemovableFilterChip(title: copy("Taille M", "المقاس M", "Size M"), tone: .neutral) {}
                    }
                })
                .background(TaleedColor.surfaceGrouped)
                ResultsSummaryRow(countLabel: copy("126 articles", "126 غرضًا", "126 items"),
                                  sortLabel: copy("Plus récents", "الأحدث", "Newest")) {}
                    .padding(.horizontal, TaleedLayout.screenMargin)
                SavedSearchRow(title: copy("M’avertir des nouvelles annonces", "نبّهني عند نشر إعلانات جديدة",
                                           "Notify me about new listings")) {}
                    .padding(.horizontal, TaleedLayout.screenMargin)
            }
        }
        GallerySection(id: "sell-steps", number: "6.4", title: "Sell-step pieces",
                       note: "Progress segments, step intro, category field, photo tips card.") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                StepProgress(current: step)
                StepIntro(step: DesignSystemStrings.format(.appA11yStepProgress, locale: locale, step, 4),
                          title: copy("Ajoutez vos photos", "أضف صورك", "Add your photos"),
                          message: copy("Les annonces avec 4 photos ou plus se vendent plus vite.",
                                        "الإعلانات التي تضم 4 صور أو أكثر تُباع أسرع.",
                                        "Listings with 4 or more photos sell faster."))
                CategoryField(label: copy("Catégorie", "الفئة", "Category"),
                              value: copy("Mode · Vestes", "أزياء · سترات", "Fashion · Jackets")) {}
                HStack(spacing: TaleedSpacing.s8) {
                    TaleedButton(title: "−", kind: .tertiary, size: .small) { step = max(1, step - 1) }
                    TaleedButton(title: "+", kind: .tertiary, size: .small) { step = min(4, step + 1) }
                }
                PhotoTipsCard(title: copy("Des photos qui vendent", "صور تجذب المشترين", "Photos that sell"),
                              tips: [copy("Lumière naturelle", "ضوء طبيعي", "Natural light"),
                                     copy("Fond uni", "خلفية سادة", "Plain background"),
                                     copy("Montrez les défauts", "أظهر أي عيوب", "Show any flaws")])
            }
        }
    }

    private func specRows(_ copy: GalleryCopy) -> some View {
        VStack(spacing: 0) {
            SpecRow(label: copy("Marque", "العلامة", "Brand"), value: "Shein")
            SpecRow(label: copy("Taille", "المقاس", "Size"), value: "M")
            SpecRow(label: copy("État", "الحالة", "Condition")) { ConditionTag(.veryGood) }
            SpecRow(label: copy("Catégorie", "الفئة", "Category"),
                    value: copy("Femmes › Vêtements", "نساء › ملابس", "Women › Clothes"), showsDivider: false) {}
        }
        .background(TaleedColor.surfacePrimary)
    }

    private var photoHero: some View {
        let photos: [ProductMedia] = [.loginGreenDress, .loginBlueTop, .loginPinkShirt, .loginBrownBag]
            .map { .local(Image(taleed: $0)) }
        return VStack(spacing: TaleedSpacing.s16) {
            ItemPhotoGallery(photos: photos, height: 240, current: $photo) {
                VStack {
                    HStack {
                        GalleryCircleButton(icon: .arrowLeft, accessibilityLabel: copyBack) {}
                        Spacer()
                        GalleryCircleButton(icon: .shareNetwork, accessibilityLabel: "Share") {}
                        GalleryCircleButton(icon: .heartFill, accessibilityLabel: DesignSystemStrings.string(.favoriteAdd, locale: locale),
                                            tone: .favorite,
                                            selectedDescription: DesignSystemStrings.string(.favoriteSaved, locale: locale)) {}
                    }
                    Spacer()
                }
                .padding(TaleedSpacing.s12)
            }
            ItemPhotoGallery(photos: photos, height: 200, contentMode: .fill, indicator: .count, current: $photo)
        }
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
    }

    private var copyBack: String { DesignSystemStrings.string(.commonBack, locale: locale) }

    private func navItems(_ copy: GalleryCopy) -> [BottomNavItem<AppTab>] {
        [
            BottomNavItem(id: .home, icon: .houseLine, title: copy("Accueil", "الرئيسية", "Home")),
            BottomNavItem(id: .explore, icon: .magnifyingGlass, title: copy("Explorer", "استكشاف", "Explore")),
            BottomNavItem(id: .sell, icon: .plus, title: copy("Vendre", "بيع", "Sell")),
            BottomNavItem(id: .messages, icon: .chatCircleText, title: copy("Messages", "الرسائل", "Messages")),
            BottomNavItem(id: .profile, icon: .user, title: copy("Profil", "الملف الشخصي", "Profile")),
        ]
    }
}
#endif
