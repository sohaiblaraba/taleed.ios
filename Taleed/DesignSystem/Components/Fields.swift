import SwiftUI

/// The visual state of a field. Disabled comes from the environment (`.disabled(true)`).
enum TaleedFieldState: Sendable {
    case normal, active, error, disabled
}

/// A label above a field (Caption 12/600 in `text/body`, decision D-4): the same on text fields, selects
/// and text areas.
struct FieldLabel: View {
    let text: String
    var color: Color = TaleedColor.textBody

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// The helper line's colour (design-system §2.4–2.6, as Android's FieldHelper): `navy/500`,
/// `feedback/info` while the field is focused or its picker open, `feedback/error` on error.
extension TaleedFieldState {
    var helperColor: Color {
        switch self {
        case .error: TaleedColor.feedbackError
        case .active: TaleedColor.feedbackInfo
        case .normal, .disabled: TaleedColor.navy500
        }
    }
}

extension View {
    /// Announces a new field error with VoiceOver (Android marks the error line as a polite live region):
    /// the error is otherwise only in the field's hint, read when the field gets focus.
    func announcesFieldError(_ error: String?) -> some View {
        onChange(of: error) { _, newValue in
            if let newValue, !newValue.isEmpty {
                AccessibilityNotification.Announcement(newValue).post()
            }
        }
    }
}

/// Helper or error text under a field (Body/Small).
struct FieldHelper: View {
    let text: String
    var color: Color = TaleedColor.navy500

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.bodySmall)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

/// Border, fill and opacity of a field box in a state (design-system §2.4–2.6).
private struct FieldBox: ViewModifier {
    let state: TaleedFieldState
    var disabledFill = TaleedColor.surfaceGrouped

    func body(content: Content) -> some View {
        let border: Color = switch state {
        case .active: TaleedColor.brandPrimary
        case .error: TaleedColor.feedbackError
        case .normal, .disabled: TaleedColor.borderSubtle
        }
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        content
            .background(shape.fill(state == .disabled ? disabledFill : TaleedColor.surfacePrimary))
            .overlay(shape.strokeBorder(border, lineWidth: state == .active ? 2 : 1))
            .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: state)
    }
}

/// Text field (design-system §2.4): label, 44 pt input with optional leading icon and clear button,
/// helper text. `error` replaces the helper and draws the error state.
struct TaleedTextField: View {
    var label: String?
    @Binding var text: String
    var placeholder: String = ""
    var leadingIcon: TaleedIcon?
    var helper: String?
    var error: String?
    var isSecure = false
    var showsClearButton = true
    /// False draws the error or helper text outside the field (promo code row): the field still takes
    /// the Error look.
    var showsMessage = true
    /// External focus, for moving focus between fields. Without it the field manages its own focus.
    var focus: FocusState<Bool>.Binding?
    /// Draws the focused state without focus, for the design-system gallery.
    var forcedState: TaleedFieldState?

    @FocusState private var ownFocus: Bool
    /// A secure field showing its text (the eye button).
    @State private var isRevealed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale

    private var isFocused: Bool { focus?.wrappedValue ?? ownFocus }

    private var state: TaleedFieldState {
        if let forcedState { return forcedState }
        if !isEnabled { return .disabled }
        if error != nil { return .error }
        return isFocused ? .active : .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textBody)
            }
            input
            if showsMessage, let message = error ?? helper {
                FieldHelper(text: message, color: state.helperColor)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
        .announcesFieldError(error)
    }

    private var input: some View {
        HStack(spacing: TaleedSize.inputGap) {
            if let leadingIcon {
                TaleedIconView(
                    leadingIcon,
                    size: TaleedSize.inputIconLeading,
                    color: state == .active ? TaleedColor.brandPrimary : TaleedColor.textSecondary
                )
            }
            field
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textPrimary)
                .tint(TaleedColor.brandPrimary)
                .focused(focus ?? $ownFocus)
                .accessibilityLabel(label ?? placeholder)
                .accessibilityHint(error ?? helper ?? "")
            if showsClearButton, !isSecure, !text.isEmpty, state != .disabled {
                Button { text = "" } label: {
                    TaleedIconView(.x, size: TaleedSize.inputIconTrailing, color: TaleedColor.textSecondary)
                        .frame(width: 24, height: 24)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignSystemStrings.string(.commonClear, locale: locale))
            }
            if isSecure {
                revealButton
            }
        }
        .padding(.horizontal, TaleedSize.inputPaddingX)
        .padding(.vertical, 6)
        .frame(minHeight: TaleedSize.inputHeight)
        .modifier(FieldBox(state: state))
        .contentShape(Rectangle())
        .onTapGesture { focusField() }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(placeholder).foregroundStyle(TaleedColor.textSecondary)
        if isSecure, !isRevealed {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }

    /// Shows or hides a password (the design system's eye; slashed while the text shows), 44 pt target.
    /// The field keeps the focus while it switches.
    private var revealButton: some View {
        Button {
            let wasFocused = isFocused
            isRevealed.toggle()
            if wasFocused {
                // Once the other field is in place: the one that left took the focus with it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    focusField()
                }
            }
        } label: {
            TaleedIconView(.eye, size: TaleedSize.inputIconTrailing + 2,
                           color: state == .active ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
                .overlay {
                    if isRevealed {
                        SlashShape()
                            .stroke(state == .active ? TaleedColor.brandPrimary : TaleedColor.textSecondary,
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
                .frame(width: 24, height: 24)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .disabled(state == .disabled)
        .accessibilityLabel(DesignSystemStrings.string(isRevealed ? .appAuthHidePassword : .appAuthShowPassword,
                                                       locale: locale))
    }

    private func focusField() {
        if let focus { focus.wrappedValue = true } else { ownFocus = true }
    }
}

/// The slash across the eye of a revealed password (Phosphor's eye-slash diagonal).
private struct SlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.12))
        return path
    }
}

/// Select field (design-system §2.5): looks like a text field with a caret; opens a picker.
/// Dependent selects stay disabled until their parent has a value.
struct TaleedSelectField: View {
    var label: String?
    /// The chosen value, nil to show the placeholder.
    var value: String?
    var placeholder: String
    var helper: String?
    var error: String?
    /// True while its picker is open (Active border).
    var isActive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var state: TaleedFieldState {
        if !isEnabled { return .disabled }
        if error != nil { return .error }
        return isActive ? .active : .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textBody)
            }
            Button(action: action) {
                HStack(spacing: TaleedSize.selectGap) {
                    Text(value ?? placeholder)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(value == nil ? TaleedColor.textSecondary : TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    TaleedIconView(.caretDown, size: TaleedSize.selectCaretSize, color: TaleedColor.textSecondary)
                }
                .padding(.horizontal, TaleedSize.selectPaddingX)
                .padding(.vertical, 6)
                .frame(minHeight: TaleedSize.selectHeight)
                .modifier(FieldBox(state: state, disabledFill: TaleedColor.surfaceSubtle))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label ?? placeholder)
            .accessibilityValue(value ?? placeholder)
            .accessibilityHint(error ?? helper ?? "")
            if let message = error ?? helper {
                FieldHelper(text: message, color: state.helperColor)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
        .announcesFieldError(error)
    }
}

/// Text area (design-system §2.6): 120 pt box that grows with the text, then scrolls.
struct TaleedTextArea: View {
    var label: String?
    @Binding var text: String
    var placeholder: String = ""
    var helper: String?
    var error: String?
    /// The most UTF-16 units the field takes (as the API counts), like the website's `maxLength`: typing
    /// or pasting past it keeps the start, and the field shows exactly what it holds.
    var maxLength: Int?
    var forcedState: TaleedFieldState?

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var state: TaleedFieldState {
        if let forcedState { return forcedState }
        if !isEnabled { return .disabled }
        if error != nil { return .error }
        return isFocused ? .active : .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textBody)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(TaleedColor.textSecondary), axis: .vertical)
                .lineLimit(5...10)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textPrimary)
                .tint(TaleedColor.brandPrimary)
                .focused($isFocused)
                .padding(TaleedSize.textAreaPadding)
                .frame(minHeight: TaleedSize.textAreaHeight, alignment: .topLeading)
                .modifier(FieldBox(state: state))
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }
                .accessibilityLabel(label ?? placeholder)
                .accessibilityHint(error ?? helper ?? "")
                // Capped after the edit, in its own update: a value rewritten inside the binding's setter
                // is not drawn back into the editor, which would keep showing the cut text.
                .onChange(of: text) { _, newValue in
                    if let capped = Self.capped(newValue, maxLength: maxLength) { text = capped }
                }
            if let message = error ?? helper {
                FieldHelper(text: message, color: state.helperColor)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
        .announcesFieldError(error)
    }

    /// The text cut to `maxLength` UTF-16 units, or nil when it fits (or there is no limit).
    static func capped(_ text: String, maxLength: Int?) -> String? {
        guard let maxLength, text.utf16.count > maxLength else { return nil }
        return text.prefix(utf16Units: maxLength)
    }
}

#Preview("Fields") {
    @Previewable @State var text = "Nike jacket"
    VStack(spacing: 24) {
        TaleedTextField(label: "Search", text: $text, placeholder: "Search Taleed", leadingIcon: .magnifyingGlass)
        TaleedTextField(label: "Maximum price", text: .constant("2 500 DA"), leadingIcon: .money,
                        error: "The minimum price is 3,000 DA")
        TaleedSelectField(label: "Category", placeholder: "Choose a category") {}
        TaleedSelectField(label: "Subcategory", placeholder: "Choose a category first") {}.disabled(true)
        TaleedTextArea(label: "Description", text: .constant(""), placeholder: "Describe your item",
                       helper: "Share the details a buyer would want to know.")
    }
    .padding()
}
