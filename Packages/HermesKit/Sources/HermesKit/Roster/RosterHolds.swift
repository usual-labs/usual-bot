import Foundation

/// Bots made, renamed, given a picture, hidden, shown or deleted from this app, held over the
/// roster read every few seconds. A read can start before the change and land after it, and would
/// put the Bot back as it was. Each change holds until a read shows it, or for three reads (15 s), after which the
/// gateway's word stands, as with sidebar sections.
struct RosterHolds {
    static let reads = 3

    private struct Hold<Value> {
        var value: Value
        var readsLeft = RosterHolds.reads
    }

    private var additions: [Contact.ID: Hold<Contact>] = [:]
    private var removed: [Contact.ID: Hold<Void>] = [:]
    private var names: [Contact.ID: Hold<String>] = [:]
    private var pictures: [Contact.ID: Hold<Contact.Picture?>] = [:]
    private var hiding: [Contact.ID: Hold<Bool>] = [:]

    /// Bots made here that no roster read has listed yet.
    var added: Set<Contact.ID> { Set(additions.keys) }

    var isEmpty: Bool {
        additions.isEmpty && removed.isEmpty && names.isEmpty && pictures.isEmpty && hiding.isEmpty
    }

    mutating func add(_ contact: Contact) {
        removed[contact.id] = nil
        additions[contact.id] = Hold(value: contact)
    }

    mutating func remove(_ id: Contact.ID) {
        additions[id] = nil
        names[id] = nil
        pictures[id] = nil
        hiding[id] = nil
        removed[id] = Hold(value: ())
    }

    mutating func rename(_ id: Contact.ID, to name: String) {
        names[id] = Hold(value: name)
        additions[id]?.value.name = name
    }

    mutating func setPicture(_ id: Contact.ID, _ picture: Contact.Picture?) {
        pictures[id] = Hold(value: picture)
        additions[id]?.value.picture = picture
    }

    mutating func setHidden(_ id: Contact.ID, _ isHidden: Bool) {
        hiding[id] = Hold(value: isHidden)
    }

    /// Which of `agents` are hidden, given the ones a roster read says are, with a change made here
    /// that it doesn't show yet. Call it once for each read, after `apply(to:)`.
    mutating func hidden(among agents: [Contact], reported: Set<Contact.ID>) -> Set<Contact.ID> {
        var hidden = reported
        for (id, hold) in hiding {
            if reported.contains(id) == hold.value || hold.readsLeft <= 0 {
                hiding[id] = nil
            } else if hold.value {
                hidden.insert(id)
            } else {
                hidden.remove(id)
            }
        }
        for id in Array(hiding.keys) { hiding[id]?.readsLeft -= 1 }
        return hidden.intersection(agents.map(\.id))
    }

    /// `agents` from a roster read, with what it doesn't show yet put back. Counts as one read.
    mutating func apply(to agents: [Contact]) -> [Contact] {
        guard !isEmpty else { return agents }
        let listed = Set(agents.map(\.id))
        for (id, hold) in removed where !listed.contains(id) || hold.readsLeft <= 0 { removed[id] = nil }
        var result = agents.filter { removed[$0.id] == nil }
        for (id, hold) in additions where listed.contains(id) || hold.readsLeft <= 0 { additions[id] = nil }
        result += additions.values.map(\.value).sorted { $0.id < $1.id }
        for index in result.indices {
            let id = result[index].id
            if let name = names[id] {
                if result[index].name == name.value || name.readsLeft <= 0 {
                    names[id] = nil
                } else {
                    result[index].name = name.value
                }
            }
            if let picture = pictures[id] {
                if (result[index].picture != nil) == (picture.value != nil) || picture.readsLeft <= 0 {
                    pictures[id] = nil
                } else {
                    result[index].picture = picture.value
                }
            }
        }
        for id in Array(additions.keys) { additions[id]?.readsLeft -= 1 }
        for id in Array(removed.keys) { removed[id]?.readsLeft -= 1 }
        for id in Array(names.keys) { names[id]?.readsLeft -= 1 }
        for id in Array(pictures.keys) { pictures[id]?.readsLeft -= 1 }
        return result
    }
}
