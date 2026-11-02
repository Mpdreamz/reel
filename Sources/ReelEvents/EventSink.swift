import Foundation

/// Where a run's events go.
public protocol EventSink: Sendable {
    func emit(_ event: RunEvent)
}

/// Appends each event to a file as a line of JSON: one `write` with `O_APPEND`, which the file system keeps whole, so
/// several writers (tracks recorded at once) never tear a line, and a reader never sees half of one but the last.
public struct FileSink: EventSink {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func emit(_ event: RunEvent) {
        let data = event.line
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}

/// Every sink in turn.
public struct Sinks: EventSink {
    public var all: [any EventSink]

    public init(_ all: [any EventSink]) {
        self.all = all
    }

    public func emit(_ event: RunEvent) {
        for sink in all {
            sink.emit(event)
        }
    }
}

/// The folder every run of reel writes its events to, one file each, `<pid>.jsonl`, for the companion app to find:
/// made when the run starts and removed when it ends. A run that crashed leaves its file; its pid is no longer alive.
public enum Runs {
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/reel/runs", directoryHint: .isDirectory)
    }

    public static func file(for pid: Int32, in folder: URL = folder) -> URL {
        folder.appending(path: "\(pid).jsonl")
    }

    /// The pid a run's file is named for.
    public static func pid(of file: URL) -> Int32? {
        guard file.pathExtension == "jsonl" else { return nil }
        return Int32(file.deletingPathExtension().lastPathComponent)
    }

    /// Whether `pid` is a running process.
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Milliseconds since 1970.
    public static var now: Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
