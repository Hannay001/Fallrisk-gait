#if canImport(Combine) && canImport(AVFoundation)
import Foundation
import Combine
import AVFoundation

/// A text-to-speech service backed by ``AVSpeechSynthesizer``.
@MainActor
public final class TTSService: NSObject, ObservableObject {
    private let synthesizer: AVSpeechSynthesizer

    /// Publishes whether the synthesizer is currently speaking an utterance.
    @Published public private(set) var isSpeaking: Bool = false

    /// The default speaking rate to use when none is supplied to ``speak(_:languageCode:rate:pitch:)``.
    @Published public var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            if rate < AVSpeechUtteranceMinimumSpeechRate {
                rate = AVSpeechUtteranceMinimumSpeechRate
            } else if rate > AVSpeechUtteranceMaximumSpeechRate {
                rate = AVSpeechUtteranceMaximumSpeechRate
            }
        }
    }

    /// The default pitch multiplier to use when none is supplied to ``speak(_:languageCode:rate:pitch:)``.
    @Published public var pitchMultiplier: Float = 1.0 {
        didSet {
            if pitchMultiplier < 0.5 {
                pitchMultiplier = 0.5
            } else if pitchMultiplier > 2.0 {
                pitchMultiplier = 2.0
            }
        }
    }

    /// When enabled, spoken utterances are slowed down to aid comprehension.
    @Published public var slowModeEnabled: Bool = false

    /// Multiplier applied to the effective speaking rate when ``slowModeEnabled`` is true.
    public var slowModeRateMultiplier: Float = 0.6 {
        didSet { slowModeRateMultiplier = max(0.1, min(slowModeRateMultiplier, 1.0)) }
    }

    public override init() {
        self.synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        rate = AVSpeechUtteranceDefaultSpeechRate
        pitchMultiplier = 1.0
    }

    deinit {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
    }

    /// Speaks ``text`` using the specified language code and optional overrides.
    /// - Parameters:
    ///   - text: The text to be spoken.
    ///   - languageCode: A BCP-47 language identifier (for example, `"en-US"`).
    ///   - rate: An optional speech rate. When omitted, ``rate`` is used.
    ///   - pitch: An optional pitch multiplier. When omitted, ``pitchMultiplier`` is used.
    public func speak(_ text: String, languageCode: String, rate: Float? = nil, pitch: Float? = nil) {
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(language: languageCode) {
            utterance.voice = voice
        }

        let providedRate = rate ?? self.rate
        let effectiveRate = slowModeEnabled
            ? max(AVSpeechUtteranceMinimumSpeechRate, providedRate * slowModeRateMultiplier)
            : providedRate
        utterance.rate = clamp(effectiveRate,
                               minimum: AVSpeechUtteranceMinimumSpeechRate,
                               maximum: AVSpeechUtteranceMaximumSpeechRate)

        let providedPitch = pitch ?? pitchMultiplier
        utterance.pitchMultiplier = clamp(providedPitch, minimum: 0.5, maximum: 2.0)

        synthesizer.speak(utterance)
    }

    /// Stops the current utterance, if any, without waiting for it to finish.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        return Swift.max(minimum, Swift.min(value, maximum))
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI controls for adjusting text-to-speech characteristics.
@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
public struct TTSControlsView: View {
    @ObservedObject private var service: TTSService

    private let rateRange = AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate

    public init(service: TTSService) {
        self.service = service
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Speaking Rate")
                    .font(.headline)
                Slider(value: Binding(get: {
                    Double(service.rate)
                }, set: { newValue in
                    service.rate = Float(newValue)
                }), in: Double(rateRange.lowerBound)...Double(rateRange.upperBound))
                Text(String(format: "%.2f", service.rate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Pitch")
                    .font(.headline)
                Slider(value: Binding(get: {
                    Double(service.pitchMultiplier)
                }, set: { newValue in
                    service.pitchMultiplier = Float(newValue)
                }), in: 0.5...2.0)
                Text(String(format: "%.2f", service.pitchMultiplier))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $service.slowModeEnabled.animation()) {
                Text("Slow Mode")
            }
            .toggleStyle(SwitchToggleStyle())
            Text("Slow mode reduces the speaking rate to support language learners.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
#endif

#endif
