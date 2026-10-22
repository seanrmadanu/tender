import SwiftUI

enum Ink {
    static let green = Color(light: 0x173F35, dark: 0xDCE9D9)
    static let paper = Color(light: 0xF5F3E9, dark: 0x13251F)
    static let card = Color(light: 0xFFFDF5, dark: 0x20392F)
    static let muted = Color(light: 0x59685B, dark: 0xAEC1B0)
    static let line = Color(light: 0xC9CDBC, dark: 0x4C6555)
    static let accent = Color(light: 0x38634A, dark: 0xA5C9A3)
    static let warning = Color(light: 0x8E421F, dark: 0xF2BC91)
}
extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}
struct Engraving: View {
    var light = false
    var body: some View {
        Canvas { context, size in
            // Vector strokes stay crisp at every display scale. Keep engraving
            // decorative: solid cards always sit beneath financial text.
            let ink = (light ? Color.white : Ink.green)
            for line in 0..<36 {
                var path = Path()
                for step in 0...120 {
                    let x = size.width * CGFloat(step) / 120
                    let y = CGFloat(line) * 8 + sin(x / 46 + CGFloat(line) * 0.13) * 10
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(ink.opacity(light ? 0.07 : 0.045)), lineWidth: 0.5)
            }
            for i in 0..<48 {
                var path = Path()
                let offset = CGFloat(i) * 7
                path.move(to: CGPoint(x: -100 + offset, y: -40))
                path.addCurve(to: CGPoint(x: size.width + 70, y: size.height + offset), control1: CGPoint(x: size.width * 0.75 + offset, y: -60), control2: CGPoint(x: size.width * 0.1 + offset, y: size.height * 0.9))
                context.stroke(path, with: .color((light ? Color.white : Ink.green).opacity(light ? 0.13 : 0.11)), lineWidth: 0.7)
            }
            for ring in 0..<26 {
                var path = Path()
                for step in 0...360 {
                    let angle = Double(step) * .pi / 180
                    let radius = 28 + Double(ring) * 3.7 + sin(angle * 12) * (4 + Double(ring) * 0.16)
                    let point = CGPoint(x: size.width * 0.82 + CGFloat(cos(angle) * radius), y: size.height * 0.48 + CGFloat(sin(angle) * radius))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(ink.opacity(light ? 0.17 : 0.12)), lineWidth: 0.55)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct PaperScreen<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) { content }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 10)
        }.scrollDismissesKeyboard(.interactively)
            .background { Ink.paper.ignoresSafeArea(); Engraving().frame(height: 280).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea().opacity(0.6) }
            .foregroundStyle(Ink.green)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true } }
    }
}
struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.title2, design: .serif).weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Ink.muted) }
        }.accessibilityElement(children: .combine)
    }
}
struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Ink.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Ink.line, lineWidth: 0.7)).shadow(color: Ink.green.opacity(0.035), radius: 10, x: 0, y: 4) }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16).background(Ink.green.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Ink.paper)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
struct CategoryIcon: View {
    var symbol: String
    var body: some View { Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).background(Ink.paper, in: RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true) }
}
struct AmountRow: View {
    var label: String
    var amount: Int64
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(Ink.muted); Spacer(minLength: 16); value.fixedSize() }
            VStack(alignment: .leading, spacing: 6) { Text(label).foregroundStyle(Ink.muted); value }
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
    private var value: some View { MoneyText(amount: amount).fontWeight(.semibold).foregroundStyle(amount < 0 ? Ink.warning : Ink.green) }
}

struct MoneyText: View {
    var amount: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(Money.format(amount)).monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(amount)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: amount)
    }
}

struct BudgetMeter: View {
    var spent: Int64
    var limit: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { min(1, max(0, Double(spent) / Double(max(1, limit)))) }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.line.opacity(0.45))
                Capsule().fill(spent > limit ? Ink.warning : Ink.accent).frame(width: proxy.size.width * fraction)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: fraction)
            }
        }.frame(height: 7).accessibilityLabel("\(Money.format(spent)) spent of \(Money.format(limit)) allocated")
    }
}

extension View {
    func paperForm() -> some View {
        self.scrollContentBackground(.hidden).background(Ink.paper).tint(Ink.green)
    }
}
struct EmptyNote: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View { PaperCard { Image(systemName: symbol).font(.title); Text(title).font(.headline); Text(message).font(.subheadline).foregroundStyle(Ink.muted) } }
}

/// Padding belongs to each field's focus target, preserving native cursor gestures.
struct TenderField: View {
    var title: String
    @Binding var text: String
    var axis: Axis
    @FocusState private var focused: Bool
    init(_ title: String, text: Binding<String>, axis: Axis = .horizontal) { self.title = title; self._text = text; self.axis = axis }
    var body: some View {
        TextField(title, text: $text, axis: axis).focused($focused)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { focused = true })
    }
}
struct BottomAdd: ViewModifier {
    var title: String
    var identifier: String? = nil
    var enabled = true
    var action: () -> Void
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            Button(action: action) { Label(title, systemImage: "plus").font(.headline).padding(.horizontal, 18).frame(minHeight: 52) }
                .foregroundStyle(.white).background(Ink.green, in: Capsule()).shadow(radius: 3, y: 2)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .accessibilityIdentifier(identifier ?? title)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
        }
    }
}
extension View {
    // Pass an identifier when a sheet's button has the same title as one on the screen behind it.
    func bottomAdd(_ title: String, identifier: String? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View { modifier(BottomAdd(title: title, identifier: identifier, enabled: enabled, action: action)) }
}
