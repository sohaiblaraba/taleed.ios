import SwiftUI

/// The language picker, then the app version.
struct SettingsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedAppBar(title: l10n.string(.settingsTitle), onBack: { dismiss() },
                         backAccessibilityLabel: l10n.string(.commonBack))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        Eyebrow(text: l10n.string(.settingsLanguage))
                        VStack(spacing: 0) {
                            ForEach(AppLanguage.allCases) { language in
                                // Each name in its own language.
                                TaleedRadio(title: language.nativeName, isSelected: language == l10n.language) {
                                    l10n.select(language)
                                }
                                .environment(\.locale, language.locale)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        HStack {
                            Text(l10n.string(.settingsVersion))
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textPrimary)
                            Spacer()
                            Text(verbatim: "\(environment.appVersion) (\(environment.buildNumber))")
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textSecondary)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .padding(.horizontal, TaleedSpacing.s16)
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                        #if DEBUG
                        Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
                        TaleedListRow(title: "Design system", leadingIcon: .sparkle, showsDivider: false) {
                            router.profilePath.append(.designSystem)
                        }
                        #endif
                    }
                    .taleedCard()
                    .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                }
                .padding(TaleedLayout.screenMargin)
                .padding(.top, TaleedSpacing.s8)
            }
        }
    }
}
