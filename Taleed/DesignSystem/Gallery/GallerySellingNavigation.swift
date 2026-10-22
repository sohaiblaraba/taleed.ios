#if DEBUG
import SwiftUI

/// §4 Selling and checkout controls.
struct GallerySellingAndCheckout: View {
    @State private var photoCounts = [0, 1, 3, 5]
    @State private var delivery = 0
    @State private var promo = ""
    @State private var promoInvalid = "WELCOM"
    @Environment(\.locale) private var locale

    private static let photoSources: [TaleedImage] = [.loginGreenDress, .loginBlueTop, .loginPinkShirt, .loginBrownBag,
                                                      .loginHeadphones]

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "photos", number: "4.1", title: "Photo uploader", note: "Variant A, 0 / 1 / 3 / 5 photos (D-6).") {
            VStack(spacing: TaleedSpacing.s24) {
                ForEach(photoCounts.indices, id: \.self) { index in
                    PhotoUploader(
                        photos: photos(count: photoCounts[index]),
                        onAdd: { photoCounts[index] = min(5, photoCounts[index] + 1) },
                        onRemove: { _ in photoCounts[index] = max(0, photoCounts[index] - 1) },
                        onMakeCover: { _ in }
                    )
                }
            }
        }
        GallerySection(id: "document", number: "4.1", title: "Document photo",
                       note: "One 16:9 slot from the uploader's parts (identity verification): empty, then picked.") {
            VStack(spacing: TaleedSpacing.s24) {
                ForEach([false, true], id: \.self) { picked in
                    DocumentPhotoSlot(label: copy("Pièce d’identité", "وثيقة الهوية", "ID document"),
                                      hint: copy("Carte d’identité ou passeport, recto lisible",
                                                 "بطاقة التعريف أو جواز السفر، وجه أمامي واضح",
                                                 "ID card or passport, readable front side"),
                                      image: picked ? Image(taleed: .loginDrapedFabric) : nil,
                                      removeLabel: copy("Retirer la photo", "إزالة الصورة", "Remove photo"),
                                      onPick: {}, onRemove: {})
                }
            }
        }
        GallerySection(id: "checkout", number: "4.3–4.4", title: "Checkout item, delivery option") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                CheckoutItem(title: "Pantalon en toile garçon", price: 800, media: .local(Image(taleed: .loginDrapedFabric)))
                    .padding(.bottom, TaleedSpacing.s16)
                Eyebrow(text: copy("Mode de livraison", "طريقة التوصيل", "Delivery method"))
                DeliveryOption(icon: .house, title: copy("Livraison à domicile", "التوصيل إلى المنزل", "Home delivery"),
                               description: copy("Livré à votre adresse par notre partenaire", "يوصله شريكنا إلى عنوانك",
                                                 "Delivered to your address by our delivery partner"),
                               selected: delivery == 0) { delivery = 0 }
                DeliveryOption(icon: .storefront, title: copy("Retrait en stop-desk", "الاستلام من مكتب التوصيل", "Stop-desk pickup"),
                               description: copy("Retirez votre colis au bureau partenaire de votre choix",
                                                 "استلم طردك من المكتب الشريك الذي تختاره",
                                                 "Pick up your parcel at the partner desk of your choice"),
                               selected: delivery == 1) { delivery = 1 }
            }
        }
        GallerySection(id: "summary", number: "4.5–4.6", title: "Order summary, promo code", note: "Pending, then resolved.") {
            VStack(spacing: TaleedSpacing.s24) {
                summary(copy, shipping: nil, total: nil)
                summary(copy, shipping: delivery == 0 ? 600 : 400, total: delivery == 0 ? 1490 : 1290)
                PromoCodeField(code: $promo) {}
                PromoCodeField(code: $promoInvalid,
                               error: copy("Ce code promo n’est pas valide.", "رمز التخفيض غير صالح.",
                                           "This promo code is not valid.")) {}
            }
        }
    }

    private func photos(count: Int) -> [PhotoUploaderItem] {
        (0..<count).map { PhotoUploaderItem(id: "\($0)", media: .local(Image(taleed: Self.photoSources[$0]))) }
    }

    private func summary(_ copy: GalleryCopy, shipping: Int?, total: Int?) -> some View {
        OrderSummary(
            lines: [
                OrderSummaryLine(id: "item", label: copy("Article", "الغرض", "Item"), amount: 800),
                OrderSummaryLine(id: "fee", label: copy("Frais de plateforme et de service", "رسوم المنصة والخدمة",
                                                        "Platform & service fee"), amount: 90, onInfo: {}),
                OrderSummaryLine(id: "shipping", label: copy("Livraison", "التوصيل", "Shipping"), amount: shipping),
            ],
            totalLabel: copy("Total à payer", "المجموع المستحق", "Total to pay"),
            total: total
        )
    }
}

/// §5 Navigation patterns and §6 composed modules.
struct GalleryNavigation: View {
    @State private var search = "Nike jacket"
    @State private var tab: AppTab = .home
    @State private var showsSheet = false
    @State private var showsModal = false
    @State private var showsHero = true
    @State private var sort = 0
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "app-bars", number: "5.1", title: "App bars", note: "56 pt (D-1), max two actions.", fullBleed: true) {
            VStack(spacing: TaleedSpacing.s8) {
                BrandAppBar(showsDivider: true, onNotifications: {}, avatarInitials: "NT", onAvatar: {})
                TaleedTopAppBar(title: copy("Profil", "الملف الشخصي", "Profile"))
                TaleedTopAppBar(title: copy("Paiement", "الدفع", "Checkout"), onBack: {},
                                // The shield opens the buyer-protection page (Saad, 2026-10-22).
                                actions: [AppBarAction(icon: .shieldCheck, accessibilityLabel: "Buyer protection") {}])
                TaleedTopAppBar(title: copy("Détail de l’article", "تفاصيل الغرض", "Item details"), onBack: {},
                                actions: [AppBarAction(icon: .shieldCheck, accessibilityLabel: "Buyer protection", isCircled: true) {}])
                TaleedTopAppBar(title: copy("Détail de l’article", "تفاصيل الغرض", "Item details"), onBack: {},
                                actions: [AppBarAction(icon: .shareNetwork, accessibilityLabel: "Share",
                                                       color: TaleedColor.textPrimary) {},
                                          AppBarAction(icon: .dotsThree,
                                                       accessibilityLabel: DesignSystemStrings.string(.commonMore, locale: locale),
                                                       color: TaleedColor.textPrimary) {}])
                SearchAppBar(text: $search, placeholder: copy("Rechercher un article", "ابحث عن غرض", "Search for an item"))
                PageHeading(eyebrow: copy("Vendre", "بيع", "Sell"), title: copy("Vendre un article", "بيع غرض", "Sell an item"))
                VStack(spacing: 0) {
                    ListRow(label: copy("Paramètres", "الإعدادات", "Settings"), showsChevron: true) {}
                    ListRow(label: copy("Version", "الإصدار", "Version"), trailingText: "1.0.0 (1)".isolatedLeftToRight)
                    ListRow(label: "Design system", leadingIcon: .sparkle, showsChevron: true, showsDivider: false) {}
                }
                .background(TaleedColor.surfacePrimary)
            }
            .background(TaleedColor.surfaceGrouped)
        }
        GallerySection(id: "bottom-nav", number: "5.2", title: "Bottom navigation",
                       note: "Five destinations (D-2). One label size for all five; never truncated. Only the top corners "
                           + "are rounded; the fill runs under the home indicator, and the items keep max(16, inset) below "
                           + "them, not 16 + inset (D-15). Inactive labels and icons in navInactive (navy/600 #575E6F, "
                           + "6.5:1), not Figma's navy/400 (D-9b).",
                       fullBleed: true) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                GalleryCaption(text: copy("Avec l’indicateur d’accueil (34) : la barre se pose sur la marge",
                                          "مع مؤشر الشاشة الرئيسية (34): يستقر الشريط على الهامش",
                                          "With a home indicator (34): the bar sits on the inset"))
                    .padding(.horizontal, TaleedLayout.screenMargin)
                GalleryScreenBottom(inset: 34) { bottomNavigation(copy) }
                GalleryCaption(text: copy("Sans indicateur d’accueil : 16 sous les éléments",
                                          "بدون مؤشر الشاشة الرئيسية: 16 أسفل العناصر",
                                          "Without a home indicator: 16 below the items"))
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s8)
                GalleryScreenBottom(inset: 0) { bottomNavigation(copy) }
            }
            .padding(.top, TaleedSpacing.s16)
            .background(TaleedColor.surfaceGrouped)
        }
        GallerySection(id: "sheets", number: "5.3–5.4", title: "Bottom sheet, confirmation modal") {
            VStack(spacing: TaleedSpacing.s16) {
                sortSheet(copy)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: TaleedSize.bottomSheetTopRadius,
                                                      topTrailingRadius: TaleedSize.bottomSheetTopRadius))
                    .taleedShadow(TaleedElevation.level2)
                ZStack {
                    TaleedColor.textPrimary.opacity(0.5)
                    deleteModal(copy).padding(TaleedSpacing.s16)
                }
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.l))
                GalleryCaption(text: copy("« Supprimer » appuyé", "«حذف» مضغوط", "\u{201C}Delete\u{201D} pressed"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    TaleedColor.textPrimary.opacity(0.5)
                    deleteModal(copy, forcesPressed: true).padding(TaleedSpacing.s16)
                }
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.l))
                HStack(spacing: TaleedSpacing.s8) {
                    TaleedButton(title: copy("Ouvrir la feuille", "فتح الورقة", "Open sheet"), kind: .tertiary, size: .medium) {
                        showsSheet = true
                    }
                    TaleedButton(title: copy("Ouvrir la fenêtre", "فتح النافذة", "Open modal"), kind: .danger, size: .medium) {
                        showsModal = true
                    }
                }
            }
            .sortBottomSheet(isPresented: $showsSheet, title: sortTitle(copy), options: sortOptions(copy), selection: $sort) {}
        }
        .taleedConfirmation(isPresented: showsModal) { deleteModal(copy) }
        GallerySection(id: "hero", number: "6", title: "Hero banner, trust strip") {
            VStack(spacing: TaleedSpacing.s16) {
                if showsHero {
                    HeroBanner(title: DesignSystemStrings.string(.homeHeroTitle, locale: locale),
                               ctaLabel: DesignSystemStrings.string(.homeHeroCta, locale: locale),
                               onCta: {}, onDismiss: { showsHero = false })
                } else {
                    TaleedButton(title: "Reset", kind: .hyperlink, size: .medium) { showsHero = true }
                }
                TrustStrip()
            }
        }
        GallerySection(id: "trust-full", number: "6", title: "Trust strip, full bleed", fullBleed: true) {
            TrustStrip(style: .fullBleed)
        }
    }

    private func bottomNavigation(_ copy: GalleryCopy) -> some View {
        TaleedBottomNavigation(items: [
            BottomNavItem(id: AppTab.home, icon: .houseLine, title: copy("Accueil", "الرئيسية", "Home")),
            BottomNavItem(id: .explore, icon: .magnifyingGlass, title: copy("Explorer", "استكشاف", "Explore")),
            BottomNavItem(id: .sell, icon: .plus, title: copy("Vendre", "بيع", "Sell")),
            BottomNavItem(id: .messages, icon: .chatCircleText, title: copy("Messages", "الرسائل", "Messages")),
            BottomNavItem(id: .profile, icon: .user, title: copy("Profil", "الملف الشخصي", "Profile")),
        ], selection: $tab)
    }

    private func sortTitle(_ copy: GalleryCopy) -> String { copy("Trier par", "الترتيب حسب", "Sort by") }

    private func sortOptions(_ copy: GalleryCopy) -> [SheetOption<Int>] {
        [
            SheetOption(id: 0, title: copy("Plus récents", "الأحدث", "Newest")),
            SheetOption(id: 1, title: copy("Prix croissant", "السعر تصاعديًا", "Price: low to high")),
            SheetOption(id: 2, title: copy("Prix décroissant", "السعر تنازليًا", "Price: high to low")),
        ]
    }

    private func sortSheet(_ copy: GalleryCopy) -> some View {
        SortSheetContent(title: sortTitle(copy), options: sortOptions(copy), selection: $sort, onApply: {}, onClose: {})
    }

    private func deleteModal(_ copy: GalleryCopy, forcesPressed: Bool = false) -> ConfirmationModalCard {
        ConfirmationModalCard(
            title: copy("Supprimer l’annonce ?", "حذف الإعلان؟", "Delete listing?"),
            message: copy("Cette action est définitive.", "هذا الإجراء نهائي.", "This action is permanent."),
            confirmTitle: copy("Supprimer", "حذف", "Delete"),
            onConfirm: { showsModal = false },
            onCancel: { showsModal = false },
            forcesConfirmPressed: forcesPressed
        )
    }
}
#endif
