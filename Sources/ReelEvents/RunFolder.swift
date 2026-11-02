import Foundation

/// Every run in the runs folder, read as it grows: each file from where it was last read, a line only once it is
/// whole. `read()` is cheap enough to call a few times a second.
public final class RunFolder {
    public let folder: URL
    /// How many finished runs are kept, the latest.
    public let keep: Int
    public private(set) var runs: [Int32: RunState] = [:]
    private var offsets: [Int32: UInt64] = [:]
    private var partial: [Int32: Data] = [:]
    private let alive: (Int32) -> Bool

    public init(folder: URL = Runs.folder, keep: Int = 5, alive: @escaping (Int32) -> Bool = Runs.isAlive) {
        self.folder = folder
        self.keep = keep
        self.alive = alive
    }

    /// The runs going on, then the finished ones, latest first.
    public var ordered: [RunState] {
        runs.values.sorted { a, b in
            let (doneA, doneB) = (a.ok != nil || a.gone, b.ok != nil || b.gone)
            if doneA != doneB { return !doneA }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Reads what was added since the last time. True when anything changed.
    @discardableResult
    public func read() -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var changed = false
        var present = Set<Int32>()
        for file in files {
            guard let pid = Runs.pid(of: file) else { continue }
            present.insert(pid)
            changed = readNew(of: file, pid: pid) || changed
        }
        for pid in runs.keys where !present.contains(pid) {
            runs[pid] = nil
            offsets[pid] = nil
            partial[pid] = nil
            changed = true
        }
        for (pid, run) in runs where run.ok == nil && !run.gone && !alive(pid) {
            runs[pid]?.gone = true
            changed = true
        }
        let finished = runs.values.filter { $0.ok != nil || $0.gone }.sorted { $0.updatedAt > $1.updatedAt }
        for run in finished.dropFirst(keep) {
            runs[run.pid] = nil
            changed = true
        }
        return changed
    }

    private func readNew(of file: URL, pid: Int32) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[pid] ?? 0
        // Made again under the same pid: a new run.
        if size < offset {
            offset = 0
            runs[pid] = nil
            partial[pid] = nil
        }
        guard size > offset else { return false }
        try? handle.seek(toOffset: offset)
        var data = partial[pid] ?? Data()
        data.append((try? handle.readToEnd()) ?? Data())
        offsets[pid] = size
        // Only whole lines: the rest waits for its newline.
        let end = data.lastIndex(of: 0x0A).map { data.index(after: $0) } ?? data.startIndex
        partial[pid] = Data(data[end...])
        let events = RunEvent.lines(Data(data[..<end]))
        guard !events.isEmpty else { return false }
        var run = runs[pid] ?? RunState(pid: pid)
        for event in events {
            run.apply(event)
        }
        runs[pid] = run
        return true
    }
}
