import Foundation

/// Where a path in a tape or a preset leads: relative to the file it is written in, from home with `~`, absolute
/// with `/`, or from the git root with `//`, so a shared preset need not count `../` from wherever it is imported.
struct Paths: Equatable, Sendable {
    /// The repository the tape is in; nil outside one.
    let root: URL?

    /// The nearest folder holding `.git` (a folder, or a file in a worktree), from `directory` up.
    static func gitRoot(from directory: URL) -> URL? {
        var folder = directory.standardizedFileURL.path
        while true {
            if FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(".git")) {
                return URL(fileURLWithPath: folder, isDirectory: true)
            }
            // `/`'s parent is itself; a URL's would be `/..`, and the search would never end.
            let parent = (folder as NSString).deletingLastPathComponent
            if parent == folder || parent.isEmpty { return nil }
            folder = parent
        }
    }

    /// `path` as a file URL, and a warning when it is relative and leads out of the git root: a tape that reaches
    /// outside its repository works only where the repository sits next to the same things.
    func resolve(_ path: String, against directory: URL, fail: (String) -> TapeError) throws
        -> (url: URL, warning: String?)
    {
        if path.hasPrefix("//") {
            guard let root else {
                throw fail("\(path) starts at the git root (//), but \(directory.path) is in no git repository")
            }
            return (root.appending(path: String(path.dropFirst(2))).standardizedFileURL, nil)
        }
        let url = ReelCore.resolve(path, against: directory)
        guard let root, !path.hasPrefix("/"), !path.hasPrefix("~") else { return (url, nil) }
        let inside = url.path == root.path || url.path.hasPrefix(root.path + "/")
        return (
            url,
            inside ? nil : "\(path) leads outside the git root \(root.path), so it works only where that sits next to the repository"
        )
    }
}
