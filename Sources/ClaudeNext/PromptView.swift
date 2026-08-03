import SwiftUI

struct RootView: View {
    @ObservedObject var model: PromptModel
    @Environment(\.colorScheme) private var scheme

    /// Header plus the action row, so the scroll area and the window agree.
    private let chromeAllowance: CGFloat = 104

    var body: some View {
        let palette = Palette.of(scheme)

        VStack(spacing: 0) {
            StatusHeader(model: model)
            Divider().overlay(palette.subtleBorder)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        if model.pending.isEmpty {
                            RecentPane(model: model)
                        } else {
                            RequestList(model: model)
                        }
                        Divider().overlay(palette.subtleBorder)
                        GlobalSettings(model: model)
                    }
                }
                .frame(maxHeight: max(260, model.maxPanelHeight - chromeAllowance))
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: model.focusedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Divider().overlay(palette.subtleBorder)
            ActionRow(model: model)
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

// MARK: - Top: state and totals

struct StatusHeader: View {
    @ObservedObject var model: PromptModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(dotColour)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(model.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
            }

            Spacer(minLength: 8)

            if model.pending.count > 1 {
                Button { model.focusPrevious() } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Focus the previous request (⌘↑)")

                Button { model.focusNext() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                .keyboardShortcut(.downArrow, modifiers: .command)
                .help("Focus the next request (⌘↓)")
            }

            Button(model.paused ? "Resume" : "Pause") { model.paused.toggle() }
                .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var dotColour: Color {
        if model.paused { return palette.faint }
        return model.pending.isEmpty ? palette.addFg : palette.accent
    }

    private var title: String {
        if model.paused { return "Paused" }
        let count = model.pending.count
        if count == 0 { return "Watching for requests" }
        return "\(count) request\(count == 1 ? "" : "s") waiting"
    }
}

// MARK: - Middle: the notifications

struct RequestList: View {
    @ObservedObject var model: PromptModel

    var body: some View {
        let stacked = model.pending.count > 1
        VStack(spacing: stacked ? 10 : 0) {
            ForEach(model.pending) { request in
                PromptCard(model: model,
                           request: request,
                           stacked: stacked,
                           isFocused: model.focusedID == request.id)
                    .id(request.id)
            }
        }
        .padding(stacked ? 10 : 0)
    }
}

// MARK: - One permission prompt

struct PromptCard: View {
    @ObservedObject var model: PromptModel
    @ObservedObject var request: PendingRequest
    /// True when several requests share the panel and this needs its own frame.
    var stacked: Bool
    var isFocused: Bool

    @Environment(\.palette) private var palette
    @State private var message: String = ""
    @State private var askAboutExpanded = false
    @State private var contentExpanded = false
    @FocusState private var messageFocused: Bool

    private var p: Presentation { request.presentation }
    private var cwd: String { request.payload.cwd }
    /// Only the focused card answers the keyboard.
    private var live: Bool { !stacked || isFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(palette.subtleBorder)
            body_
            Divider().overlay(palette.subtleBorder)
            footer
            Divider().overlay(palette.subtleBorder)
            askAbout
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(stacked ? palette.surface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(stacked ? (isFocused ? palette.accent.opacity(0.65) : palette.border)
                                      : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded {
            model.focusedID = request.id
        })
        .onChange(of: messageFocused) { _, focused in
            if focused { model.focusedID = request.id }
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

                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.faint)
                    Text(p.project)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if let location = p.location {
                        Text("›")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.faint)
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    if let subtitle = p.subtitle, !subtitle.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.faint)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .help(p.projectPath)
            }

            Spacer(minLength: 8)

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

    /// Stacked cards grow to their (already line-clamped) content and let the
    /// list scroll; a lone card scrolls inside itself instead.
    @ViewBuilder
    private var body_: some View {
        if stacked {
            blocks
        } else {
            ScrollView(.vertical) { blocks }
                .frame(maxHeight: 260)
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Long diffs and file contents start folded — a card you have to scroll
    /// past to reach the buttons is worse than one that shows less.
    private static let foldOver = 8
    private static let foldTo = 3

    private var contentLines: Int {
        p.blocks.reduce(0) { total, block in
            switch block {
            case .code(let text): return total + text.components(separatedBy: "\n").count
            case .diff(let removed, let added): return total + removed.count + added.count
            case .note, .field: return total + 1
            }
        }
    }

    private var isFolded: Bool { contentLines > Self.foldOver && !contentExpanded }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(isFolded ? p.blocks.map { Self.shorten($0, to: Self.foldTo) } : p.blocks) {
                blockView($0)
            }
            if p.blocks.isEmpty {
                Text("No additional details.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.faint)
            }
            if contentLines > Self.foldOver {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { contentExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: contentExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                        Text(contentExpanded ? "Show less" : "Show all \(changeSummary)")
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(palette.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var changeSummary: String {
        var added = 0, removed = 0
        for case .diff(let r, let a) in p.blocks { removed += r.count; added += a.count }
        if added > 0 || removed > 0 { return "+\(added) −\(removed)" }
        return "· \(contentLines) lines"
    }

    private static func shorten(_ block: Presentation.Block, to limit: Int) -> Presentation.Block {
        switch block {
        case .code(let text):
            let lines = text.components(separatedBy: "\n")
            guard lines.count > limit else { return block }
            return .code(lines.prefix(limit).joined(separator: "\n") + "\n…")
        case .diff(let removed, let added):
            let half = max(1, limit / 2)
            return .diff(removed: Array(removed.prefix(half)),
                         added: Array(added.prefix(limit - min(half, removed.count))))
        case .note, .field:
            return block
        }
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
                    decide(.deny, remember: model.optionDown && live)
                } label: {
                    HStack(spacing: 5) {
                        Text(model.optionDown && live ? "Always deny" : "Deny")
                        if live { KeyCapLabel(text: "esc", color: palette.danger) }
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette, tint: palette.danger))
                .keyboardShortcut(live ? .cancelAction : nil)
                .help(model.optionDown && live
                      ? "Remember this as a deny rule"
                      : "Block this call. Anything typed above is sent to Claude as the reason.")

                Button {
                    model.resolve(request, with: PromptDecision(decision: .pass))
                } label: {
                    Text("Skip")
                }
                .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette,
                                               tint: palette.faint))
                .help("Leave this one to Claude Code's own prompt")

                Spacer(minLength: 0)

                if let rule = request.payload.suggestedRule, !rule.isEmpty {
                    Button {
                        decide(.allow, remember: true)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Always allow")
                            if live { KeyCapLabel(text: "⌘A", color: palette.text) }
                        }
                    }
                    .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette))
                    .keyboardShortcut(live ? KeyboardShortcut("a", modifiers: .command) : nil)
                    .help("Adds \(rule) to \(p.project)/.claude/settings.local.json")
                }

                Button {
                    decide(.allow, remember: false)
                } label: {
                    HStack(spacing: 5) {
                        Text("Allow")
                        if live { KeyCapLabel(text: "↩", color: palette.onAccent) }
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .primary, palette: palette))
                .keyboardShortcut(live ? .defaultAction : nil)
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

    // MARK: What this project asks about

    private var askAbout: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { askAboutExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: askAboutExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.faint)
                    Text("Ask about in \(p.project)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.faint)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if askAboutExpanded {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                    GridItem(.flexible(), spacing: 6),
                                    GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(AppConfig.knownTools, id: \.self) { tool in
                        toolChip(tool)
                    }
                }
                Text(model.projectHasOverride(cwd)
                     ? "Saved in \(p.project)/.claude/claudenext.json."
                     : "Currently following the global default; changing one writes this project's own file.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var summary: String {
        let on = AppConfig.knownTools.filter { model.interceptList(for: cwd).contains($0) }
        let scope = model.projectHasOverride(cwd) ? "" : " · global"
        return "\(on.count) tools\(scope)"
    }

    private func toolChip(_ tool: String) -> some View {
        let on = model.interceptList(for: cwd).contains(tool)
        return Button {
            model.toggleProjectIntercept(tool, cwd: cwd)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 9.5))
                    .foregroundStyle(on ? palette.accent : palette.faint)
                Text(tool)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(ActionButtonStyle(variant: .secondary, palette: palette,
                                       tint: on ? palette.text : palette.muted))
    }

    private func decide(_ kind: PromptDecision.Kind, remember: Bool) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        model.resolve(request,
                      with: PromptDecision(decision: kind,
                                         remember: remember,
                                         message: trimmed.isEmpty ? nil : trimmed))
    }
}

// MARK: - Middle when nothing is pending

struct RecentPane: View {
    @ObservedObject var model: PromptModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.serverError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Bottom: the few genuinely global switches

struct GlobalSettings: View {
    @ObservedObject var model: PromptModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SETTINGS")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(palette.faint)

            switchRow("Sound on a new request", model.config.sound) { on in
                model.editConfig { $0.sound = on }
            }
            switchRow("Open the panel automatically", model.config.autoOpenOnRequest) { on in
                model.editConfig { $0.autoOpenOnRequest = on }
            }
            switchRow("Hide the menu bar icon when idle", model.config.hideWhenIdle) { on in
                model.editConfig { $0.hideWhenIdle = on }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func switchRow(_ title: String, _ isOn: Bool,
                           _ change: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: change))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(palette.accent)
        }
    }

}

// MARK: - Pinned actions

struct ActionRow: View {
    @ObservedObject var model: PromptModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            // Editing rules and config by hand lives in the status item's
            // right-click menu, not underfoot in the panel.
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(ActionButtonStyle(variant: .quiet, palette: palette))
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
