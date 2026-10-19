import SwiftUI

/// The language picker, then the app version.
struct SettingsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.settingsTitle), onBack: { dismiss() })
        } content: {
            // Flat rows, as Android's SettingsScreen.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: l10n.string(.settingsLanguage))
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s24)
                        .padding(.bottom, TaleedSpacing.s8)
                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases) { language in
                            // Each name in its own language.
                            TaleedRadio(title: language.nativeName, isSelected: language == l10n.language) {
                                l10n.select(language)
                            }
                            .environment(\.locale, language.locale)
                        }
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    // "1.0.0 (1)" has no direction of its own: it stays left to right in Arabic too.
                    ListRow(label: l10n.string(.settingsVersion),
                            trailingText: "\(environment.appVersion) (\(environment.buildNumber))".isolatedLeftToRight)
                        .padding(.top, TaleedSpacing.s16)
                    #if DEBUG
                    ListRow(label: "Design system", leadingIcon: .sparkle, showsChevron: true) {
                        router.profilePath.append(.designSystem)
                    }
                    #endif
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
    }
}
