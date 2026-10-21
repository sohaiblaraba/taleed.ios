import SwiftUI

/// Two-thumb range slider (Filters sheet 218:3162, "Price"): a 6 pt pill track in `surface/subtle`, the
/// part between the thumbs in `brand/accent`, two 18 pt `brand/accent` thumbs with a 1 pt white ring.
/// Values snap to `step` and the thumbs never cross. A touch moves the nearer thumb; the whole control is
/// 44 pt high to be easy to hit. It mirrors in right-to-left (the lower value on the right).
///
/// Each thumb is its own adjustable VoiceOver element ("Min, 5 000 DA"), moved by `accessibilityStep`.
/// Android: `TaleedRangeSlider`.
struct TaleedRangeSlider: View {
    @Binding var lower: Int
    @Binding var upper: Int
    let bounds: ClosedRange<Int>
    var step = 1
    /// How far one VoiceOver swipe moves a thumb; ten steps by default.
    var accessibilityStep: Int?
    let lowerLabel: String
    let upperLabel: String
    /// What VoiceOver reads for a value ("5 000 DA").
    var valueText: (Int) -> String = { String($0) }

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging: Thumb?

    static let trackHeight: CGFloat = 6
    static let thumbSize: CGFloat = 18

    enum Thumb: Sendable {
        case lower, upper
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY = proxy.size.height / 2
            let lowX = displayX(position(of: lower, width: width), width: width)
            let highX = displayX(position(of: upper, width: width), width: width)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(TaleedColor.surfaceSubtle)
                    .frame(width: width, height: Self.trackHeight)
                    .position(x: width / 2, y: midY)
                Capsule()
                    .fill(isEnabled ? TaleedColor.brandAccent : TaleedColor.navy300)
                    .frame(width: abs(highX - lowX), height: Self.trackHeight)
                    .position(x: (lowX + highX) / 2, y: midY)
                thumb(.lower).position(x: lowX, y: midY)
                thumb(.upper).position(x: highX, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(drag(width: width))
        }
        // Positions are worked out left to right and mirrored by hand (`displayX`).
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: TaleedSize.touchTargetMin)
        .accessibilityElement(children: .contain)
    }

    private func thumb(_ which: Thumb) -> some View {
        let value = which == .lower ? lower : upper
        return Circle()
            .fill(isEnabled ? TaleedColor.brandAccent : TaleedColor.navy300)
            .overlay { Circle().strokeBorder(TaleedColor.surfacePrimary, lineWidth: 1) }
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .scaleEffect(dragging == which ? 1.15 : 1)
            .animation(.easeOut(duration: TaleedMotion.transitionMin), value: dragging)
            .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
            .accessibilityElement()
            .accessibilityLabel(which == .lower ? lowerLabel : upperLabel)
            .accessibilityValue(valueText(value))
            .accessibilityAdjustableAction { direction in
                let delta = accessibilityStep ?? step * 10
                switch direction {
                case .increment: set(which, to: value + delta)
                case .decrement: set(which, to: value - delta)
                @unknown default: break
                }
            }
    }

    // MARK: Geometry

    /// The thumb's centre from the leading end: the thumbs stay inside the track.
    private func position(of value: Int, width: CGFloat) -> CGFloat {
        let radius = Self.thumbSize / 2
        let span = CGFloat(bounds.upperBound - bounds.lowerBound)
        guard span > 0 else { return radius }
        let clamped = CGFloat(min(max(value, bounds.lowerBound), bounds.upperBound) - bounds.lowerBound)
        return radius + clamped / span * max(0, width - 2 * radius)
    }

    private func displayX(_ leadingX: CGFloat, width: CGFloat) -> CGFloat {
        layoutDirection == .rightToLeft ? width - leadingX : leadingX
    }

    /// The value at a point of the track, snapped to `step`.
    private func value(atDisplayX x: CGFloat, width: CGFloat) -> Int {
        let radius = Self.thumbSize / 2
        let leadingX = layoutDirection == .rightToLeft ? width - x : x
        let usable = max(1, width - 2 * radius)
        let fraction = min(max((leadingX - radius) / usable, 0), 1)
        let raw = Double(bounds.upperBound - bounds.lowerBound) * Double(fraction)
        return Self.snapped(bounds.lowerBound + Int(raw.rounded()), bounds: bounds, step: step)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard let which = dragging
                    ?? nearestThumb(to: gesture.startLocation.x, movingTo: gesture.location.x, width: width) else { return }
                dragging = which
                set(which, to: value(atDisplayX: gesture.location.x, width: width))
            }
            .onEnded { gesture in
                // A tap on the two thumbs together moves neither.
                if dragging == nil, let which = nearestThumb(to: gesture.startLocation.x, movingTo: gesture.location.x,
                                                             width: width, decides: true) {
                    set(which, to: value(atDisplayX: gesture.location.x, width: width))
                }
                dragging = nil
            }
    }

    /// The thumb nearer the touch. When both sit together, the one the finger moves towards, nil until it
    /// has moved (`decides` picks one anyway, at the end of a tap).
    private func nearestThumb(to x: CGFloat, movingTo current: CGFloat, width: CGFloat, decides: Bool = false) -> Thumb? {
        let low = displayX(position(of: lower, width: width), width: width)
        let high = displayX(position(of: upper, width: width), width: width)
        guard abs(low - high) < 1 else { return abs(x - low) <= abs(x - high) ? .lower : .upper }
        guard abs(current - x) >= 2 else {
            guard decides else { return nil }
            // Towards the side of the track the tap is on.
            return (layoutDirection == .rightToLeft ? x < low : x > low) ? .upper : .lower
        }
        let forward = layoutDirection == .rightToLeft ? current < x : current > x
        return forward ? .upper : .lower
    }

    private func set(_ which: Thumb, to newValue: Int) {
        let snapped = Self.snapped(newValue, bounds: bounds, step: step)
        switch which {
        case .lower:
            let value = min(snapped, upper)
            if value != lower { lower = value }
        case .upper:
            let value = max(snapped, lower)
            if value != upper { upper = value }
        }
    }

    /// `value` on the step grid from the lower bound, inside the bounds.
    static func snapped(_ value: Int, bounds: ClosedRange<Int>, step: Int) -> Int {
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        guard step > 1 else { return clamped }
        let offset = clamped - bounds.lowerBound
        let rounded = Int((Double(offset) / Double(step)).rounded()) * step
        return min(bounds.lowerBound + rounded, bounds.upperBound)
    }
}

#Preview("Range slider") {
    @Previewable @State var low = 5_000
    @Previewable @State var high = 60_000
    VStack(spacing: 24) {
        TaleedRangeSlider(lower: $low, upper: $high, bounds: 0...200_000, step: 500, lowerLabel: "Min", upperLabel: "Max")
        TaleedRangeSlider(lower: $low, upper: $high, bounds: 0...200_000, step: 500, lowerLabel: "Min", upperLabel: "Max")
            .environment(\.layoutDirection, .rightToLeft)
        Text("\(low) – \(high)")
    }
    .padding()
}
