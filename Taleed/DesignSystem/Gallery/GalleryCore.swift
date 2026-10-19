#if DEBUG
import SwiftUI

/// §2 Core components.
struct GalleryCoreComponents: View {
    @Binding var toast: ToastItem?
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GalleryButtons()
        GallerySection(id: "icon-buttons", number: "2.2–2.3", title: "Icon button, favorite control") {
            GalleryIconButtons()
        }
        GallerySection(id: "fields", number: "2.4–2.6", title: "Text field, select, text area") {
            GalleryFields()
        }
        GallerySection(id: "chips", number: "2.7", title: "Chips and filters", fullBleed: true) {
            GalleryChips()
        }
        GallerySection(id: "badges", number: "2.8–2.10", title: "Badges, condition tags, tabs") {
            GalleryTags()
        }
        GallerySection(id: "avatars", number: "2.11", title: "Avatar and seller row") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                HStack(spacing: TaleedSpacing.s12) {
                    ForEach([32, 40, 48, 56, 72] as [CGFloat], id: \.self) { size in
                        TaleedAvatar(initials: "LN", size: size, isVerified: size >= 40 && size <= 56)
                    }
                }
                GalleryCaption(text: copy("Style des maquettes (36, 44)", "نمط النماذج (36، 44)", "Wireframe style (36, 44)"))
                HStack(spacing: TaleedSpacing.s12) {
                    TaleedAvatar(initials: "NT", size: 36, style: .wireframe)
                    TaleedAvatar(initials: "S", size: 44, style: .wireframe)
                    // Arabic initials take Alexandria through the brand cascade.
                    TaleedAvatar(initials: TaleedAvatar.initials(from: "أمينة بن علي"), size: 44, style: .wireframe)
                    TaleedAvatar(initials: TaleedAvatar.initials(from: "كريم سعدي"), size: 48)
                }
                SellerRow(name: "Lina N.", reputation: copy("4,9 ★ · 38 ventes · Alger", "4.9 ★ · 38 عملية بيع · الجزائر",
                                                            "4.9 ★ · 38 sales · Algiers"),
                          isVerified: true, verifiedLabel: copy("Vérifiée", "موثّقة", "Verified")) {}
            }
        }
        GallerySection(id: "selection", number: "2.12", title: "Toggle, checkbox, radio") {
            GallerySelection()
        }
        GallerySection(id: "alerts", number: "2.13", title: "Inline alert") {
            GalleryAlerts()
        }
        GallerySection(id: "toasts", number: "2.14", title: "Toast",
                       note: "Light = component; dark = feedback after an action (D-11). Auto-dismiss 4 s.") {
            GalleryToasts(toast: $toast)
        }
    }
}

private struct GalleryButtons: View {
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "buttons", number: "2.1", title: "Button",
                       note: "Default · Pressed · Disabled, Small 32 · Medium 40 · Large 48") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                ForEach(TaleedButtonKind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        GalleryCaption(text: kind.rawValue.capitalized)
                        ForEach(TaleedButtonSize.allCases, id: \.self) { size in
                            FlowRow {
                                ForEach(TaleedButtonState.allCases, id: \.self) { state in
                                    TaleedButton(title: copy("Vendre", "بيع", "Sell"), kind: kind, size: size,
                                                 leadingIcon: size == .large ? .plus : nil, forcedState: state) {}
                                        .disabled(state == .disabled)
                                }
                            }
                        }
                        FlowRow {
                            ForEach(TaleedButtonSize.allCases, id: \.self) { size in
                                ForEach([TaleedButtonState.normal, .disabled], id: \.self) { state in
                                    TaleedIconOnlyButton(icon: .caretLeft, accessibilityLabel: "Back", kind: kind, size: size,
                                                         forcedState: state) {}
                                        .disabled(state == .disabled)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    GalleryCaption(text: copy("Chargement, pleine largeur, icônes", "تحميل، عرض كامل، أيقونات",
                                              "Loading, full width, icons"))
                    TaleedButton(title: copy("Publier l’annonce", "نشر الإعلان", "Publish listing"), kind: .secondary,
                                 isLoading: true, isFullWidth: true) {}
                    TaleedButton(title: copy("Publier l’annonce", "نشر الإعلان", "Publish listing"), kind: .secondary,
                                 isFullWidth: true) {}
                    TaleedButton(title: copy("Écrire au vendeur", "مراسلة البائع", "Message seller"), kind: .tertiary,
                                 leadingIcon: .chatCircle, trailingIcon: .caretRight, isFullWidth: true) {}
                    TaleedButton(title: copy("Continuer avec l’e-mail", "المتابعة بالبريد الإلكتروني", "Continue with email"),
                                 kind: .tertiary, leadingIcon: .envelope, isFullWidth: true,
                                 leadingIconColor: TaleedColor.blue600) {}
                }
            }
        }
    }
}

private struct GalleryIconButtons: View {
    @State private var saved = true
    @State private var count = 7
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            HStack(spacing: TaleedSpacing.s12) {
                TaleedIconButton(icon: .heart, accessibilityLabel: "Save") {}
                TaleedIconButton(icon: .heart, accessibilityLabel: "Save", isActive: true, activeIcon: .heartStraight) {}
                TaleedIconButton(icon: .share, accessibilityLabel: "Share") {}
                TaleedIconButton(icon: .dotsThree, accessibilityLabel: "More") {}.disabled(true)
            }
            HStack(spacing: TaleedSpacing.s12) {
                FavoriteControl(isSaved: false) {}
                FavoriteControl(isSaved: false, count: 7) {}
                FavoriteControl(isSaved: true) {}
                FavoriteControl(isSaved: saved, count: count) {
                    saved.toggle()
                    count += saved ? 1 : -1
                }
                FavoriteCircleButton(isSaved: false) {}
                FavoriteCircleButton(isSaved: true) {}
            }
        }
    }
}

private struct GalleryFields: View {
    @State private var search = ""
    @State private var price = "2 500 DA"
    @State private var location = "Central Algiers"
    @State private var title = "Nike jacket"
    @State private var description = ""
    @State private var descriptionError = "Nice dress."
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
            TaleedTextField(label: copy("Recherche", "بحث", "Search"), text: $search,
                            placeholder: copy("Rechercher sur Taleed", "ابحث في تليد", "Search Taleed"),
                            leadingIcon: .magnifyingGlass)
            TaleedTextField(label: copy("Titre", "العنوان", "Title"), text: $title, leadingIcon: .magnifyingGlass,
                            helper: copy("Actif (focus)", "نشط (تركيز)", "Active (focused)"), forcedState: .active)
            TaleedTextField(label: copy("Prix maximum", "أقصى سعر", "Maximum price"), text: $price, leadingIcon: .money,
                            error: copy("Le prix minimum est 3 000 DA", "أدنى سعر هو 3.000 د.ج.", "The minimum price is 3,000 DA"))
            TaleedTextField(label: copy("Lieu", "الموقع", "Location"), text: $location, leadingIcon: .mapPin,
                            helper: copy("Désactivé", "معطّل", "Disabled"))
                .disabled(true)
            TaleedSelectField(label: copy("Catégorie", "الفئة", "Category"),
                              placeholder: copy("Choisir une catégorie", "اختر فئة", "Choose a category")) {}
            TaleedSelectField(label: copy("Catégorie", "الفئة", "Category"), value: copy("Femmes", "نساء", "Women"),
                              placeholder: "", isActive: true) {}
            TaleedSelectField(label: copy("Sous-catégorie", "الفئة الفرعية", "Subcategory"),
                              placeholder: copy("Choisissez d’abord une catégorie", "اختر فئة أولًا", "Choose a category first")) {}
                .disabled(true)
            TaleedSelectField(label: copy("Wilaya", "الولاية", "Wilaya"), placeholder: copy("Choisir", "اختر", "Choose"),
                              error: copy("Choisissez une wilaya.", "اختر ولاية.", "Choose a wilaya.")) {}
            TaleedTextArea(label: copy("Description", "الوصف", "Description"), text: $description,
                           placeholder: copy("Décrivez votre article : matière, défauts, mesures…",
                                             "صف غرضك: الخامة، العيوب، المقاسات…",
                                             "Describe your item: material, any flaws, measurements..."),
                           helper: copy("Donnez les détails qu’un acheteur voudrait connaître.",
                                        "أضف التفاصيل التي يودّ المشتري معرفتها.",
                                        "Share the details a buyer would want to know."))
            TaleedTextArea(label: copy("Description", "الوصف", "Description"), text: $descriptionError,
                           error: copy("Ajoutez plus de détails sur votre article.", "أضف تفاصيل أكثر عن غرضك.",
                                       "Add more detail about your item."))
        }
    }
}

private struct GalleryChips: View {
    @State private var selected = 0
    @State private var filters = ["condition", "delivery", "size"]
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        let categories: [ChipSample] = [
            ChipSample(title: copy("Tout", "الكل", "All"), icon: nil),
            ChipSample(title: copy("Enfants", "أطفال", "Kids"), icon: .baby, iconSize: 18),
            ChipSample(title: copy("Femmes", "نساء", "Women"), icon: .dress),
            ChipSample(title: copy("Hommes", "رجال", "Men"), icon: .tShirt),
            ChipSample(title: copy("Maison", "المنزل", "Home"), icon: .houseLine),
            ChipSample(title: copy("Électroménager", "إلكترونيات", "Electronics"), icon: .washingMachine),
        ]
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            ChipRow {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, item in
                    CategoryChip(title: item.title, icon: item.icon, iconSize: item.iconSize, isSelected: index == selected) {
                        selected = index
                    }
                }
            }
            ChipRow(spacing: 10) {
                FilterChip(title: copy("Oran", "وهران", "Oran"))
                FilterChip(title: copy("Moins de 5 000 DA", "أقل من 5.000 د.ج.", "Under 5,000 DA"), icon: .slidersHorizontal,
                           tone: .brand)
                FilterChip(title: copy("Filtres · 2", "عوامل التصفية · 2", "Filters · 2"), icon: .slidersHorizontal, tone: .brand) {}
            }
            ChipRow(spacing: 10) {
                if filters.contains("condition") {
                    RemovableFilterChip(title: copy("Très bon état", "حالة ممتازة", "Very good condition"), tone: .brand) {
                        filters.removeAll { $0 == "condition" }
                    }
                }
                if filters.contains("delivery") {
                    RemovableFilterChip(title: copy("Livraison", "التوصيل", "Delivery"), tone: .success) {
                        filters.removeAll { $0 == "delivery" }
                    }
                }
                if filters.contains("size") {
                    RemovableFilterChip(title: copy("Taille M", "المقاس M", "Size M"), tone: .neutral) {
                        filters.removeAll { $0 == "size" }
                    }
                }
            }
        }
    }
}

private struct ChipSample {
    let title: String
    let icon: TaleedIcon?
    var iconSize: CGFloat = 20
}

private struct GalleryTags: View {
    @State private var tab = 0
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            FlowRow {
                TaleedBadge(title: copy("Nouveau", "جديد", "New"), tone: .brand)
                TaleedBadge(title: copy("Vérifié", "موثّق", "Verified"), tone: .success, icon: .shieldCheck)
                TaleedBadge(title: copy("Réservé", "محجوز", "Reserved"), tone: .warning)
                CountBadge(count: 3)
                CountBadge(count: 128)
                SizeTag(text: "M")
                SizeTag(text: "38")
            }
            GalleryCaption(text: copy("État · petit (22)", "الحالة · صغير (22)", "Condition · small (22)"))
            FlowRow {
                ForEach(ProductCondition.allCases, id: \.self) { ConditionTag($0) }
                ConditionTag(code: "NEW_CODE", catalogLabel: copy("Libellé du catalogue", "تسمية الفهرس", "Catalog label"),
                             catalogShortLabel: copy("Libellé court", "تسمية قصيرة", "Short label"))
            }
            GalleryCaption(text: copy("État · grand (30)", "الحالة · كبير (30)", "Condition · large (30)"))
            FlowRow {
                ForEach(ProductCondition.allCases, id: \.self) { ConditionTag($0, size: .large) }
                ConditionTag(code: "NEW_CODE", catalogLabel: copy("Libellé du catalogue", "تسمية الفهرس", "Catalog label"),
                             catalogShortLabel: copy("Libellé court", "تسمية قصيرة", "Short label"), size: .large)
            }
            TaleedTabs(titles: [copy("Pour vous", "لك", "For you"), copy("À proximité", "بالقرب منك", "Nearby"),
                                copy("Abonnements", "المتابَعون", "Following")], selection: $tab)
        }
    }
}

private struct GallerySelection: View {
    @State private var notifications = true
    @State private var hideSold = false
    @State private var delivery = true
    @State private var pickup = false
    @State private var sort = 0
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        VStack(alignment: .leading, spacing: 0) {
            Toggle(copy("Alertes de prix", "تنبيهات الأسعار", "Price notifications"), isOn: $notifications).toggleStyle(.taleed)
            Toggle(copy("Masquer les articles vendus", "إخفاء الأغراض المباعة", "Hide sold items"), isOn: $hideSold)
                .toggleStyle(.taleed)
            Toggle(copy("Désactivé", "معطّل", "Disabled"), isOn: .constant(true)).toggleStyle(.taleed).disabled(true)
            Toggle(copy("Livraison disponible", "التوصيل متاح", "Delivery available"), isOn: $delivery)
                .toggleStyle(.taleedCheckbox)
            Toggle(copy("Remise en main propre", "الاستلام باليد", "Local pickup"), isOn: $pickup).toggleStyle(.taleedCheckbox)
            TaleedRadio(title: copy("Prix croissant", "السعر تصاعديًا", "Price: low to high"), isSelected: sort == 0) { sort = 0 }
            TaleedRadio(title: copy("Plus récents", "الأحدث", "Newest"), isSelected: sort == 1) { sort = 1 }
        }
    }
}

private struct GalleryAlerts: View {
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        VStack(spacing: TaleedSpacing.s12) {
            InlineAlert(kind: .info, title: copy("Conseil de sécurité", "نصيحة أمان", "Safety tip"),
                        message: copy("Gardez vos échanges et paiements sur Taleed.", "أبقِ محادثاتك ومدفوعاتك داخل تليد.",
                                      "Keep conversations and payments within Taleed."),
                        actionTitle: copy("En savoir plus", "اعرف المزيد", "Learn more")) {}
            InlineAlert(kind: .success, title: copy("Annonce publiée", "تم نشر الإعلان", "Listing published"),
                        message: copy("Votre article est visible par les acheteurs.", "غرضك ظاهر الآن للمشترين.",
                                      "Your item is now visible to buyers."))
            InlineAlert(kind: .warning, title: copy("Photo à améliorer", "الصورة تحتاج إلى تحسين", "Photo needs improvement"),
                        message: copy("Ajoutez une photo à la lumière du jour.", "أضف صورة في ضوء طبيعي.",
                                      "Add a photo in natural light."))
            InlineAlert(kind: .error, title: copy("Échec de l’envoi", "تعذّر الإرسال", "Failed to send"),
                        message: copy("Vérifiez votre connexion et réessayez.", "تحقق من اتصالك وأعد المحاولة.",
                                      "Check your connection and try again."))
            UsageNote(text: copy("Utilisez des libellés pour l’accueil et la navigation.",
                                 "استخدم التسميات في الترحيب والتنقل.",
                                 "Use labels in onboarding and navigation."))
        }
    }
}

private struct GalleryToasts: View {
    @Binding var toast: ToastItem?
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        let messages: [(TaleedFeedbackKind, String)] = [
            (.success, copy("Ajouté aux favoris", "أضيف إلى المفضلة", "Added to favorites")),
            (.error, copy("Impossible d’ajouter aux favoris", "تعذّرت الإضافة إلى المفضلة", "Unable to add to favorites")),
            (.warning, copy("Limite de favoris atteinte", "تم بلوغ حد المفضلة", "Favorites limit reached")),
            (.info, copy("Déjà dans vos favoris", "موجود في المفضلة", "Already in favorites")),
        ]
        let cancel = copy("Annuler", "إلغاء", "Cancel")
        VStack(spacing: TaleedSpacing.s8) {
            ForEach(messages, id: \.0) { kind, message in
                TaleedToast(kind: kind, message: message, style: .light, actionTitle: kind == .success ? cancel : nil,
                            onAction: {}, onClose: {})
            }
            ForEach(messages, id: \.1) { kind, message in
                TaleedToast(kind: kind, message: message, actionTitle: kind == .success ? cancel : nil, onAction: {}, onClose: {})
            }
            TaleedButton(title: copy("Afficher un toast", "عرض إشعار", "Show a toast"), kind: .tertiary, size: .medium) {
                toast = ToastItem(kind: .success, message: messages[0].1, actionTitle: cancel, onAction: {})
            }
        }
    }
}

/// Lays children out in rows that wrap, leading-aligned (mirrors in right-to-left layouts).
struct FlowRow: Layout {
    var spacing: CGFloat = TaleedSpacing.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var leading = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: leading, y: top + (row.height - size.height) / 2), proposal: .unspecified)
                leading += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
#endif
