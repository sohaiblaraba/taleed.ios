import SwiftUI

/// The language picker, then the app version.
struct SettingsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        List {
            Section(l10n.string(.settingsLanguage)) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        l10n.select(language)
                    } label: {
                        HStack {
                            // Each name in its own language.
                            Text(verbatim: language.nativeName)
                                .environment(\.locale, language.locale)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if language == l10n.language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: Theme.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(language == l10n.language ? .isSelected : [])
                }
            }

            Section {
                LabeledContent(l10n.string(.settingsVersion)) {
                    Text(verbatim: "\(environment.appVersion) (\(environment.buildNumber))")
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .navigationTitle(l10n.string(.settingsTitle))
    }
}
