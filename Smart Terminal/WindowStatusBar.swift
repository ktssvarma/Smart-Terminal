#if os(macOS)
import AppKit
import Combine
import Darwin
import SwiftUI

struct WindowStatusBar: View {
    @ObservedObject var tab: TerminalTab
    @StateObject private var git = GitMonitor()
    @State private var copied = false

    var body: some View {
        HStack(spacing: AppTheme.space2) {
            if let branch = git.branch {
                Button(action: { copy(branch) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                        Text(copied ? "Copied" : branch)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy branch name")

                Button(action: git.fetch) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .rotationEffect(.degrees(git.isFetching ? 360 : 0))
                        .animation(
                            git.isFetching
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: git.isFetching
                        )
                }
                .buttonStyle(.plain)
                .disabled(git.isFetching)
                .help(git.isFetching ? "Fetching…" : "git fetch")

                commitDelta(icon: "arrow.down", count: git.behind, help: "\(git.behind) commit(s) behind remote")
                commitDelta(icon: "arrow.up", count: git.ahead, help: "\(git.ahead) commit(s) ahead of remote")

                if let author = git.lastCommitAuthor, let date = git.lastCommitDate {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        HStack(spacing: 4) {
                            Image(systemName: "person")
                                .font(.system(size: 9, weight: .semibold))
                            Text(author)
                                .lineLimit(1)
                            Text("·")
                            Text(relativeTime(from: date, now: timeline.date))
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .help("Last commit by \(author)")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.space3)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
        .background(AppTheme.sidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
        .onAppear {
            git.update(path: tab.currentPath)
        }
        .onChange(of: tab.currentPath) { _, path in
            copied = false
            git.update(path: path)
        }
        .onChange(of: tab.isCommandRunning) { _, running in
            if !running {
                git.refreshStatus()
            }
        }
        .onChange(of: tab.id) { _, _ in
            copied = false
        }
    }

    private func commitDelta(icon: String, count: Int, help: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .help(help)
    }

    private func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if seconds < 86_400 * 30 {
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        if seconds < 86_400 * 365 {
            let months = Int(seconds / (86_400 * 30))
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        let years = Int(seconds / (86_400 * 365))
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }

    private func copy(_ branch: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(branch, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}

final class GitMonitor: ObservableObject {
    @Published private(set) var branch: String?
    @Published private(set) var ahead = 0
    @Published private(set) var behind = 0
    @Published private(set) var lastCommitAuthor: String?
    @Published private(set) var lastCommitDate: Date?
    @Published private(set) var isFetching = false

    private var path = ""
    private var generation = 0
    private var lastHeadSignature: String?
    private var headTimer: Timer?
    private var headSource: DispatchSourceFileSystemObject?
    private var headFileDescriptor: Int32 = -1

    deinit {
        stopWatching()
    }

    func update(path: String) {
        let pathChanged = path != self.path
        self.path = path
        if pathChanged {
            lastHeadSignature = nil
            startWatching()
        }
        refreshStatus()
    }

    func refreshStatus() {
        generation += 1
        let token = generation
        let path = self.path
        DispatchQueue.global(qos: .utility).async {
            let snapshot = GitStatus.snapshot(for: path)
            let signature = GitStatus.headSignature(for: path)
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.apply(snapshot, signature: signature)
            }
        }
    }

    func fetch() {
        guard !isFetching, GitStatus.repositoryRoot(for: path) != nil else { return }
        isFetching = true
        let path = self.path
        DispatchQueue.global(qos: .userInitiated).async {
            if let root = GitStatus.repositoryRoot(for: path) {
                _ = GitStatus.run(["fetch", "--quiet"], in: root, timeout: 45)
            }
            let snapshot = GitStatus.snapshot(for: path)
            let signature = GitStatus.headSignature(for: path)
            DispatchQueue.main.async {
                self.isFetching = false
                self.apply(snapshot, signature: signature)
            }
        }
    }

    private func apply(_ snapshot: GitStatus.Snapshot, signature: String?) {
        lastHeadSignature = signature
        branch = snapshot.branch
        ahead = snapshot.ahead
        behind = snapshot.behind
        lastCommitAuthor = snapshot.author
        lastCommitDate = snapshot.date
    }

    private func startWatching() {
        stopWatching()
        guard GitStatus.repositoryRoot(for: path) != nil else { return }
        armHeadWatch()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkHeadChanged()
        }
        RunLoop.main.add(timer, forMode: .common)
        headTimer = timer
    }

    private func stopWatching() {
        headTimer?.invalidate()
        headTimer = nil
        cancelHeadWatch()
    }

    private func checkHeadChanged() {
        let signature = GitStatus.headSignature(for: path)
        guard signature != lastHeadSignature else { return }
        lastHeadSignature = signature
        refreshStatus()
        armHeadWatch()
    }

    private func armHeadWatch() {
        cancelHeadWatch()
        guard let headPath = GitStatus.headFilePath(for: path) else { return }
        let fd = open(headPath, O_EVTONLY)
        guard fd >= 0 else { return }
        headFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.checkHeadChanged()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        headSource = source
    }

    private func cancelHeadWatch() {
        headSource?.cancel()
        headSource = nil
        headFileDescriptor = -1
    }
}

enum GitStatus {
    struct Snapshot {
        var branch: String?
        var ahead: Int
        var behind: Int
        var author: String?
        var date: Date?
    }

    static func snapshot(for path: String) -> Snapshot {
        guard let root = repositoryRoot(for: path) else {
            return Snapshot(branch: nil, ahead: 0, behind: 0)
        }
        let branch = branch(for: path)
        var ahead = 0
        var behind = 0
        if let output = run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: root),
           let counts = parseAheadBehind(output) {
            ahead = counts.ahead
            behind = counts.behind
        }
        let commit = lastCommit(in: root)
        return Snapshot(branch: branch, ahead: ahead, behind: behind, author: commit.author, date: commit.date)
    }

    private static func lastCommit(in root: String) -> (author: String?, date: Date?) {
        guard let output = run(["-c", "log.showSignature=false", "log", "-1", "--format=%an%n%at"], in: root) else {
            return (nil, nil)
        }
        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard let last = lines.last, let timestamp = TimeInterval(last) else {
            return (nil, nil)
        }
        let author = lines.dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (author.isEmpty ? nil : author, Date(timeIntervalSince1970: timestamp))
    }

    static func repositoryRoot(for path: String) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            let gitURL = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    static func headSignature(for path: String) -> String? {
        guard let headPath = headFilePath(for: path) else { return nil }
        return try? String(contentsOfFile: headPath, encoding: .utf8)
    }

    static func headFilePath(for path: String) -> String? {
        guard let root = repositoryRoot(for: path) else { return nil }
        return gitDirectory(at: URL(fileURLWithPath: root))?.appendingPathComponent("HEAD").path
    }

    static func branch(for path: String) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            if let branch = branch(inRepositoryAt: current) {
                return branch
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    @discardableResult
    static func run(_ arguments: [String], in directory: String, timeout: TimeInterval = 8) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GCM_INTERACTIVE"] = "never"
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func parseAheadBehind(_ output: String) -> (ahead: Int, behind: Int)? {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) else {
            return nil
        }
        return (ahead, behind)
    }

    private static func gitDirectory(at directory: URL) -> URL? {
        let gitURL = directory.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return gitURL
        }
        return resolvedGitDirectory(from: gitURL, relativeTo: directory)
    }

    private static func branch(inRepositoryAt directory: URL) -> String? {
        guard let gitDir = gitDirectory(at: directory) else { return nil }
        return headName(in: gitDir)
    }

    private static func resolvedGitDirectory(from gitFile: URL, relativeTo directory: URL) -> URL? {
        guard let contents = try? String(contentsOf: gitFile, encoding: .utf8) else { return nil }
        guard let line = contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else {
            return nil
        }
        let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, relativeTo: directory).standardizedFileURL
    }

    private static func headName(in gitDir: URL) -> String? {
        let headURL = gitDir.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !head.isEmpty else { return nil }

        if head.hasPrefix("ref:") {
            let ref = head.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            if ref.hasPrefix("refs/heads/") {
                return String(ref.dropFirst("refs/heads/".count))
            }
            return URL(fileURLWithPath: ref).lastPathComponent
        }

        return String(head.prefix(7))
    }
}
#endif
