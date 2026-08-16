#if os(macOS)
import AppKit
import Foundation
import SwiftTerm

final class TerminalSession {
    let shellPath: String

    private weak var terminalView: LocalProcessTerminalView?
    private var didStart = false

    init() {
        shellPath = Self.resolveShell()
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
            currentDirectory: NSHomeDirectory()
        )
    }

    func sendInput(_ data: Data) {
        guard !data.isEmpty, let process = terminalView?.process else { return }
        process.send(data: ArraySlice([UInt8](data)))
    }

    func stop() {
        terminalView?.terminate()
        didStart = false
    }

    deinit {
        terminalView?.terminate()
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
}
#endif
