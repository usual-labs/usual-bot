import AVFoundation
import HermesKit
import Speech

/// The call's engine, voice, speed and language, kept between calls (`@AppStorage` keys below).
enum CallSettings {
    /// `""` follows the agent's gateway setting (`voice.voice_chat_mode`), `apple` is on-device
    /// speech, `gpt-live` is OpenAI's full-duplex voice, `gateway` is the Bot's own speech-to-text
    /// and text-to-speech on Hermes.
    static let engineKey = "callEngine"
    static let gateway = "gateway"
    static let voiceKey = "callVoice"
    static let speedKey = "callSpeed"
    static let languageKey = "callLanguage"

    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    static var engine: String { UserDefaults.standard.string(forKey: engineKey) ?? "" }

    /// Which engine a call runs on.
    enum Engine: Equatable {
        case onDevice, gptLive, gateway
        /// The chosen engine can't run here; the call says why instead of using another.
        case unavailable(String)
    }

    /// The engine for `choice`, given what the gateway said about GPT-Live (`nil`: no answer).
    /// Automatic follows `voice.voice_chat_mode` only to GPT-Live: Hermes's `chained` mode would
    /// be Gateway, but that sends your voice off the device and may cost money, so it's chosen,
    /// never automatic, as Gateway dictation is.
    static func resolve(choice: String, status: VoiceLiveStatus?) -> Engine {
        switch choice {
        case "apple": return .onDevice
        case gateway: return .gateway
        case "gpt-live":
            if status?.available == true { return .gptLive }
            return .unavailable(
                String(
                    localized:
                        "GPT-Live can't start: \(status?.reason ?? String(localized: "the gateway didn't answer")). Choose On-device in the call settings to talk anyway."
                ))
        default:
            return status?.mode == "gpt-live" && status?.available == true ? .gptLive : .onDevice
        }
    }

    /// The language you speak and are answered in: the one chosen, or the device's.
    static var language: Locale {
        let chosen = UserDefaults.standard.string(forKey: languageKey) ?? ""
        return chosen.isEmpty ? Locale.current : Locale(identifier: chosen)
    }

    static var speed: Double {
        let speed = UserDefaults.standard.double(forKey: speedKey)
        return speed > 0 ? speed : 1
    }

    /// Languages the speech recognizer knows, by name.
    static var languages: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { name(of: $0).localizedCompare(name(of: $1)) == .orderedAscending }
    }

    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Voices installed for `language`, best quality first.
    static func voices(for language: Locale) -> [AVSpeechSynthesisVoice] {
        let code = language.language.languageCode?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { Locale(identifier: $0.language).language.languageCode?.identifier == code }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// The chosen voice if it's installed for the language, else the best one.
    static var voice: AVSpeechSynthesisVoice? {
        let voices = voices(for: language)
        let chosen = UserDefaults.standard.string(forKey: voiceKey) ?? ""
        return voices.first { $0.identifier == chosen } ?? voices.first
            ?? AVSpeechSynthesisVoice(language: language.identifier(.bcp47))
    }

    /// `text` to be said in the chosen voice, at the chosen speed.
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceDefaultSpeechRate * Float(speed), AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }
}

/// Who turns your speech into text in the message box, kept on this device for every Bot.
enum DictationSettings {
    /// `""` is Apple's on-device recognizer; `gateway` is the Bot's own speech-to-text on Hermes.
    static let engineKey = "dictationEngine"
    static let gateway = "gateway"
}
