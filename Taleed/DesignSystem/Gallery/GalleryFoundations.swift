#if DEBUG
import SwiftUI

/// §1 Foundations: colours, type, spacing, radius, elevation, icons.
struct GalleryFoundations: View {
    @Environment(\.locale) private var locale

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "colors", number: "1.2", title: "Colour",
                       note: "Scales, semantic variables and recurring literals (tokens.json); app: colours the app adds (D-9).") {
            ForEach(["semantic", "literal", "app", "blue", "mint", "navy", "neutral"], id: \.self) { group in
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    GalleryCaption(text: group)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: TaleedSpacing.s8)],
                              spacing: TaleedSpacing.s8) {
                        ForEach((TaleedColor.catalog + TaleedColor.appCatalog).filter { $0.group == group }, id: \.name) { token in
                            ColorSwatch(token: token)
                        }
                    }
                }
            }
        }
        GallerySection(id: "type", number: "1.3", title: "Typography",
                       note: copy("Plus Jakarta Sans partout ; Alexandria pour l’écriture arabe.",
                                  "Plus Jakarta Sans في كل اللغات؛ Alexandria للحروف العربية.",
                                  "Plus Jakarta Sans everywhere; Alexandria for Arabic script.")) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                ForEach(TaleedFont.catalog, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        GalleryCaption(text: "\(item.name) · \(Int(item.style.size))/\(item.style.weight.rawValue)")
                        Text(copy("Donnez une seconde vie à vos trésors", "امنح كنوزك حياة ثانية",
                                  "Give your treasures a second life"))
                            .taleedFont(item.style)
                            .foregroundStyle(TaleedColor.textPrimary)
                    }
                }
                // D-9: secondary text below 16 pt in neutral/700 (AA), from 16 pt in text/secondary.
                GalleryCaption(text: "secondary text (D-9)")
                ForEach(["meta", "bodySmall", "bodyRegular", "caption", "bodyLarge"], id: \.self) { name in
                    if let style = TaleedFont.catalog.first(where: { $0.name == name })?.style {
                        let small = TaleedColor.usesSmallSecondary(style)
                        VStack(alignment: .leading, spacing: 2) {
                            GalleryCaption(text: "\(name) · " + (small ? "textSecondarySmall #46506A" : "textSecondary #778198"))
                            Text(copy("Expédié depuis Oran · il y a 2 h", "يُشحن من وهران · منذ ساعتين",
                                      "Ships from Oran · 2 h ago"))
                                .taleedFont(style)
                                .foregroundStyle(TaleedColor.secondaryText(for: style))
                        }
                    }
                }
            }
        }
        GallerySection(id: "spacing", number: "1.4–1.6", title: "Spacing, radius, elevation") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                ForEach(TaleedSpacing.catalog, id: \.name) { item in
                    HStack(spacing: TaleedSpacing.s12) {
                        GalleryCaption(text: item.name).frame(width: 44, alignment: .leading)
                        Rectangle().fill(TaleedColor.brandPrimary).frame(width: item.value, height: 12)
                    }
                }
                HStack(spacing: TaleedSpacing.s12) {
                    ForEach(TaleedRadius.catalog.filter { $0.name != "full" }, id: \.name) { item in
                        VStack(spacing: TaleedSpacing.s4) {
                            RoundedRectangle(cornerRadius: item.value, style: .continuous)
                                .fill(TaleedColor.brandSoft)
                                .overlay(RoundedRectangle(cornerRadius: item.value, style: .continuous)
                                    .strokeBorder(TaleedColor.brandSoftBorder))
                                .frame(width: 52, height: 52)
                            GalleryCaption(text: "\(item.name) \(Int(item.value))")
                        }
                    }
                }
                HStack(spacing: TaleedSpacing.s16) {
                    elevation("level0", nil)
                    elevation("level1", TaleedElevation.level1)
                    elevation("level2", TaleedElevation.level2)
                    elevation("navTop", TaleedElevation.navTop)
                }
                .padding(.vertical, TaleedSpacing.s8)
            }
        }
        GallerySection(id: "icons", number: "1.7", title: "Icons",
                       note: "\(TaleedIcon.allCases.count) Phosphor icons; arrows and carets mirror in Arabic.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: TaleedSpacing.s8)], spacing: TaleedSpacing.s12) {
                ForEach(TaleedIcon.allCases, id: \.self) { icon in
                    VStack(spacing: TaleedSpacing.s4) {
                        TaleedIconView(icon, size: 24, color: icon.isDirectional ? TaleedColor.brandPrimary : TaleedColor.textPrimary)
                        Text(verbatim: icon.rawValue)
                            .font(.custom(TaleedTypeface.plusJakartaSans.postScriptName(.regular), fixedSize: 9))
                            .foregroundStyle(TaleedColor.textSecondarySmall)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: TaleedSpacing.s16) {
                Image(taleed: .wordmark).resizable().scaledToFit().frame(width: 95, height: 24)
                Image(taleed: .wordmarkWhite).resizable().scaledToFit().frame(width: 95, height: 24)
                    .padding(6).background(TaleedColor.brandPrimary, in: RoundedRectangle(cornerRadius: TaleedRadius.s))
                Image(taleed: .lettermark).resizable().frame(width: 38, height: 38)
                Image(taleed: .emptyStateSearch).resizable().frame(width: 48, height: 48)
            }
        }
    }

    private func elevation(_ name: String, _ shadow: TaleedShadow?) -> some View {
        VStack(spacing: TaleedSpacing.s4) {
            RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                .fill(TaleedColor.surfacePrimary)
                .frame(width: 64, height: 48)
                .overlay {
                    if shadow == nil {
                        RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous).strokeBorder(TaleedColor.borderSubtle)
                    }
                }
                .taleedShadow(shadow ?? TaleedShadow(x: 0, y: 0, blur: 0, color: .clear, opacity: 0))
            GalleryCaption(text: name)
        }
    }
}

private struct ColorSwatch: View {
    let token: ColorToken

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                .fill(token.color)
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                    .strokeBorder(TaleedColor.borderSubtle))
            Text(verbatim: token.name)
                .font(.custom(TaleedTypeface.plusJakartaSans.postScriptName(.semibold), fixedSize: 10))
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: String(format: "#%06X", token.hex) + (token.opacity < 1 ? " \(Int(token.opacity * 100))%" : ""))
                .font(.custom(TaleedTypeface.plusJakartaSans.postScriptName(.regular), fixedSize: 9))
                .foregroundStyle(TaleedColor.textSecondarySmall)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
#endif
