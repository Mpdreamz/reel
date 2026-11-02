import AppKit

/// The companion app, Reel Companion: it shows a run's progress in the menu bar, and an overlay on the window being
/// recorded. Reel opens it, without bringing it forward, before it looks at what is running, so the overlay is kept
/// out of the take from its first frame. `REEL_COMPANION=0` leaves it closed; not installed, nothing happens.
public enum Companion {
    public static let bundleID = "io.github.mpdreamz.reel.companion"
    public static let variable = "REEL_COMPANION"
    /// How long reel waits for it to start.
    static let timeout: Duration = .seconds(1)

    static func open(environment: [String: String] = ProcessInfo.processInfo.environment) async {
        guard environment[variable] != "0",
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let deadline = ContinuousClock.now + timeout
        while NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
              ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
