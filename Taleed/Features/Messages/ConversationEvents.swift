import Foundation
import TaleedAPI

// Live updates of a conversation (slice C, Live updates): one server-sent events connection to
// `GET /conversations/{id}/events` while the screen is on. The generated `streamConversationEvents`
// waits for the stream to end (30 minutes), so this reader is used instead.

/// What the live stream of a conversation delivers.
enum ConversationEvent: Equatable, Sendable {
    /// A connection opened (the first one, or after a drop): sends that failed can go again.
    case connected
    /// A new message: the other member's, the member's own from another device, or an automatic one.
    /// It can repeat one the screen has: merge by id.
    case message(ChatMessage)
}

/// The live stream of a conversation, from the newest message the screen has. Reconnects by itself
/// after a drop or the 30-minute limit; ends with an `ApiError` when the API refuses it for good
/// (`401`, `403`, `404`). Ending the iteration closes the connection.
@MainActor
protocol ConversationEventsSource: AnyObject {
    func events(conversationId: String, after newestMessageId: String?) -> AsyncThrowingStream<ConversationEvent, Error>
}

/// One server-sent event.
struct ServerEvent: Sendable, Equatable {
    var id: String?
    var event: String
    var data: String
}

/// Cuts the bytes of a server-sent events stream into events as they arrive (the slice's reader).
/// Comment lines (`: ping` heartbeats) are skipped; `retry:` sets the wait before reconnecting.
struct ServerEventParser {
    private var line: [UInt8] = []
    private var id: String?
    private var event = "message"
    private var data: [String] = []
    /// The last `retry:` the server sent, in milliseconds.
    private(set) var retryMilliseconds: Int?

    mutating func feed(_ bytes: Data) -> [ServerEvent] {
        var events: [ServerEvent] = []
        for byte in bytes {
            guard byte == UInt8(ascii: "\n") else {
                line.append(byte)
                continue
            }
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            let text = String(bytes: line, encoding: .utf8) ?? ""
            line.removeAll(keepingCapacity: true)
            if let event = handle(text) { events.append(event) }
        }
        return events
    }

    /// One line: a blank line ends the event in progress; a comment (`: ping`) is skipped.
    private mutating func handle(_ text: String) -> ServerEvent? {
        if text.isEmpty {
            defer {
                event = "message"
                data = []
            }
            return data.isEmpty ? nil : ServerEvent(id: id, event: event, data: data.joined(separator: "\n"))
        }
        guard !text.hasPrefix(":") else { return nil }
        let field = text.prefix { $0 != ":" }
        var value = text.dropFirst(field.count + 1)
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "id": id = String(value)
        case "event": event = String(value)
        case "data": data.append(String(value))
        case "retry": retryMilliseconds = Int(value) ?? retryMilliseconds
        default: break
        }
        return nil
    }
}

/// The stream answered something other than `200`: its status and body, to read the error code.
struct StreamRefused: Error {
    let status: Int
    let body: Data
    let retryAfter: String?
}

/// One connection of an events stream. Ending the iteration closes it.
final class EventStreamConnection: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Item: Sendable {
        /// The stream answered `200`.
        case opened
        case event(ServerEvent)
        /// The server's `retry:`, in milliseconds.
        case retry(Int)
    }

    // Only used on the session's delegate queue, which runs one task at a time.
    private var parser = ServerEventParser()
    private var errorBody = Data()
    private let continuation: AsyncThrowingStream<Item, Error>.Continuation

    private init(_ continuation: AsyncThrowingStream<Item, Error>.Continuation) {
        self.continuation = continuation
    }

    static func open(_ request: URLRequest) -> AsyncThrowingStream<Item, Error> {
        AsyncThrowingStream { continuation in
            let configuration = URLSessionConfiguration.default
            // A heartbeat comes every 15 seconds: 45 without a byte means the connection is dead.
            configuration.timeoutIntervalForRequest = 45
            configuration.timeoutIntervalForResource = 60 * 60
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: EventStreamConnection(continuation),
                                     delegateQueue: queue)
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        if (response as? HTTPURLResponse)?.statusCode == 200 { continuation.yield(.opened) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard (dataTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            if errorBody.count < 16_384 { errorBody.append(data) }
            return
        }
        let retryBefore = parser.retryMilliseconds
        for event in parser.feed(data) { continuation.yield(.event(event)) }
        if let retry = parser.retryMilliseconds, retry != retryBefore { continuation.yield(.retry(retry)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let response = task.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        if let error {
            continuation.finish(throwing: error)
        } else if status != 200 {
            continuation.finish(throwing: StreamRefused(status: status, body: errorBody,
                                                        retryAfter: response?.value(forHTTPHeaderField: "Retry-After")))
        } else {
            continuation.finish()
        }
    }
}

extension GeneratedTaleedApi: ConversationEventsSource {
    func events(conversationId: String, after newestMessageId: String?) -> AsyncThrowingStream<ConversationEvent, Error> {
        let session = self.session
        let caller = self.caller
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastEventId = newestMessageId
                // The server's `retry:` (3 s); longer after a 429.
                var retryDelay = Duration.seconds(3)
                while !Task.isCancelled {
                    let configuration = session.configuration
                    let sentToken = session.token
                    var wait = retryDelay
                    do {
                        let request = Self.eventsRequest(conversationId: conversationId, after: lastEventId,
                                                         configuration: configuration)
                        for try await item in EventStreamConnection.open(request) {
                            switch item {
                            case .opened:
                                continuation.yield(.connected)
                            case let .retry(milliseconds):
                                retryDelay = .milliseconds(max(1000, milliseconds))
                                wait = retryDelay
                            case let .event(event):
                                // Other event names can appear later: ignore them.
                                guard event.event == "message",
                                      let message = try? configuration.codableHelper.decode(Message.self, from: Data(event.data.utf8)).get()
                                else { continue }
                                lastEventId = message.id
                                continuation.yield(.message(ChatMessage(message)))
                            }
                        }
                    } catch let refused as StreamRefused {
                        let error = ApiError.from(status: refused.status, body: refused.body, retryAfterHeader: refused.retryAfter)
                        guard let delay = Self.reconnectDelay(after: error, usual: retryDelay) else {
                            // `401`, `403`, `404` and other refusals are final (slice C): handled like any
                            // other request, never reconnected.
                            caller.record(error, sentToken: sentToken)
                            continuation.finish(throwing: error)
                            return
                        }
                        wait = delay
                    } catch {
                        // A network drop, the 45-second silence or the 30-minute end: reconnect below.
                    }
                    try? await Task.sleep(for: wait)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The wait before connecting again after the stream refused: the usual `retry` after a 5xx, what a
    /// `429` asks (30 s when it does not say); nil for a final refusal (`401`, `403`, `404`, `400`).
    nonisolated static func reconnectDelay(after error: ApiError, usual: Duration) -> Duration? {
        switch error {
        case let .rateLimited(seconds): .seconds(max(seconds ?? 30, 3))
        case .server, .network: usual
        default: nil
        }
    }

    /// `GET /conversations/{id}/events` with the session's headers (`Authorization`, `Accept-Language`,
    /// the `X-App-*` ones) and `Last-Event-ID`, so that the stream starts after the newest message.
    nonisolated static func eventsRequest(conversationId: String, after lastEventId: String?,
                                          configuration: TaleedAPIAPIConfiguration) -> URLRequest {
        let base = URL(string: configuration.basePath) ?? URL(filePath: "/")
        var request = URLRequest(url: base.appending(path: "conversations").appending(path: conversationId).appending(path: "events"))
        for (name, value) in configuration.customHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let lastEventId { request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID") }
        request.timeoutInterval = 45
        return request
    }
}
