import Darwin
import Foundation

/// A shell in a terminal of reel's own: zsh in a pseudo-terminal reel opens itself, with a home of its own, a fixed
/// prompt, no history and none of the Mac's shell setup, so a reel's commands look the same on every Mac. They are
/// real commands: a reel can only run what is installed.
final class TerminalSession: @unchecked Sendable {
    /// What zsh reads at start: the prompt (the folder, then reel's chevron), no history, and a mark after every
    /// command (OSC 133;D, as terminals that know about prompts use it) that `Wait exit` looks for.
    static let zshrc = """
    unsetopt PROMPT_SP BEEP
    unset HISTFILE
    SAVEHIST=0
    PROMPT=$'%F{6}%1~%f %F{3}\u{276F}%f '
    precmd() { print -n $'\\e]133;D;'"$?"$'\\a' }

    """
    /// The mark a command's end prints (`precmd`, above).
    static let exitMark = Array("\u{1b}]133;D;".utf8)

    let pid: pid_t
    private let pty: Int32
    private let home: URL
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var start = ContinuousClock.now
    private var lastOutput = ContinuousClock.now
    /// Everything printed, as printed: what waits look in.
    private var raw: [UInt8] = []
    /// Everything printed, and when: what is drawn.
    private var printed: [(ms: Int, text: String)] = []
    /// The start of a character split across two reads, kept for the next.
    private var partial: [UInt8] = []
    private var ended = false

    /// Starts zsh in `folder`, `columns` by `rows`, on `channel` (`REEL_CHANNEL`), so a reel run in it talks to this
    /// one.
    init(columns: Int, rows: Int, folder: URL, channel: URL? = nil) throws {
        home = FileManager.default.temporaryDirectory.appending(path: "reel-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Self.zshrc.write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw ReelError("the terminal's folder \(folder.path) is not there")
        }

        let inherited = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": home.path, "ZDOTDIR": home.path, "TERM": "xterm-256color", "COLORTERM": "truecolor",
            "CLICOLOR": "1", "LANG": inherited["LANG"] ?? "en_US.UTF-8", "PATH": inherited["PATH"] ?? "/usr/bin:/bin",
            "USER": inherited["USER"] ?? "reel", "LOGNAME": inherited["USER"] ?? "reel", "SHELL": "/bin/zsh",
            "TMPDIR": inherited["TMPDIR"] ?? "/tmp", "PWD": folder.path,
        ]
        if let channel { environment[Channel.variable] = channel.path }
        // Everything the child needs, made before forking: after it, the child may only exec.
        let words: [String] = ["zsh", "-d", "-i"]
        let arguments: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
        let pairs: [String] = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let variables: [UnsafeMutablePointer<CChar>?] = pairs.map { strdup($0) } + [nil]
        let directory = strdup(folder.path)
        let shell = strdup("/bin/zsh")
        defer {
            (arguments + variables).forEach { free($0) }
            free(directory)
            free(shell)
        }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        var fd: Int32 = -1
        let child = forkpty(&fd, nil, nil, &size)
        if child == 0 {
            chdir(directory)
            execve(shell, arguments, variables)
            _exit(127)
        }
        guard child > 0 else { throw ReelError("cannot start a shell: \(String(cString: strerror(errno)))") }
        pid = child
        pty = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "reel.terminal"))
        source.setEventHandler { [weak self] in self?.read() }
        source.resume()
        self.source = source
    }

    deinit {
        close()
    }

    private func read() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(pty, &buffer, buffer.count)
        guard count > 0 else {
            // The shell has gone (EIO from a pseudo-terminal whose other end closed).
            lock.withLock { ended = true }
            source?.cancel()
            return
        }
        let bytes = Array(buffer[0 ..< count])
        lock.withLock {
            raw += bytes
            lastOutput = .now
            let whole = partial + bytes
            let cut = Self.completeLength(whole)
            partial = Array(whole[cut...])
            let text = String(decoding: whole[..<cut], as: UTF8.self)
            if !text.isEmpty { printed.append((milliseconds(since: start), text)) }
        }
    }

    /// How much of `bytes` is whole characters: an incomplete one at the end waits for the next read.
    static func completeLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count
        // Back over continuation bytes to the last lead byte, at most three.
        while index > 0, bytes.count - index < 3, bytes[index - 1] & 0xC0 == 0x80 {
            index -= 1
        }
        guard index > 0 else { return bytes.count }
        let lead = bytes[index - 1]
        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        return bytes.count - (index - 1) >= length ? bytes.count : index - 1
    }

    private func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        Recorder.milliseconds(ContinuousClock.now - instant)
    }

    /// Milliseconds since the take started.
    var now: Int {
        lock.withLock { milliseconds(since: start) }
    }

    /// Starts the take's clock: what the shell printed before (its first prompt) shows from the first frame.
    func startClock() {
        lock.withLock {
            start = .now
            printed = printed.map { (0, $0.text) }
        }
    }

    /// How much has been printed: a place to wait from.
    var mark: Int {
        lock.withLock { raw.count }
    }

    /// What the shell printed since `mark`, as text without its colours and cursor moves.
    func text(since mark: Int) -> String {
        let bytes = lock.withLock { Array(raw[min(mark, raw.count)...]) }
        return Self.plain(String(decoding: bytes, as: UTF8.self))
    }

    /// Whether a command has ended since `mark`: its end mark was printed.
    func exited(since mark: Int) -> Bool {
        let bytes = lock.withLock { Array(raw[min(mark, raw.count)...]) }
        return bytes.count >= Self.exitMark.count
            && (0 ... bytes.count - Self.exitMark.count)
            .contains { bytes[$0 ..< $0 + Self.exitMark.count].elementsEqual(Self.exitMark) }
    }

    /// How long since the shell last printed anything.
    var quiet: Duration {
        lock.withLock { ContinuousClock.now - lastOutput }
    }

    var hasEnded: Bool {
        lock.withLock { ended }
    }

    /// Everything printed so far, and when.
    var output: [(ms: Int, text: String)] {
        lock.withLock { printed }
    }

    func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        let written = bytes.withUnsafeBytes { Darwin.write(pty, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw ReelError("the shell is not taking input any more") }
    }

    /// Ends the shell and everything it started, and removes its home.
    func close() {
        guard source != nil else { return }
        source?.cancel()
        source = nil
        kill(pid, SIGHUP)
        Darwin.close(pty)
        var status: Int32 = 0
        // Reaped if it has gone; one that ignores the hang-up is killed.
        if waitpid(pid, &status, WNOHANG) == 0 {
            usleep(100_000)
            if waitpid(pid, &status, WNOHANG) == 0 {
                kill(pid, SIGKILL)
                waitpid(pid, &status, 0)
            }
        }
        try? FileManager.default.removeItem(at: home)
    }

    /// `text` without escape sequences (colours, cursor moves, titles, marks) and carriage returns.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1b}\\[[0-?]*[ -/]*[@-~]|\u{1b}\\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\\\)|\u{1b}[@-Z\\\\-_]|\r",
            with: "", options: .regularExpression
        )
    }
}
