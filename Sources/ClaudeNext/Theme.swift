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

/// Colours taken from the Claude app's own token set (`app.asar`).
///
/// The panel is a popover, so its background is `--surface-popover`
/// (`--surface-3` → `--gray-0`), not the page canvas. Everything else follows
/// the same `--gray-*` / `--neutral-*` ramp the app ships, which is a neutral
/// scale rather than the older warm `--bg-*` one.
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
        bg: hexColor(0xFFFFFF),           // surface-3 · gray-0
        surface: hexColor(0xFCFCFB),      // surface-1 · gray-10
        codeBg: hexColor(0xF0EFEC),       // gray-50
        border: hexColor(0xE7E7E7),       // alpha-2 over white
        subtleBorder: hexColor(0xF3F3F3), // alpha-1 over white
        text: hexColor(0x0B0B0B),         // neutral-900
        muted: hexColor(0x52514E),        // neutral-600
        faint: hexColor(0x898781),        // neutral-400
        accent: hexColor(0xD97757),       // accent-brand
        accentPressed: hexColor(0xC2664A),
        onAccent: hexColor(0xFFFFFF),     // on-brand · gray-0
        danger: hexColor(0xB03A2A),
        addFg: hexColor(0x1E9E3C),        // text-git-added
        addBg: hexColor(0xE9F5EC),
        delFg: hexColor(0xCD2054),        // text-git-removed
        delBg: hexColor(0xFAE9EE),
        hover: hexColor(0x000000, 0.05)   // alpha-1
    )

    static let dark = Palette(
        bg: hexColor(0x383835),           // surface-3 · gray-700
        surface: hexColor(0x1A1A19),      // surface-1 · gray-830
        codeBg: hexColor(0x20201F),       // gray-800
        border: hexColor(0x4C4C49),       // alpha-2 over surface-3
        subtleBorder: hexColor(0x42423F), // alpha-1 over surface-3
        text: hexColor(0xFFFFFF),         // neutral-900 · gray-0
        muted: hexColor(0xA5A49A),        // neutral-600 · gray-300
        faint: hexColor(0x6D6B67),        // neutral-400 · gray-500
        accent: hexColor(0xD97757),
        accentPressed: hexColor(0xE28C6F),
        onAccent: hexColor(0xFFFFFF),     // on-brand is gray-0 in both modes
        danger: hexColor(0xE0705C),
        addFg: hexColor(0x32D74B),
        addBg: hexColor(0x374838),
        delFg: hexColor(0xFF2C56),
        delBg: hexColor(0x4C3738),
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
