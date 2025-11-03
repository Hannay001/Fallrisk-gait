#if canImport(Combine)
import Foundation
import Combine

/// A WebSocket client that connects to the language tutor back-end and exchanges
/// JSON encoded messages describing automatic speech recognition (ASR) updates
/// and tutor responses.
@MainActor
public final class TutorSocket: NSObject, ObservableObject {
    /// The operating mode for the socket.
    public enum Mode: Equatable {
        /// Connect to the live back-end when available, falling back to the demo
        /// simulator when the network is unavailable.
        case automatic
        /// Always run in demo mode without establishing a network connection.
        case demo
    }

    /// High level connection states surfaced to the UI.
    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(delay: TimeInterval)
        case demo
        case failed(String)

        public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.demo, .demo):
                return true
            case let (.reconnecting(lhsDelay), .reconnecting(rhsDelay)):
                return abs(lhsDelay - rhsDelay) < 0.001
            case let (.failed(lhsMessage), .failed(rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }

    /// Errors that can be emitted by ``TutorSocket``.
    public enum SocketError: LocalizedError, Equatable {
        case invalidEnvironment
        case encodingFailed
        case decodingFailed
        case server(String)
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .invalidEnvironment:
                return "Tutor socket environment is not configured."
            case .encodingFailed:
                return "Failed to encode the outbound message."
            case .decodingFailed:
                return "Failed to decode the tutor response."
            case .server(let message):
                return message
            case .transport(let message):
                return message
            }
        }
    }

    /// Outbound message sent to the tutor server.
    public struct ClientMessage: Codable, Equatable {
        public enum MessageType: String, Codable {
            case asr
        }

        public let type: MessageType
        public let text: String
        public let lang: String
        public let level: String

        public init(text: String, languageCode: String, level: String, type: MessageType = .asr) {
            self.type = type
            self.text = text
            self.lang = languageCode
            self.level = level
        }
    }

    /// Typed representation of the tutor's reply payload.
    public struct TutorReply: Codable, Equatable {
        public enum MessageType: String, Codable {
            case tutor
        }

        public let type: MessageType
        public let reply: String
        public let hint: String?
        public let errors: [String]
        public let cefr: String?
        public let receivedAt: Date

        public init(reply: String, hint: String?, errors: [String], cefr: String?, receivedAt: Date = Date()) {
            self.type = .tutor
            self.reply = reply
            self.hint = hint
            self.errors = errors
            self.cefr = cefr
            self.receivedAt = receivedAt
        }
    }

    private enum ServerMessageType: Equatable {
        case tutor
        case error
        case echo
        case ping
        case pong
        case unknown(String)
    }

    private struct ServerMessageEnvelope: Decodable {
        let type: ServerMessageType
        let reply: String?
        let hint: String?
        let errors: [String]?
        let cefr: String?
        let message: String?
        let reason: String?
        let payload: ClientMessage?
        let text: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case reply
            case hint
            case errors
            case cefr
            case message
            case reason
            case payload
            case text
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawType = (try? container.decode(String.self, forKey: .type)) ?? ""
            switch rawType {
            case "tutor":
                type = .tutor
            case "error":
                type = .error
            case "echo":
                type = .echo
            case "ping":
                type = .ping
            case "pong":
                type = .pong
            default:
                type = .unknown(rawType)
            }
            reply = try container.decodeIfPresent(String.self, forKey: .reply)
            hint = try container.decodeIfPresent(String.self, forKey: .hint)
            errors = try container.decodeIfPresent([String].self, forKey: .errors)
            cefr = try container.decodeIfPresent(String.self, forKey: .cefr)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            reason = try container.decodeIfPresent(String.self, forKey: .reason)
            payload = try container.decodeIfPresent(ClientMessage.self, forKey: .payload)
            text = try container.decodeIfPresent(String.self, forKey: .text)
        }
    }

    private let mode: Mode
    private let autoReconnect: Bool
    private let minimumBackoff: TimeInterval
    private let maximumBackoff: TimeInterval
    private let path: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let sessionConfiguration: URLSessionConfiguration
    private let requiredPathComponents: [String]

    private lazy var session: URLSession = {
        URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var sendStream: AsyncStream<ClientMessage>?
    private var sendContinuation: AsyncStream<ClientMessage>.Continuation?
    private var pendingMessages: [ClientMessage] = []
    private var isDemoFallbackActive: Bool = false

    private let providedURL: URL?
    private let environmentIdentifier: String?

    /// Published properties for UI binding.
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var lastReply: TutorReply?
    @Published public private(set) var lastError: SocketError?

    /// Closure invoked whenever a tutor reply is processed.
    public var onReply: ((TutorReply) -> Void)?

    /// Closure invoked for diagnostic logging.
    public var logger: ((String) -> Void)?

    public init(
        environment: String? = ProcessInfo.processInfo.environment["TUTOR_SOCKET_ENV"],
        url: URL? = {
            if let raw = ProcessInfo.processInfo.environment["TUTOR_SOCKET_URL"], let parsed = URL(string: raw) {
                return parsed
            }
            return nil
        }(),
        mode: Mode = .automatic,
        autoReconnect: Bool = true,
        minimumBackoff: TimeInterval = 1.0,
        maximumBackoff: TimeInterval = 30.0,
        path: String = "/realtime",
        sessionConfiguration: URLSessionConfiguration = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.environmentIdentifier = environment
        self.providedURL = url
        self.mode = mode
        self.autoReconnect = autoReconnect
        self.minimumBackoff = max(0.1, minimumBackoff)
        self.maximumBackoff = max(self.minimumBackoff, maximumBackoff)
        self.path = path
        self.sessionConfiguration = sessionConfiguration
        self.encoder = encoder
        self.decoder = decoder
        self.requiredPathComponents = path
            .split(separator: "/")
            .map { String($0) }
        super.init()
    }

    deinit {
        disconnect()
        session.invalidateAndCancel()
    }

    /// Connects to the tutor back-end if not already connected.
    public func connect() {
        reconnectTask?.cancel()

        guard mode != .demo else {
            isDemoFallbackActive = true
            connectionState = .demo
            return
        }

        guard webSocketTask == nil else { return }
        guard let endpoint = resolveEndpoint() else {
            connectionState = .failed(SocketError.invalidEnvironment.errorDescription ?? "Invalid environment")
            lastError = .invalidEnvironment
            return
        }

        connectionState = .connecting
        logger?("Connecting to \(endpoint.absoluteString)")

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        startSendLoop(for: task)
        startReceiveLoop(for: task)
        task.resume()
    }

    /// Disconnects the socket and clears the current tasks.
    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendContinuation?.finish()
        sendContinuation = nil
        sendStream = nil
        pendingMessages.removeAll()

        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
        }
        webSocketTask = nil

        if mode == .demo || isDemoFallbackActive {
            connectionState = .demo
        } else {
            connectionState = .disconnected
        }
    }

    /// Sends a transcription update to the tutor back-end or demo simulator.
    public func send(text: String, languageCode: String, level: String) {
        let message = ClientMessage(text: text, languageCode: languageCode, level: level)
        guard !text.isEmpty else { return }

        if mode == .demo || isDemoFallbackActive {
            runDemoReply(for: message)
            return
        }

        if let continuation = sendContinuation {
            continuation.yield(message)
        } else {
            pendingMessages.append(message)
        }
    }

    private func resolveEndpoint() -> URL? {
        if let url = providedURL ?? environmentURLFromProcess() {
            return ensureRequiredPath(on: url)
        }

        guard let identifier = environmentIdentifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.lowercased().hasPrefix("ws") {
            return ensureRequiredPath(on: url)
        }

        var hostPart = trimmed
        var pathPart: String?
        if let slashRange = trimmed.firstIndex(of: "/") {
            hostPart = String(trimmed[..<slashRange])
            pathPart = String(trimmed[slashRange...])
        }

        let scheme: String
        if hostPart.contains("localhost") || hostPart.contains("127.0.0.1") || hostPart.contains("0.0.0.0") {
            scheme = "ws"
        } else {
            scheme = "wss"
        }

        var components = URLComponents()
        components.scheme = scheme

        if let colonRange = hostPart.firstIndex(of: ":") {
            let host = String(hostPart[..<colonRange])
            let portPart = String(hostPart[hostPart.index(after: colonRange)...])
            components.host = host
            components.port = Int(portPart)
        } else {
            components.host = hostPart
        }

        if let pathPart, !pathPart.isEmpty {
            components.percentEncodedPath = pathPart
        }

        guard let url = components.url else { return nil }
        return ensureRequiredPath(on: url)
    }

    private func environmentURLFromProcess() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["TUTOR_SOCKET_URL"], let url = URL(string: raw) {
            return url
        }
        return nil
    }

    private func ensureRequiredPath(on url: URL) -> URL? {
        guard !requiredPathComponents.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

        let existingSegments = components.path.split(separator: "/").map { String($0) }
        if existingSegments.isEmpty {
            components.percentEncodedPath = "/" + requiredPathComponents.joined(separator: "/")
            return components.url
        }

        if existingSegments.suffix(requiredPathComponents.count) == requiredPathComponents {
            return components.url
        }
        return components.url
    }

    private func startSendLoop(for task: URLSessionWebSocketTask) {
        let (stream, continuation) = AsyncStream<ClientMessage>.makeStream()
        sendStream = stream
        sendContinuation = continuation

        if !pendingMessages.isEmpty {
            for item in pendingMessages {
                continuation.yield(item)
            }
            pendingMessages.removeAll()
        }

        sendTask = Task { [weak self] in
            guard let self else { return }
            for await message in stream {
                do {
                    let payload = try self.encoder.encode(message)
                    if let stringValue = String(data: payload, encoding: .utf8) {
                        try await task.send(.string(stringValue))
                    } else {
                        try await task.send(.data(payload))
                    }
                } catch is EncodingError {
                    lastError = .encodingFailed
                    logger?("Encoding error while sending message")
                    break
                } catch {
                    await self.handleTransportFailure(error)
                    break
                }
            }
        }
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        await self.handleIncomingData(data)
                    case .string(let string):
                        guard let data = string.data(using: .utf8) else { continue }
                        await self.handleIncomingData(data)
                    @unknown default:
                        continue
                    }
                } catch {
                    await self.handleTransportFailure(error)
                    break
                }
            }
        }
    }

    private func handleIncomingData(_ data: Data) async {
        do {
            let envelope = try decoder.decode(ServerMessageEnvelope.self, from: data)
            switch envelope.type {
            case .tutor:
                guard let replyText = envelope.reply else {
                    lastError = .decodingFailed
                    return
                }
                let reply = TutorReply(reply: replyText,
                                       hint: envelope.hint,
                                       errors: envelope.errors ?? [],
                                       cefr: envelope.cefr,
                                       receivedAt: Date())
                lastReply = reply
                onReply?(reply)
            case .echo:
                if let payload = envelope.payload {
                    runDemoReply(for: payload, simulated: false)
                } else if let text = envelope.text {
                    let reply = TutorReply(reply: text,
                                           hint: envelope.hint,
                                           errors: envelope.errors ?? [],
                                           cefr: envelope.cefr,
                                           receivedAt: Date())
                    lastReply = reply
                    onReply?(reply)
                }
            case .error:
                let message = envelope.message ?? envelope.reason ?? "Unknown server error"
                let error = SocketError.server(message)
                lastError = error
            case .ping:
                webSocketTask?.sendPing { [weak self] pingError in
                    if let pingError {
                        Task { await self?.handleTransportFailure(pingError) }
                    }
                }
            case .pong, .unknown:
                break
            }
        } catch {
            lastError = .decodingFailed
            logger?("Decoding error: \(error.localizedDescription)")
        }
    }

    private func handleTransportFailure(_ error: Error) async {
        guard !Task.isCancelled else { return }
        logger?("Transport failure: \(error.localizedDescription)")

        if shouldEnterDemoMode(for: error) {
            enterDemoMode()
            return
        }

        lastError = .transport(error.localizedDescription)
        tearDownSocket()
        scheduleReconnect()
    }

    private func tearDownSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendContinuation?.finish()
        sendContinuation = nil
        sendStream = nil
        webSocketTask = nil
    }

    private func scheduleReconnect(updateState: Bool = true) {
        guard autoReconnect, mode != .demo else { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1

        let exponential = minimumBackoff * pow(2.0, Double(reconnectAttempt - 1))
        let capped = min(maximumBackoff, exponential)
        let jitterFactor = 1.0 + Double.random(in: -0.25...0.25)
        let delay = max(minimumBackoff, capped * jitterFactor)

        if updateState {
            connectionState = .reconnecting(delay: delay)
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.performReconnect()
        }
    }

    private func performReconnect() async {
        guard mode != .demo else { return }
        webSocketTask = nil
        connect()
    }

    private func shouldEnterDemoMode(for error: Error) -> Bool {
        guard mode == .automatic else { return false }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .timedOut:
            return true
        default:
            return false
        }
    }

    private func enterDemoMode() {
        tearDownSocket()
        isDemoFallbackActive = true
        connectionState = .demo
        reconnectAttempt = 0
        scheduleReconnect(updateState: false)
    }

    private func runDemoReply(for message: ClientMessage, simulated: Bool = true) {
        let sanitized = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cefr = message.level
        let replyText: String
        let hint: String?
        let errors: [String]

        if sanitized.isEmpty {
            replyText = "Bitte sag etwas, damit ich helfen kann."
            hint = message.lang.hasPrefix("de") ? "Nutze einfache Begrüßungen wie 'Guten Tag'." : "Try saying a short greeting."
            errors = ["No speech detected"]
        } else {
            replyText = "«\(sanitized)» klingt gut! Versuche, einen längeren Satz auf Niveau \(cefr)."
            hint = message.lang.hasPrefix("de") ? "Achte auf die Verbposition im Satz." : "Focus on forming complete sentences."
            errors = sanitized.count < 6 ? ["Versuche, einen vollständigen Satz zu bilden."] : []
        }

        let reply = TutorReply(reply: replyText,
                               hint: hint,
                               errors: errors,
                               cefr: cefr,
                               receivedAt: Date())

        let delayNanoseconds = UInt64((simulated ? Double.random(in: 0.35...0.8) : 0.05) * 1_000_000_000)
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await MainActor.run {
                guard let self else { return }
                self.lastReply = reply
                self.onReply?(reply)
            }
        }
    }
}

extension TutorSocket: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        reconnectAttempt = 0
        isDemoFallbackActive = false
        connectionState = .connected
        lastError = nil
        logger?("WebSocket opened")
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger?("WebSocket closed with code \(closeCode.rawValue)")
        tearDownSocket()
        if mode == .demo || isDemoFallbackActive {
            connectionState = .demo
        } else if closeCode == .normalClosure {
            connectionState = .disconnected
        } else {
            scheduleReconnect()
        }
    }
}

private extension AsyncStream {
    static func makeStream(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) -> (AsyncStream<Element>, AsyncStream<Element>.Continuation) {
        var continuation: AsyncStream<Element>.Continuation!
        let stream = AsyncStream<Element>(bufferingPolicy: bufferingPolicy) { continuation = $0 }
        return (stream, continuation)
    }
}

#endif
