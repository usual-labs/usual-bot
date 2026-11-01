import SwiftUI

struct VoiceSettings: View {
    @AppStorage(CallSettings.engineKey) private var engine = ""
    @AppStorage(CallSettings.voiceKey) private var voice = ""
    @AppStorage(CallSettings.speedKey) private var speed = 1.0
    @AppStorage(CallSettings.languageKey) private var language = ""

    var body: some View {
        Section {
            Picker("Call engine", selection: $engine) {
                Text("Automatic").tag("")
                Text("On-device").tag("apple")
                Text("GPT-Live").tag("gpt-live")
            }
        } header: {
            Text("Voice calls")
        } footer: {
            Text(
                "Automatic follows the agent’s gateway setting. GPT-Live requires an OpenAI key on your gateway; OpenAI bills the minutes. You can also change these choices inside a call."
            )
        }
        Section {
            Picker("Language", selection: $language) {
                Text("Follow System").tag("")
                ForEach(CallSettings.languages, id: \.identifier) { locale in
                    Text(CallSettings.name(of: locale)).tag(locale.identifier)
                }
            }
            Picker("Voice", selection: $voice) {
                Text("Best available").tag("")
                ForEach(CallSettings.voices(for: CallSettings.language), id: \.identifier) { voice in
                    Text(voice.name).tag(voice.identifier)
                }
            }
            Picker("Speaking speed", selection: $speed) {
                ForEach(CallSettings.speeds, id: \.self) { speed in
                    Text(speed.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(speed)
                }
            }
        } header: {
            Text("On-device speech")
        } footer: {
            Text("These choices are shared with the controls inside a call. GPT-Live’s voice is set on the gateway.")
        }
        .onChange(of: language) { voice = "" }
    }
}
