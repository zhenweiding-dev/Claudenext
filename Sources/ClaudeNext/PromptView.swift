import SwiftUI

struct RootView: View {
    @ObservedObject var model: PromptModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.of(scheme)

        VStack(spacing: 0) {
            if let request = model.pending.first {
                PromptView(model: model, request: request)
                    .id(request.id)
                    .transition(.opacity)
            } else {
                IdleView(model: model)
            }
        }
        .frame(width: 420)
        .environment(\.palette, palette)
        .background(palette.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }
}

// MARK: - The permission prompt

struct PromptView: View {
    @ObservedObject var model: PromptModel
    @ObservedObject var request: PendingRequest
    @Environment(\.palette) private var palette
    @State private var message: String = ""
    @FocusState private var messageFocused: Bool

    private var p: Presentation { request.presentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(palette.subtleBorder)
            body_
            Divider().overlay(palette.subtleBorder)
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(palette.accent)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let subtitle = p.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if model.pending.count > 1 {
                Text("+\(model.pending.count - 1)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(palette.hover))
                    .help("\(model.pending.count - 1) more request(s) waiting")
            }

            Text(p.badge)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent.opacity(0.12))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Body

    private var body_: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(p.blocks) { block in
                    blockView(block)
                }
                if p.blocks.isEmpty {
                    Text("No additional details.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 260)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func blockView(_ block: Presentation.Block) -> some View {
        switch block {
        case .code(let text):
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.codeBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(palette.subtleBorder, lineWidth: 1)
                )

        case .note(let text):
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .diff(let removed, let added):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(removed.enumerated()), id: \.offset) { _, line in
                    diffLine("-", line, fg: palette.delFg, bg: palette.delBg)
                }
                ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                    diffLine("+", line, fg: palette.addFg, bg: palette.addBg)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.subtleBorder, lineWidth: 1)
            )

        case .field(let label, let value):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .frame(width: 92, alignment: .leading)
                Text(value)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func diffLine(_ sign: String, _ line: String, fg: Color, bg: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(sign)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(fg.opacity(0.7))
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(bg)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Tell Claude what to do differently…", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .lineLimit(1...4)
                .focused($messageFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(messageFocused ? palette.accent.opacity(0.55) : palette.border,
                                      lineWidth: 1)
                )
                .onSubmit { decide(.deny, remember: false) }

            HStack(spacing: 8) {
                Button {
                    decide(.deny, remember: model.optionDown)
                } label: {
                    HStack(spacing: 5) {
                        Text(model.optionDown ? "Always deny" : "Deny")
                        KeyCapLabel(text: "esc", color: palette.danger)
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette, tint: palette.danger))
                .keyboardShortcut(.cancelAction)
                .help(model.optionDown
                      ? "Remember this as a deny rule"
                      : "Block this call. Anything typed above is sent to Claude as the reason.")

                Spacer(minLength: 0)

                if let rule = request.payload.suggestedRule, !rule.isEmpty {
                    Button {
                        decide(.allow, remember: true)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Always allow")
                            KeyCapLabel(text: "⌘A", color: palette.text)
                        }
                    }
                    .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette))
                    .keyboardShortcut("a", modifiers: .command)
                    .help("Adds the rule \(rule) to \(model.rememberScopeLabel)")
                }

                Button {
                    decide(.allow, remember: false)
                } label: {
                    HStack(spacing: 5) {
                        Text("Allow")
                        KeyCapLabel(text: "↩", color: palette.onAccent)
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .primary, palette: palette))
                .keyboardShortcut(.defaultAction)
            }

            if let rule = request.payload.suggestedRule, !rule.isEmpty {
                HStack(spacing: 5) {
                    Text("Always allow adds")
                        .foregroundStyle(palette.faint)
                    Text(rule)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .textSelection(.enabled)
                }
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    private func decide(_ kind: PromptDecision.Kind, remember: Bool) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        model.resolve(request,
                      with: PromptDecision(decision: kind,
                                         remember: remember,
                                         message: trimmed.isEmpty ? nil : trimmed))
    }
}

// MARK: - Nothing pending

struct IdleView: View {
    @ObservedObject var model: PromptModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(model.paused ? palette.faint : palette.addFg)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.paused ? "Paused" : "Watching for requests")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(model.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                Button(model.paused ? "Resume" : "Pause") {
                    model.paused.toggle()
                }
                .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let error = model.serverError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider().overlay(palette.subtleBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.faint)

                if model.recent.isEmpty {
                    Text("No decisions yet this session.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.faint)
                        .padding(.vertical, 2)
                } else {
                    ForEach(model.recent.prefix(6)) { item in
                        HStack(spacing: 8) {
                            Text(item.kind == .allow ? "allow" : "deny")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(item.kind == .allow ? palette.addFg : palette.delFg)
                                .frame(width: 34, alignment: .leading)
                            Text(item.toolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.text)
                            Text(item.summary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            if item.remembered {
                                Text("saved")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(palette.faint)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider().overlay(palette.subtleBorder)

            HStack(spacing: 4) {
                Button("Rules…") { model.openRulesFile() }
                    .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                Button("Config…") { model.openConfigFile() }
                    .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}
