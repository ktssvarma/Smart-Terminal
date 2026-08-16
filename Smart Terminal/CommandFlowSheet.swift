#if os(macOS)
import SwiftUI

struct FlowStep: Identifiable, Hashable {
    var id = UUID()
    var text: String = ""
    var continueOn: Set<CommandOutcome> = [.success]
    var notifyOn: Set<CommandOutcome> = [.error, .warning]
}

struct CommandFlowSheet: View {
    @ObservedObject var tab: TerminalTab
    @Environment(\.dismiss) private var dismiss
    @State private var steps: [FlowStep] = [FlowStep()]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AppTheme.border)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        FlowStepCard(
                            step: binding(for: step.id),
                            canDelete: steps.count > 1,
                            onDelete: {
                                steps.removeAll { $0.id == step.id }
                                highlightLastStepSuccess()
                            }
                        )
                        if index < steps.count - 1 {
                            FlowContinuePicker(selection: continueBinding(for: steps[index + 1].id))
                        } else {
                            flowExit
                        }
                    }
                    Button(action: addStep) {
                        Label("Add step", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppTheme.space3)
                }
                .padding(AppTheme.space4)
            }
            Divider().overlay(AppTheme.border)
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(AppTheme.window)
        .onAppear {
            loadFromQueue()
            highlightLastStepSuccess()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Command Flow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Run steps in order. Choose when to continue to the next step, or exit.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.space4)
    }

    private var footer: some View {
        HStack {
            Text("Success = 0, warning = 1, error = 2+")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Button(action: runFlow) {
                Text("Run flow")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                            .fill(canRun ? AppTheme.fillActive : AppTheme.fillUtility)
                    )
                    .foregroundStyle(canRun ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canRun)
        }
        .padding(AppTheme.space4)
    }

    private var flowExit: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 10)
            Text("exit")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(AppTheme.fillUtility)
                )
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 10)
        }
        .frame(maxWidth: .infinity)
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

    private func loadFromQueue() {
        var loaded: [FlowStep] = []
        if tab.isCommandRunning || tab.isQueuePaused {
            loaded.append(contentsOf: tab.commandQueue.map(FlowStep.init))
        } else if !tab.commandQueue.isEmpty {
            loaded.append(contentsOf: tab.commandQueue.map(FlowStep.init))
        }
        if loaded.isEmpty {
            steps = [FlowStep()]
        } else {
            steps = loaded.enumerated().map { index, step in
                var updated = step
                if index > 0, updated.continueOn.isEmpty {
                    updated.continueOn = [.success]
                }
                return updated
            }
        }
    }

    private func runFlow() {
        let commands = steps.compactMap { step -> QueuedCommand? in
            let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return QueuedCommand(text: text, continueOn: step.continueOn, notifyOn: step.notifyOn)
        }
        tab.runFlow(commands)
        dismiss()
    }
}

private struct FlowStepCard: View {
    @Binding var step: FlowStep
    var canDelete: Bool
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.space2) {
            TextField("Command", text: $step.text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
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
        .padding(AppTheme.space3)
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

private struct FlowContinuePicker: View {
    @Binding var selection: CommandOutcome

    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 10)
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
            .frame(width: 110)
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension FlowStep {
    init(_ command: QueuedCommand) {
        self.init(id: command.id, text: command.text, continueOn: command.continueOn, notifyOn: command.notifyOn)
    }
}
#endif
