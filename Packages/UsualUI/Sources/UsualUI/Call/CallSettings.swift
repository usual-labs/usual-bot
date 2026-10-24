import AVFoundation
import Speech

/// The call's engine, voice, speed and language, kept between calls (`@AppStorage` keys below).
enum CallSettings {
    /// `""` follows the agent's gateway setting (`voice.voice_chat_mode`), `apple` is on-device
    /// speech, `gpt-live` is OpenAI's full-duplex voice.
    static let engineKey = "callEngine"
    static let voiceKey = "callVoice"
    static let speedKey = "callSpeed"
    static let languageKey = "callLanguage"

    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    static var engine: String { UserDefaults.standard.string(forKey: engineKey) ?? "" }

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
}
