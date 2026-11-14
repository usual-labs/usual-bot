import SwiftUI

struct VoiceSettings: View {
    @AppStorage(CallSettings.engineKey) private var engine = ""
    @AppStorage(CallSettings.voiceKey) private var voice = ""
    @AppStorage(CallSettings.speedKey) private var speed = 1.0
    @AppStorage(CallSettings.languageKey) private var language = ""
    @AppStorage(DictationSettings.engineKey) private var dictation = ""

    var body: some View {
        Section {
            Picker("Speech to text", selection: $dictation) {
                Text("On-device").tag("")
                Text("Gateway").tag(DictationSettings.gateway)
            }
            .clickable()
        } header: {
            Text("Dictation")
        } footer: {
            Text(
                dictation == DictationSettings.gateway
                    ? "Your voice goes to the Bot’s gateway, which sends it to whatever speech-to-text it’s set up with. That may be a paid service. Words appear as you speak if the gateway can stream them, otherwise when you stop."
                    : "Your voice stays on this device, and dictation works offline."
            )
        }
        Section {
            Picker("Call engine", selection: $engine) {
                Text("Automatic").tag("")
                Text("On-device").tag("apple")
                Text("GPT-Live").tag("gpt-live")
            }
            .clickable()
        } header: {
            Text("Voice calls")
        } footer: {
            Text(
                "Automatic follows the Bot’s gateway setting. GPT-Live requires an OpenAI key on your gateway; OpenAI bills the minutes. You can also change these choices inside a call."
            )
        }
        Section {
            Picker("Language", selection: $language) {
                Text("Follow System").tag("")
                ForEach(CallSettings.languages, id: \.identifier) { locale in
                    Text(CallSettings.name(of: locale)).tag(locale.identifier)
                }
            }
            .clickable()
            Picker("Voice", selection: $voice) {
                Text("Best available").tag("")
                ForEach(CallSettings.voices(for: CallSettings.language), id: \.identifier) { voice in
                    Text(voice.name).tag(voice.identifier)
                }
            }
            .clickable()
            Picker("Speaking speed", selection: $speed) {
                ForEach(CallSettings.speeds, id: \.self) { speed in
                    Text(speed.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(speed)
                }
            }
            .clickable()
        } header: {
            Text("On-device speech")
        } footer: {
            Text("These choices are shared with the controls inside a call. GPT-Live’s voice is set on the gateway.")
        }
        .onChange(of: language) { voice = "" }
    }
}
