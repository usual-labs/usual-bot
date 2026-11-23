import Foundation

/// A `::preview{file="…"}` line: Hermes's inline widget, an HTML file the agent wrote that runs
/// live in its message. Hermes's desktop app (`inline-preview-directive.tsx`) is the reference;
/// the "desktop" platform hint in Hermes's `prompt_builder.py` is what agents are told to write.
public struct WidgetDirective: Equatable, Sendable {
    /// As written: absolute, or relative to the profile's workspace.
    public let file: String
    /// The `height` attribute: only where the frame starts, before the page measures itself.
    public let height: Int?

    public init(file: String, height: Int? = nil) {
        self.file = file
        self.height = height
    }

    /// Whether the file is a page to run, not something to show as a file.
    public var isPage: Bool {
        ["html", "htm", "xhtml"].contains((file as NSString).pathExtension.lowercased())
    }

    /// The directive on `line`, which holds nothing else; `nil` for any other line.
    public static func parse(_ line: some StringProtocol) -> WidgetDirective? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix(opening), line.hasSuffix("}") else { return nil }
        let attributes = Self.attributes(line.dropFirst(opening.count).dropLast())
        guard let file = attributes["file"], !file.isEmpty else { return nil }
        return WidgetDirective(file: file, height: attributes["height"].flatMap { Int($0) })
    }

    /// Whether `line` is a directive, or the start of one a gateway preview cut short.
    public static func starts(_ line: some StringProtocol) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(opening)
    }

    /// Plain text's stand-in for a message that is only a widget.
    public static var sentWords: String { String(localized: "Sent a widget") }

    public static let opening = "::preview{"

    /// `key="value"`, `key='value'` or `key=value`, separated by spaces, as remark-directive reads
    /// them. `#id` and `.class` shorthands mean nothing here and are skipped.
    private static func attributes(_ text: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var rest = text[...]
        while true {
            rest = rest.drop { $0.isWhitespace }
            guard !rest.isEmpty else { return result }
            let key = rest.prefix { $0 != "=" && !$0.isWhitespace }
            rest = rest.dropFirst(key.count)
            guard rest.first == "=" else { continue }
            rest = rest.dropFirst()
            let value: Substring
            if let quote = rest.first, quote == "\"" || quote == "'" {
                rest = rest.dropFirst()
                value = rest.prefix { $0 != quote }
                rest = rest.dropFirst(value.count + 1)
            } else {
                value = rest.prefix { !$0.isWhitespace }
                rest = rest.dropFirst(value.count)
            }
            result[String(key)] = String(value)
        }
    }
}
