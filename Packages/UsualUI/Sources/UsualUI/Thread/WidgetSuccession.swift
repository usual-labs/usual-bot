import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// The newest message showing each widget file in the transcript around it.
    @Entry var widgetSuccession = WidgetSuccession()
    /// The message a widget is in; `nil` outside a transcript's messages, such as a reply being written.
    @Entry var widgetPlace: WidgetPlace? = nil
}

/// A message holding widgets: its item, and the room member who wrote it (`nil` for the chat's agent).
struct WidgetPlace: Hashable {
    let item: Int
    var author: String? = nil
}

/// An agent can write a new message's widget to a file an earlier message already showed. The
/// gateway keeps only the newest page, so the earlier widget would turn into the new one: it stops
/// reading its file once a later message shows it (`InlineWidget`).
struct WidgetSuccession: Equatable {
    private struct Key: Hashable {
        let author: String?
        let file: String
    }

    private var newest: [Key: Int] = [:]

    init() {}

    @MainActor init(_ items: [TranscriptItem]) {
        for item in items {
            let (author, text): (String?, String)
            switch item.content {
            case .assistant(let reply): (author, text) = (nil, reply)
            case .member(let id, let reply): (author, text) = (id, reply)
            case .background(_, let result): (author, text) = (nil, result)
            default: continue
            }
            // Most messages have none; this runs as each word of a reply arrives.
            guard text.contains(WidgetDirective.opening) else { continue }
            for case .widget(let directive) in MarkdownBlock.blocks(of: text) {
                newest[Key(author: author, file: directive.file)] = item.id
            }
        }
    }

    /// Whether a later message shows `file` again.
    func isReplaced(_ file: String, at place: WidgetPlace) -> Bool {
        newest[Key(author: place.author, file: file)].map { $0 != place.item } ?? false
    }
}
