#if os(macOS)
import AppKit
import SwiftUI

struct FlowStep: Identifiable, Hashable {
    var id = UUID()
    var text: String = ""
    var continueOn: Set<CommandOutcome> = [.success]
    var notifyOn: Set<CommandOutcome> = [.error, .warning]
}

struct CommandFlowEditor<LeadingToolbar: View>: View {
    @ObservedObject var tab: TerminalTab
    @Binding var fillCommand: String
    var leadingToolbar: LeadingToolbar
    @State private var steps: [FlowStep] = [FlowStep()]
    @FocusState private var focusedStepID: UUID?

    init(
        tab: TerminalTab,
        fillCommand: Binding<String>,
        @ViewBuilder leadingToolbar: () -> LeadingToolbar
    ) {
        self.tab = tab
        self._fillCommand = fillCommand
        self.leadingToolbar = leadingToolbar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space2) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                FlowStepCard(
                    step: binding(for: step.id),
                    continueOn: index > 0 ? continueBinding(for: step.id) : nil,
                    focusedStepID: $focusedStepID,
                    history: tab.commandHistory,
                    canDelete: steps.count > 1,
                    onDelete: {
                        steps.removeAll { $0.id == step.id }
                        highlightLastStepSuccess()
                    },
                    onSubmit: runFlow
                )
            }

            HStack(spacing: AppTheme.space2) {
                leadingToolbar

                Button(action: addStep) {
                    Label("Add step", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: runFlow) {
                    Text("Run flow")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                                .fill(canRun ? AppTheme.fillActive : AppTheme.fillUtility)
                        )
                        .foregroundStyle(canRun ? AppTheme.textPrimary : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
            }
            .padding(.top, AppTheme.space2)
        }
        .onAppear {
            highlightLastStepSuccess()
        }
        .onChange(of: focusedStepID) { _, newValue in
            CommandFieldFocus.isActive = newValue != nil
        }
        .onChange(of: fillCommand) { _, command in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            applyFilledCommand(trimmed)
            fillCommand = ""
        }
    }

    private func continueBinding(for id: UUID) -> Binding<CommandOutcome> {
        Binding(
            get: {
                let selected = steps.first(where: { $0.id == id })?.continueOn ?? []
                return CommandOutcome.allCases.first { selected.contains($0) } ?? .success
            },
            set: { outcome in
                if let index = steps.firstIndex(where: { $0.id == id }) {
                    steps[index].continueOn = [outcome]
                }
            }
        )
    }

    private var canRun: Bool {
        steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func binding(for id: UUID) -> Binding<FlowStep> {
        Binding(
            get: { steps.first(where: { $0.id == id }) ?? FlowStep(id: id) },
            set: { updated in
                if let index = steps.firstIndex(where: { $0.id == id }) {
                    steps[index] = updated
                }
            }
        )
    }

    private func addStep() {
        steps.append(FlowStep(continueOn: [.success]))
        highlightLastStepSuccess()
    }

    private func highlightLastStepSuccess() {
        guard !steps.isEmpty else { return }
        for index in steps.indices {
            if index == steps.count - 1 {
                steps[index].notifyOn.insert(.success)
            } else {
                steps[index].notifyOn.remove(.success)
            }
        }
    }

    private func applyFilledCommand(_ command: String) {
        if let empty = steps.lastIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            steps[empty].text = command
        } else if let last = steps.indices.last {
            steps[last].text = command
        } else {
            steps = [FlowStep(text: command, notifyOn: [.success, .error, .warning])]
        }
    }

    private func runFlow() {
        let commands = steps.compactMap { step -> QueuedCommand? in
            let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return QueuedCommand(text: text, continueOn: step.continueOn, notifyOn: step.notifyOn)
        }
        guard !commands.isEmpty else { return }
        tab.runFlow(commands)
        let firstID = steps.first?.id ?? UUID()
        steps = [FlowStep(id: firstID)]
        highlightLastStepSuccess()
        focusDefaultField(id: firstID)
    }

    private func focusDefaultField(id: UUID) {
        CommandFieldFocus.isActive = true
        focusedStepID = id
        for delay in [0.0, 0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                CommandFieldFocus.isActive = true
                focusedStepID = id
            }
        }
    }
}

private struct FlowStepCard: View {
    @Binding var step: FlowStep
    var continueOn: Binding<CommandOutcome>?
    var focusedStepID: FocusState<UUID?>.Binding
    var history: [String]
    var canDelete: Bool
    var onDelete: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.space2) {
            if let continueOn {
                FlowContinuePicker(selection: continueOn)
            }

            CommandHistoryTextField(
                text: $step.text,
                placeholder: "Command",
                history: history,
                shouldFocus: focusedStepID.wrappedValue == step.id,
                onSubmit: onSubmit
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .fill(AppTheme.header)
            )

            notifyIcons

            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .help("Remove step")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .fill(AppTheme.sidebar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var notifyIcons: some View {
        HStack(spacing: 6) {
            ForEach(CommandOutcome.allCases) { outcome in
                let isOn = step.notifyOn.contains(outcome)
                Button {
                    if isOn {
                        step.notifyOn.remove(outcome)
                    } else {
                        step.notifyOn.insert(outcome)
                    }
                } label: {
                    Image(systemName: outcome.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? outcome.color : AppTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                                .fill(isOn ? outcome.color.opacity(0.18) : AppTheme.fillUtility)
                        )
                }
                .buttonStyle(.plain)
                .help("Notify on \(outcome.title)")
            }
        }
    }
}

private struct CommandHistoryTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var history: [String]
    var shouldFocus: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, history: history, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.history = history
        context.coordinator.onSubmit = onSubmit
        nsView.placeholderString = placeholder
        if nsView.stringValue != text, nsView.currentEditor() == nil || text.isEmpty {
            nsView.stringValue = text
        }
        if shouldFocus, CommandFieldFocus.isActive {
            CommandFieldFocus.claim(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var history: [String]
        var onSubmit: () -> Void
        private var historyIndex: Int?
        private var historyDraft = ""
        private var applyingHistory = false

        init(text: Binding<String>, history: [String], onSubmit: @escaping () -> Void) {
            self.text = text
            self.history = history
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            CommandFieldFocus.claim(field)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            if !applyingHistory {
                historyIndex = nil
                historyDraft = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                CommandFieldFocus.isActive = true
                onSubmit()
                if let field = control as? NSTextField {
                    applyingHistory = true
                    field.stringValue = ""
                    text.wrappedValue = ""
                    field.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
                    applyingHistory = false
                }
                historyIndex = nil
                historyDraft = ""
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                recall(delta: -1, in: control as? NSTextField)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                recall(delta: 1, in: control as? NSTextField)
                return true
            }
            return false
        }

        private func recall(delta: Int, in field: NSTextField?) {
            guard let field, !history.isEmpty else { return }
            if historyIndex == nil {
                guard delta < 0 else { return }
                historyDraft = field.stringValue
                historyIndex = history.count - 1
                apply(history[history.count - 1], to: field)
                return
            }
            var index = historyIndex! + delta
            if index < 0 {
                index = 0
            }
            if index >= history.count {
                historyIndex = nil
                apply(historyDraft, to: field)
                return
            }
            historyIndex = index
            apply(history[index], to: field)
        }

        private func apply(_ value: String, to field: NSTextField) {
            applyingHistory = true
            field.stringValue = value
            text.wrappedValue = value
            let end = (value as NSString).length
            field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
            applyingHistory = false
        }
    }
}

private struct FlowContinuePicker: View {
    @Binding var selection: CommandOutcome

    var body: some View {
        Menu {
            ForEach(CommandOutcome.allCases) { outcome in
                Button(outcome.title) {
                    selection = outcome
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text(selection.title)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(selection.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(selection.color.opacity(0.16))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Continue to this step if")
    }
}
#endif
