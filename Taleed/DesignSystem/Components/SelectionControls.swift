import SwiftUI

/// Switch row (design-system §2.12): label then a 44 x 26 track. The whole row is the tap target.
/// Use as `Toggle(isOn:) { Text(...) }.toggleStyle(.taleed)`.
struct TaleedToggleStyle: ToggleStyle {
    /// The label's style: Button/Small by default; a settings list uses the list rows' Body/Large
    /// (`.taleedRow`), so the switch reads as one of its rows.
    var labelStyle = TaleedFont.buttonSmall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: TaleedMotion.transitionMin)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: TaleedSpacing.s12) {
                configuration.label
                    .taleedFont(labelStyle)
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

    /// The switch with the list rows' Body/Large label (the settings screen).
    static var taleedRow: TaleedToggleStyle { TaleedToggleStyle(labelStyle: TaleedFont.bodyLarge) }
}

extension ToggleStyle where Self == TaleedCheckboxStyle {
    static var taleedCheckbox: TaleedCheckboxStyle { TaleedCheckboxStyle() }
}

/// The 22 pt radio circle (8 pt white dot when selected). It grows with the text size, so it does not
/// shrink to a dot next to large labels.
struct RadioIndicator: View {
    let isSelected: Bool
    @ScaledMetric(relativeTo: .body) private var size = TaleedSize.radioSize
    @ScaledMetric(relativeTo: .body) private var dot = TaleedSize.radioDot

    var body: some View {
        Circle()
            .fill(isSelected ? TaleedColor.brandPrimary : TaleedColor.surfacePrimary)
            .overlay(Circle().strokeBorder(isSelected ? TaleedColor.brandPrimary : TaleedColor.borderSubtle,
                                           lineWidth: TaleedSize.radioBorderWidth))
            .overlay {
                if isSelected {
                    Circle().fill(TaleedColor.textInverse).frame(width: min(dot, 12), height: min(dot, 12))
                }
            }
            // Up to 32 pt: larger would take the label's room and break its words.
            .frame(width: min(size, 32), height: min(size, 32))
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
            HStack(alignment: .top, spacing: TaleedSize.radioLabelGap) {
                if indicatorEdge == .leading { indicator }
                Text(title)
                    .taleedFont(textStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if indicatorEdge == .trailing { indicator }
            }
            // At least 12 pt above and below the label at every size: a label on several lines never
            // touches the next row.
            .padding(.vertical, TaleedSpacing.s12)
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The circle centred on the label's first line (a label on two lines keeps it beside its start):
    /// a hidden one-line label in the same style gives that line's height.
    private var indicator: some View {
        ZStack {
            Text(verbatim: "X").taleedFont(textStyle).fixedSize().frame(width: 1).hidden()
            RadioIndicator(isSelected: isSelected)
        }
        .accessibilityHidden(true)
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
