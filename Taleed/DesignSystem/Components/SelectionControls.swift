import SwiftUI

/// Switch row (design-system §2.12): label then a 44 x 26 track. The whole row is the tap target.
/// Use as `Toggle(isOn:) { Text(...) }.toggleStyle(.taleed)`.
struct TaleedToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: TaleedMotion.transitionMin)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: TaleedSpacing.s12) {
                configuration.label
                    .taleedFont(TaleedFont.buttonSmall)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SwitchTrack(isOn: configuration.isOn)
            }
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}

private struct SwitchTrack: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Capsule()
            .fill(isOn ? TaleedColor.brandPrimary : TaleedColor.toggleOffTrack)
            .frame(width: TaleedSize.toggleWidth, height: TaleedSize.toggleHeight)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(TaleedColor.surfacePrimary)
                    .frame(width: TaleedSize.toggleThumb, height: TaleedSize.toggleThumb)
                    .taleedShadow(isOn ? TaleedElevation.toggleThumbOn : TaleedElevation.toggleThumbOff)
                    .padding(TaleedSize.togglePadding)
            }
            .opacity(isEnabled ? 1 : TaleedOpacity.disabledField)
    }
}

/// Checkbox row (22 pt box, radius 6). Use as `Toggle(isOn:) { Text(...) }.toggleStyle(.taleedCheckbox)`.
struct TaleedCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: TaleedSize.checkboxLabelGap) {
                CheckboxBox(isOn: configuration.isOn)
                configuration.label
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}

private struct CheckboxBox: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TaleedSize.checkboxRadius, style: .continuous)
        shape
            .fill(isOn ? TaleedColor.brandPrimary : TaleedColor.surfacePrimary)
            .overlay(shape.strokeBorder(isOn ? TaleedColor.brandPrimary : TaleedColor.borderSubtle,
                                        lineWidth: TaleedSize.checkboxBorderWidth))
            .overlay {
                if isOn { TaleedIconView(.check, size: TaleedSize.checkboxCheckIcon, color: TaleedColor.textInverse) }
            }
            .frame(width: TaleedSize.checkboxSize, height: TaleedSize.checkboxSize)
    }
}

extension ToggleStyle where Self == TaleedToggleStyle {
    static var taleed: TaleedToggleStyle { TaleedToggleStyle() }
}

extension ToggleStyle where Self == TaleedCheckboxStyle {
    static var taleedCheckbox: TaleedCheckboxStyle { TaleedCheckboxStyle() }
}

/// The 22 pt radio circle (8 pt white dot when selected).
struct RadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? TaleedColor.brandPrimary : TaleedColor.surfacePrimary)
            .overlay(Circle().strokeBorder(isSelected ? TaleedColor.brandPrimary : TaleedColor.borderSubtle,
                                           lineWidth: TaleedSize.radioBorderWidth))
            .overlay {
                if isSelected {
                    Circle().fill(TaleedColor.textInverse).frame(width: TaleedSize.radioDot, height: TaleedSize.radioDot)
                }
            }
            .frame(width: TaleedSize.radioSize, height: TaleedSize.radioSize)
            .accessibilityHidden(true)
    }
}

/// Radio row: circle then label, the whole row selects. In a choice sheet the circle goes after the
/// label (`.trailing`), as in the sort sheet (design-system §5.3).
struct TaleedRadio: View {
    enum IndicatorEdge: Sendable { case leading, trailing }

    let title: String
    let isSelected: Bool
    var textStyle: TaleedTextStyle = TaleedFont.bodyRegular
    var indicatorEdge: IndicatorEdge = .leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSize.radioLabelGap) {
                if indicatorEdge == .leading { RadioIndicator(isSelected: isSelected) }
                Text(title)
                    .taleedFont(textStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if indicatorEdge == .trailing { RadioIndicator(isSelected: isSelected) }
            }
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Selection controls") {
    @Previewable @State var isOn = true
    @Previewable @State var off = false
    VStack {
        Toggle("Price notifications", isOn: $isOn).toggleStyle(.taleed)
        Toggle("Hide sold items", isOn: $off).toggleStyle(.taleed)
        Toggle("Delivery available", isOn: $isOn).toggleStyle(.taleedCheckbox)
        TaleedRadio(title: "Newest", isSelected: true) {}
        TaleedRadio(title: "Price: low to high", isSelected: false) {}
    }
    .padding()
}
