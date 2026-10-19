#if DEBUG
import SwiftUI

/// §6 Composed patterns and the Item Detail pieces of the wireframes.
struct GalleryComposed: View {
    @State private var query = "Nike jacket"
    @State private var tab: ShellTab = .home
    @State private var step = 2
    @State private var photo = 0
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "item-detail", number: "6.3", title: "Item Detail pieces",
                       note: "Spec rows, photo count pill and page dots, sticky CTA bar (size.bottomActionBar).",
                       fullBleed: true) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                specRows(copy)
                photoHero
                    .padding(.horizontal, TaleedLayout.screenMargin)
                VStack(spacing: TaleedSpacing.s16) {
                    BottomActionBar {
                        ItemDetailActions(offerTitle: copy("Faire une offre", "قدّم عرضًا", "Make an offer"),
                                          buyTitle: copy("Acheter", "اشترِ الآن", "Buy now"), onOffer: {}, onBuy: {})
                    }
                    BottomActionBar {
                        ItemDetailActions(offerTitle: copy("Faire une offre", "قدّم عرضًا", "Make an offer"),
                                          buyTitle: copy("Acheter", "اشترِ الآن", "Buy now"), onOffer: {}, onBuy: {})
                    } footer: {
                        BottomNavigation(items: navItems(copy), selection: $tab, drawsBackground: false)
                    }
                }
                .padding(.top, TaleedSpacing.s16)
                .background(TaleedColor.surfaceGrouped)
            }
        }
        GallerySection(id: "search", number: "6.2", title: "Search results pieces",
                       note: "Header with query and filters, saved-search row.", fullBleed: true) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                SearchResultsHeader(text: $query, placeholder: copy("Rechercher un article", "ابحث عن غرض", "Search for an item"),
                                    onBack: {}, backAccessibilityLabel: copy("Retour", "رجوع", "Back"), filters: {
                    ChipRow(spacing: TaleedSpacing.s8) {
                        FilterChip(title: copy("Filtres · 2", "عوامل التصفية · 2", "Filters · 2"), icon: .slidersHorizontal,
                                   tone: .brand) {}
                        FilterChip(title: copy("Alger", "الجزائر", "Algiers"))
                        RemovableFilterChip(title: copy("Taille M", "المقاس M", "Size M"), tone: .neutral) {}
                    }
                })
                .background(TaleedColor.surfaceGrouped)
                SavedSearchRow(title: copy("M’avertir des nouvelles annonces", "نبّهني عند نشر إعلانات جديدة",
                                           "Notify me about new listings")) {}
                    .padding(.horizontal, TaleedLayout.screenMargin)
            }
        }
        GallerySection(id: "sell-steps", number: "6.4", title: "Sell-step pieces", note: "Progress segments, photo tips card.") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                SellStepProgress(current: step)
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
        let photos: [TaleedImage] = [.loginGreenDress, .loginBlueTop, .loginPinkShirt, .loginBrownBag]
        return TabView(selection: $photo) {
            ForEach(photos.indices, id: \.self) { index in
                ProductMediaView(media: .local(Image(taleed: photos[index])), contentMode: .fit)
                    .background(TaleedColor.surfacePrimary)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 240)
        .background(TaleedColor.navy300)
        .overlay(alignment: .bottom) {
            PhotoPageDots(count: photos.count, current: photo).padding(.bottom, TaleedSpacing.s16)
        }
        .overlay(alignment: .bottomTrailing) {
            PhotoCountPill(index: photo + 1, count: photos.count).padding(.trailing, 16).padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
    }

    private func navItems(_ copy: GalleryCopy) -> [BottomNavItem<ShellTab>] {
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
