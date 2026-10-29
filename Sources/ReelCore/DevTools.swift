import Foundation

/// A connection to a browser over the Chrome DevTools Protocol: commands sent as JSON over a WebSocket, each answered
/// by its id. Events are not listened to; reel asks the page instead.
final class DevTools: @unchecked Sendable {
    /// How long a command may take before reel gives up on it.
    static let timeout: TimeInterval = 15

    private let socket: URLSessionWebSocketTask
    private let lock = NSLock()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    init(_ url: URL) {
        socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 64 << 20
        socket.resume()
        listen()
    }

    /// Sends `method` and waits for its result.
    @discardableResult
    func send(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        let id = lock.withLock {
            nextID += 1
            return nextID
        }
        let message = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let data: Data = try await withCheckedThrowingContinuation { done in
            lock.withLock { pending[id] = done }
            socket.send(.string(String(decoding: message, as: UTF8.self))) { [weak self] error in
                if let error { self?.finish(
                    id,
                    with: .failure(ReelError("DevTools \(method): \(error.localizedDescription)"))
                ) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                self?.finish(
                    id,
                    with: .failure(ReelError("DevTools \(method) had no answer in \(Int(Self.timeout)) s"))
                )
            }
        }
        return try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Evaluates JavaScript in the page and returns its value (awaiting a promise).
    func evaluate(_ expression: String) async throws -> Any? {
        let result = try await send("Runtime.evaluate", [
            "expression": expression, "returnByValue": true, "awaitPromise": true,
        ])
        if let thrown = result["exceptionDetails"] as? [String: Any] {
            let text = ((thrown["exception"] as? [String: Any])?["description"] as? String) ?? "\(thrown["text"] ?? "")"
            throw ReelError("the page threw: \(text)")
        }
        let value = (result["result"] as? [String: Any])?["value"]
        return value is NSNull ? nil : value
    }

    func close() {
        socket.cancel(with: .goingAway, reason: nil)
    }

    private func listen() {
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                let data: Data? = switch message {
                case let .string(text): Data(text.utf8)
                case let .data(data): data
                @unknown default: nil
                }
                if let data { handle(data) }
                listen()
            case let .failure(error):
                let waiting = lock.withLock {
                    defer { pending = [:] }
                    return pending
                }
                for done in waiting.values {
                    done.resume(throwing: ReelError("the browser went away (\(error.localizedDescription))"))
                }
            }
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int
        else { return }
        if let error = object["error"] as? [String: Any] {
            finish(id, with: .failure(ReelError("DevTools: \(error["message"] ?? error)")))
        } else {
            let result = (try? JSONSerialization.data(withJSONObject: object["result"] ?? [String: Any]())) ?? Data()
            finish(id, with: .success(result))
        }
    }

    private func finish(_ id: Int, with result: Result<Data, Error>) {
        let done = lock.withLock { pending.removeValue(forKey: id) }
        done?.resume(with: result)
    }
}
