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

    var onCommandRunningChange: ((Bool) -> Void)?
    private(set) var lastExitCode: Int?
    private var isCapturingOutput = false
    private var capturedOutput = ""

    private weak var terminalView: LocalProcessTerminalView?
    private var didStart = false
    private var activityTimer: Timer?
    private var isCommandRunning = false

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
        startActivityMonitor()
    }

    func sendInput(_ data: Data) {
        guard !data.isEmpty, let process = terminalView?.process else { return }
        process.send(data: ArraySlice([UInt8](data)))
    }

    func sendCommand(_ command: String) {
        lastExitCode = nil
        beginOutputCapture()
        clearInputLine()
        sendLine(command)
    }

    func beginOutputCapture() {
        capturedOutput = ""
        isCapturingOutput = true
    }

    func appendCapturedOutput(_ text: String) {
        guard isCapturingOutput, !text.isEmpty else { return }
        capturedOutput.append(text)
        if capturedOutput.count > 80_000 {
            capturedOutput.removeFirst(capturedOutput.count - 60_000)
        }
    }

    func endOutputCapture() -> String {
        isCapturingOutput = false
        return capturedOutput
    }

    func probeLastExitCode(timeout: TimeInterval = 0.8, completion: @escaping (Int?) -> Void) {
        lastExitCode = nil
        clearInputLine()
        sendLine("echo __ST_EXIT:$?__")
        waitForExitCode(timeout: timeout, completion: completion)
    }

    func clearInputLine() {
        sendInput(Data([0x15]))
    }

    func acceptExitCode(_ code: Int) {
        lastExitCode = code
    }

    func waitForExitCode(timeout: TimeInterval = 0.4, completion: @escaping (Int?) -> Void) {
        if let lastExitCode {
            completion(lastExitCode)
            return
        }
        let started = Date()
        func poll() {
            if let lastExitCode {
                completion(lastExitCode)
                return
            }
            if Date().timeIntervalSince(started) >= timeout {
                completion(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }

    private func sendLine(_ command: String) {
        var line = command
        if !line.hasSuffix("\r"), !line.hasSuffix("\n") {
            line += "\r"
        }
        sendInput(Data(line.utf8))
    }

    func updateWorkingDirectory(_ directory: String?) {
        guard let path = Self.normalizedPath(directory) else { return }
        publishWorkingDirectory(path)
    }

    func resolvedWorkingDirectory() -> String? {
        if let live = processWorkingDirectory(), FileManager.default.fileExists(atPath: live) {
            return live
        }
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory) {
            return workingDirectory
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

    var isBusy: Bool {
        isForegroundCommandRunning() || hasListeningPort()
    }

    func isForegroundCommandRunning() -> Bool {
        guard let process = terminalView?.process else { return false }
        let fd = process.childfd
        let shellPid = process.shellPid
        guard fd >= 0, shellPid > 0 else { return false }

        let foreground = Self.foregroundProcessGroup(fd: fd)
        let shellGroup = getpgid(shellPid)
        guard foreground > 0, shellGroup > 0 else { return false }
        return foreground != shellGroup
    }

    func hasListeningPort() -> Bool {
        guard let pid = terminalView?.process.shellPid, pid > 0 else { return false }
        return Self.processTree(from: pid).contains { Self.hasListeningTCP(pid: $0) }
    }

    func stop() {
        stopActivityMonitor()
        terminalView?.terminate()
        didStart = false
        publishCommandRunning(false)
    }

    deinit {
        stopActivityMonitor()
        terminalView?.terminate()
    }

    private func startActivityMonitor() {
        guard activityTimer == nil else { return }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.refreshCommandActivity()
        }
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
        refreshCommandActivity()
    }

    private func stopActivityMonitor() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    private func refreshCommandActivity() {
        publishCommandRunning(isForegroundCommandRunning())
        if let live = processWorkingDirectory(), FileManager.default.fileExists(atPath: live) {
            publishWorkingDirectory(live)
        }
    }

    private func publishWorkingDirectory(_ path: String) {
        guard path != workingDirectory else { return }
        workingDirectory = path
        onWorkingDirectoryChange?(path)
    }

    private static func normalizedPath(_ directory: String?) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        if directory.hasPrefix("file:"), let url = URL(string: directory), url.isFileURL {
            let path = url.path
            return path.isEmpty ? nil : path
        }
        return directory
    }

    private func publishCommandRunning(_ running: Bool) {
        guard running != isCommandRunning else { return }
        isCommandRunning = running
        onCommandRunningChange?(running)
    }

    private static func foregroundProcessGroup(fd: Int32) -> pid_t {
        let group = tcgetpgrp(fd)
        if group > 0 {
            return group
        }
        var pgrp: pid_t = 0
        if ioctl(fd, TIOCGPGRP, &pgrp) == 0, pgrp > 0 {
            return pgrp
        }
        return -1
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

    private static func processTree(from root: pid_t) -> [pid_t] {
        var seen = Set<pid_t>()
        var stack = [root]
        var result: [pid_t] = []
        while let pid = stack.popLast() {
            guard pid > 0, seen.insert(pid).inserted else { continue }
            result.append(pid)
            stack.append(contentsOf: childPids(of: pid))
        }
        return result
    }

    private static func childPids(of parent: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 128)
        let bytes = proc_listchildpids(parent, &buffer, Int32(MemoryLayout<pid_t>.stride * buffer.count))
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<pid_t>.stride
        return Array(buffer.prefix(count)).filter { $0 > 0 }
    }

    private static func hasListeningTCP(pid: pid_t) -> Bool {
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return false }

        let count = Int(listSize) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, listSize)
        guard written > 0 else { return false }

        let available = Int(written) / MemoryLayout<proc_fdinfo>.stride
        for index in 0..<available {
            let fd = fds[index]
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }

            var info = socket_fdinfo()
            let infoSize = Int32(MemoryLayout<socket_fdinfo>.stride)
            let infoWritten = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize)
            guard infoWritten >= infoSize else { continue }
            if info.psi.soi_kind == SOCKINFO_TCP, info.psi.soi_proto.pri_tcp.tcpsi_state == TCPS_LISTEN {
                return true
            }
        }
        return false
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
