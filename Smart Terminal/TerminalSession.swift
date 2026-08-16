#if os(macOS)
import AppKit
import Darwin
import Foundation
import SwiftTerm

final class TerminalSession {
    let shellPath: String

    private let initialDirectory: String?
    private(set) var workingDirectory: String?
    var onWorkingDirectoryChange: ((String) -> Void)?

    private weak var terminalView: LocalProcessTerminalView?
    private var didStart = false

    init(workingDirectory: String? = nil) {
        shellPath = Self.resolveShell()
        initialDirectory = workingDirectory
        self.workingDirectory = workingDirectory
    }

    func attach(_ view: LocalProcessTerminalView) {
        terminalView = view
    }

    func startIfNeeded() {
        guard !didStart, let view = terminalView else { return }
        guard view.bounds.width > 1, view.bounds.height > 1 else { return }

        didStart = true
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        view.startProcess(
            executable: shellPath,
            args: ["-i"],
            environment: Self.environment(shell: shellPath),
            execName: "-\(shellName)",
            currentDirectory: initialDirectory ?? NSHomeDirectory()
        )
    }

    func sendInput(_ data: Data) {
        guard !data.isEmpty, let process = terminalView?.process else { return }
        process.send(data: ArraySlice([UInt8](data)))
    }

    func updateWorkingDirectory(_ directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        workingDirectory = directory
        onWorkingDirectoryChange?(directory)
    }

    func resolvedWorkingDirectory() -> String? {
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory) {
            return workingDirectory
        }
        if let live = processWorkingDirectory(), FileManager.default.fileExists(atPath: live) {
            workingDirectory = live
            return live
        }
        if let initialDirectory, FileManager.default.fileExists(atPath: initialDirectory) {
            return initialDirectory
        }
        return nil
    }

    func focus() {
        guard let terminalView else { return }
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func copySelection() {
        terminalView?.copy(())
    }

    func pasteClipboard() {
        terminalView?.paste(())
    }

    func selectAllText() {
        terminalView?.selectAll(nil)
    }

    func stop() {
        terminalView?.terminate()
        didStart = false
    }

    deinit {
        terminalView?.terminate()
    }

    private func processWorkingDirectory() -> String? {
        guard let pid = terminalView?.process.shellPid, pid > 0 else { return nil }
        return Self.workingDirectory(for: pid)
    }

    private static func resolveShell() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let shell = environment["SHELL"], FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }

        if let password = getpwuid(getuid()) {
            let shell = String(cString: password.pointee.pw_shell)
            if FileManager.default.isExecutableFile(atPath: shell) {
                return shell
            }
        }

        return "/bin/zsh"
    }

    private static func environment(shell: String) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["SHELL"] = shell
        if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
            env["HOME"] = NSHomeDirectory()
        }
        if env["PATH"] == nil || env["PATH"]?.isEmpty == true {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    private static func workingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let written = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard written > 0 else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { path in
                let directory = String(cString: path)
                return directory.isEmpty ? nil : directory
            }
        }
    }
}
#endif
