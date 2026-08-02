import SwiftUI

func hexColor(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}

/// Colours lifted from Claude's own surfaces: cream canvas, ivory panels,
/// the terracotta accent, and the warm-grey dark mode.
struct Palette {
    var bg: Color
    var surface: Color
    var codeBg: Color
    var border: Color
    var subtleBorder: Color
    var text: Color
    var muted: Color
    var faint: Color
    var accent: Color
    var accentPressed: Color
    var onAccent: Color
    var danger: Color
    var addFg: Color
    var addBg: Color
    var delFg: Color
    var delBg: Color
    var hover: Color

    static let light = Palette(
        bg: hexColor(0xFAF9F5),
        surface: hexColor(0xFFFFFF),
        codeBg: hexColor(0xF2F1EA),
        border: hexColor(0xDEDCD3),
        subtleBorder: hexColor(0xE9E7DF),
        text: hexColor(0x1F1E1D),
        muted: hexColor(0x73726C),
        faint: hexColor(0x9A9890),
        accent: hexColor(0xD97757),
        accentPressed: hexColor(0xC2664A),
        onAccent: hexColor(0xFFFFFF),
        danger: hexColor(0xB03A2A),
        addFg: hexColor(0x2C6E49),
        addBg: hexColor(0xE6F2EA),
        delFg: hexColor(0xA33A28),
        delBg: hexColor(0xFAE9E5),
        hover: hexColor(0x000000, 0.05)
    )

    static let dark = Palette(
        bg: hexColor(0x262624),
        surface: hexColor(0x30302E),
        codeBg: hexColor(0x1E1E1C),
        border: hexColor(0x45443F),
        subtleBorder: hexColor(0x3A3936),
        text: hexColor(0xF5F4EE),
        muted: hexColor(0xA6A49C),
        faint: hexColor(0x7C7A73),
        accent: hexColor(0xD97757),
        accentPressed: hexColor(0xE28C6F),
        onAccent: hexColor(0x1F1E1D),
        danger: hexColor(0xE0705C),
        addFg: hexColor(0x7BC49A),
        addBg: hexColor(0x1F2E26),
        delFg: hexColor(0xE0836F),
        delBg: hexColor(0x33221F),
        hover: hexColor(0xFFFFFF, 0.07)
    )

    static func of(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Buttons

struct ActionButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, quiet }

    var variant: Variant
    var palette: Palette
    var tint: Color? = nil

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = {
            switch variant {
            case .primary: return palette.onAccent
            case .secondary, .quiet: return tint ?? palette.text
            }
        }()

        let bg: Color = {
            switch variant {
            case .primary:
                return configuration.isPressed ? palette.accentPressed : palette.accent
            case .secondary:
                return configuration.isPressed ? palette.hover : (hovering ? palette.hover : .clear)
            case .quiet:
                return configuration.isPressed || hovering ? palette.hover : .clear
            }
        }()

        return configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, variant == .quiet ? 8 : 12)
            .padding(.vertical, 6.5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(variant == .secondary ? palette.border : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// The little "⌘⏎" hints on the buttons.
struct KeyCapLabel: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color.opacity(0.65))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}
