#if canImport(Combine) && canImport(AVFoundation) && canImport(Speech)
import Foundation
import Combine
import AVFoundation
import Speech

/// An observable wrapper around `SFSpeechRecognizer` that streams live transcriptions
/// using `AVAudioEngine` and publishes partial and final results.
@MainActor
public final class SpeechRecognizerService: ObservableObject {
    /// Errors emitted by ``SpeechRecognizerService``.
    public enum ServiceError: LocalizedError {
        case speechUnavailable
        case unsupportedLocale(String)
        case speechAuthorizationDenied(SFSpeechRecognizerAuthorizationStatus)
        case microphonePermissionDenied
        case audioSessionUnavailable
        case recognitionFailed(Error)
        case timeout
        case cancelled
        case unknown(Error)

        public var errorDescription: String? {
            switch self {
            case .speechUnavailable:
                return "Speech recognition is currently unavailable."
            case .unsupportedLocale(let identifier):
                return "Speech recognition is not supported for locale \(identifier)."
            case .speechAuthorizationDenied:
                return "Speech recognition permission was denied."
            case .microphonePermissionDenied:
                return "Microphone access is required for speech recognition."
            case .audioSessionUnavailable:
                return "The audio session could not be configured for recording."
            case .recognitionFailed(let error):
                return "Speech recognition failed: \(error.localizedDescription)."
            case .timeout:
                return "Speech recognition timed out."
            case .cancelled:
                return "Speech recognition was cancelled."
            case .unknown(let error):
                return "An unknown error occurred: \(error.localizedDescription)."
            }
        }
    }

    /// The latest transcription string, updated with partial and final recognition results.
    @Published public private(set) var transcript: String = ""
    /// Indicates whether audio capture and speech recognition are currently running.
    @Published public private(set) var isRunning: Bool = false
    /// The most recent error emitted by the service, including cancellation events.
    @Published public private(set) var lastError: ServiceError?
    /// The locale identifier currently used for recognition, if any.
    @Published public private(set) var localeIdentifier: String?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutWorkItem: DispatchWorkItem?
    private var startTask: Task<Void, Never>?
    private var suppressedCancellationTaskIDs: Set<ObjectIdentifier> = []
    private var isAudioTapInstalled = false

    public let timeoutInterval: TimeInterval

    /// Creates a new speech recognizer service.
    /// - Parameter timeoutInterval: The duration, in seconds, to wait for recognition
    ///   updates before emitting a timeout error. Pass `0` to disable timeout handling.
    public init(timeoutInterval: TimeInterval = 10) {
        self.timeoutInterval = timeoutInterval
    }

    deinit {
        startTask?.cancel()
        timeoutWorkItem?.cancel()
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine.stop()
        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Begins streaming recognition for the supplied locale.
    /// - Parameter identifier: A BCP 47 locale identifier (for example `"en-US"` or `"de-DE"`).
    public func start(locale identifier: String) {
        startTask?.cancel()
        startTask = Task { [weak self] in
            await self?.performStart(locale: identifier)
        }
    }

    /// Stops the current recognition session and cancels any pending authorization requests.
    public func stop() {
        startTask?.cancel()
        startTask = nil
        guard isRunning || recognitionTask != nil else {
            stopInternal()
            lastError = nil
            return
        }

        stopInternal(suppressCancellationError: true)
        lastError = nil
    }

    @MainActor
    private func performStart(locale identifier: String) async {
        defer { startTask = nil }
        guard !Task.isCancelled else { return }

        stopInternal(suppressCancellationError: recognitionTask != nil)
        transcript = ""
        localeIdentifier = nil
        lastError = nil

        do {
            try await ensurePermissions()
            guard !Task.isCancelled else { return }
            try configureRecognizer(with: identifier)
            guard !Task.isCancelled else { return }
            try startRecording()
            isRunning = true
            localeIdentifier = identifier
        } catch let error as ServiceError {
            handleError(error)
        } catch {
            handleError(.unknown(error))
        }
    }

    private func ensurePermissions() async throws {
        try await ensureSpeechAuthorization()
        try await ensureMicrophonePermission()
        try configureAudioSession()
    }

    private func ensureSpeechAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let newStatus = await requestSpeechAuthorization()
            guard newStatus == .authorized else {
                throw ServiceError.speechAuthorizationDenied(newStatus)
            }
        case .denied, .restricted:
            throw ServiceError.speechAuthorizationDenied(status)
        @unknown default:
            throw ServiceError.speechAuthorizationDenied(status)
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func ensureMicrophonePermission() async throws {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return
        case .denied:
            throw ServiceError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }

            guard granted else {
                throw ServiceError.microphonePermissionDenied
            }
        @unknown default:
            throw ServiceError.microphonePermissionDenied
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw ServiceError.audioSessionUnavailable
        }
    }

    private func configureRecognizer(with identifier: String) throws {
        let locale = Locale(identifier: identifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ServiceError.unsupportedLocale(identifier)
        }

        guard recognizer.isAvailable else {
            throw ServiceError.speechUnavailable
        }

        speechRecognizer = recognizer
    }

    private func startRecording() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        guard let speechRecognizer else {
            throw ServiceError.speechUnavailable
        }

        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        if isAudioTapInstalled {
            node.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
        }
        isAudioTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw ServiceError.audioSessionUnavailable
        }

        let task = speechRecognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            guard let self else { return }
            let taskIdentifier = ObjectIdentifier(task)
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetTimeout()
                    if result.isFinal {
                        self.stopInternal(suppressCancellationError: true)
                    }
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == SFSpeechRecognizerErrorDomain,
                       nsError.code == SFSpeechErrorCode.canceled.rawValue,
                       self.suppressedCancellationTaskIDs.remove(taskIdentifier) != nil {
                        return
                    }

                    self.suppressedCancellationTaskIDs.remove(taskIdentifier)
                    if nsError.domain == SFSpeechRecognizerErrorDomain,
                       nsError.code == SFSpeechErrorCode.canceled.rawValue {
                        self.handleError(.cancelled)
                    } else {
                        self.handleError(.recognitionFailed(error))
                    }
                }
            }
        })
        recognitionTask = task

        resetTimeout()
    }

    private func stopInternal(suppressCancellationError: Bool = false) {
        if suppressCancellationError, let recognitionTask {
            suppressedCancellationTaskIDs.insert(ObjectIdentifier(recognitionTask))
        }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        isRunning = false
        localeIdentifier = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Swallow audio session deactivation errors to avoid crashing debug builds.
        }
    }

    private func handleError(_ error: ServiceError) {
        lastError = error
        stopInternal(suppressCancellationError: true)
    }

    private func resetTimeout() {
        timeoutWorkItem?.cancel()
        guard timeoutInterval > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleError(.timeout)
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval, execute: workItem)
    }
}

#endif
