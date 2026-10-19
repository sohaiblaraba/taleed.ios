import SwiftUI

/// The visual state of a field. Disabled comes from the environment (`.disabled(true)`).
enum TaleedFieldState: Sendable {
    case normal, active, error, disabled
}

/// A label above a field (Caption 12/600, decision D-4).
struct FieldLabel: View {
    let text: String
    var color: Color = TaleedColor.textPrimary

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
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
    /// External focus, for moving focus between fields. Without it the field manages its own focus.
    var focus: FocusState<Bool>.Binding?
    /// Draws the focused state without focus, for the design-system gallery.
    var forcedState: TaleedFieldState?

    @FocusState private var ownFocus: Bool
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
        VStack(alignment: .leading, spacing: TaleedSize.Input.labelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textBody)
            }
            input
            if let message = error ?? helper {
                FieldHelper(text: message, color: helperColor)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
    }

    private var helperColor: Color {
        switch state {
        case .error: TaleedColor.feedbackError
        case .active: TaleedColor.feedbackInfo
        case .normal, .disabled: TaleedColor.navy500
        }
    }

    private var input: some View {
        HStack(spacing: TaleedSize.Input.gap) {
            if let leadingIcon {
                TaleedIconView(
                    leadingIcon,
                    size: TaleedSize.Input.iconLeading,
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
                    TaleedIconView(.x, size: TaleedSize.Input.iconTrailing, color: TaleedColor.textSecondary)
                        .frame(width: 24, height: 24)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignSystemStrings.string(.a11yClearText, locale: locale))
            }
        }
        .padding(.horizontal, TaleedSize.Input.paddingX)
        .padding(.vertical, 6)
        .frame(minHeight: TaleedSize.Input.height)
        .modifier(FieldBox(state: state))
        .contentShape(Rectangle())
        .onTapGesture { focusField() }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(placeholder).foregroundStyle(TaleedColor.textSecondary)
        if isSecure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }

    private func focusField() {
        if let focus { focus.wrappedValue = true } else { ownFocus = true }
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
        VStack(alignment: .leading, spacing: TaleedSize.Input.labelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textPrimary)
            }
            Button(action: action) {
                HStack(spacing: TaleedSize.Select.gap) {
                    Text(value ?? placeholder)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(value == nil ? TaleedColor.textSecondary : TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    TaleedIconView(.caretDown, size: TaleedSize.Select.caretSize, color: TaleedColor.textSecondary)
                }
                .padding(.horizontal, TaleedSize.Select.paddingX)
                .padding(.vertical, 6)
                .frame(minHeight: TaleedSize.Select.height)
                .modifier(FieldBox(state: state, disabledFill: TaleedColor.surfaceSubtle))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label ?? placeholder)
            .accessibilityValue(value ?? placeholder)
            .accessibilityHint(error ?? helper ?? "")
            if let message = error ?? helper {
                FieldHelper(text: message, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textSecondary)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
    }
}

/// Text area (design-system §2.6): 120 pt box that grows with the text, then scrolls.
struct TaleedTextArea: View {
    var label: String?
    @Binding var text: String
    var placeholder: String = ""
    var helper: String?
    var error: String?
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
        VStack(alignment: .leading, spacing: TaleedSize.Input.labelGap) {
            if let label {
                FieldLabel(text: label, color: state == .error ? TaleedColor.feedbackError : TaleedColor.textPrimary)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(TaleedColor.textSecondary), axis: .vertical)
                .lineLimit(5...10)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textPrimary)
                .tint(TaleedColor.brandPrimary)
                .focused($isFocused)
                .padding(TaleedSize.TextArea.padding)
                .frame(minHeight: TaleedSize.TextArea.height, alignment: .topLeading)
                .modifier(FieldBox(state: state))
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }
                .accessibilityLabel(label ?? placeholder)
                .accessibilityHint(error ?? helper ?? "")
            if let message = error ?? helper {
                FieldHelper(text: message, color: state == .error ? TaleedColor.feedbackError : TaleedColor.navy500)
            }
        }
        .opacity(state == .disabled ? TaleedOpacity.disabledField : 1)
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
