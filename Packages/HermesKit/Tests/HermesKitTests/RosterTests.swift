import Foundation
import Testing

@testable import HermesKit

struct RosterTests {
    /// Shaped like a real `profiles.list` result (tui_gateway/methods_profiles.py).
    static let listJSON = """
        {"profiles":[
          {"name":"default","path":"/h","is_default":true,"model":"hermes-4","provider":"nous",
           "description":"Your everyday agent","display_name":"","skill_count":12,"previous_names":[],
           "ui_meta_revisions":{},"ui_meta":{"hermes-bots":{"title":"Hermes","color":"#6E7BFF","pinned":true}},
           "has_avatar":false,
           "canonical_session":{"id":"s1","resolved_id":"s1b","root_title":"Bot Chat","title":"Bot Chat",
             "preview":"Pushed release/0.3.1","started_at":1700000000,"last_active":1700000500.5,"message_count":42},
           "last_session":null,"worker_session":null},
          {"name":"scout","description":"Reads feeds","display_name":"Scout","ui_meta":{"hermes-bots":{"color":7}},
           "canonical_session":null},
          {"name":"old-bot","ui_meta":{"hermes-bots":{"hidden":true}}},
          {"name":"ops","ui_meta":"not-an-object","canonical_session":{"id":"s3","preview":"","last_active":0}}
        ],"bot_mode_protocol":true,"install_id":"i1"}
        """

    @Test func mapsProfilesToContacts() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(Self.listJSON.utf8))
        let contacts = try value.decode(ProfileList.self).profiles.compactMap(Contact.init(profile:))

        #expect(contacts.map(\.id) == ["default", "scout", "ops"])

        let hermes = contacts[0]
        #expect(hermes.name == "Hermes")  // From the bot title, not the "default" fallback.
        #expect(hermes.tint == "#6E7BFF")
        #expect(hermes.preview == "Pushed release/0.3.1")
        #expect(hermes.lastActive == Date(timeIntervalSince1970: 1_700_000_500.5))
        #expect(hermes.isPinned)

        let scout = contacts[1]
        #expect(scout.name == "Scout")
        #expect(scout.tint == nil)
        #expect(scout.preview == "Reads feeds")
        #expect(scout.lastActive == nil)

        let ops = contacts[2]
        #expect(ops.name == "Ops")
        #expect(ops.preview == nil)
        #expect(ops.lastActive == nil)
    }

    @Test func untitledProfilesGetFriendlyNames() {
        #expect(Contact.friendlyName(forProfile: "default") == "Hermes")
        #expect(Contact.friendlyName(forProfile: "job-scout") == "Job Scout")
        #expect(Contact.friendlyName(forProfile: "shiv") == "Shiv")
        #expect(Contact.friendlyName(forProfile: "data_ops-2") == "Data Ops 2")
    }

    @Test func previewsDropMarkdown() {
        #expect(
            Contact.plainPreview("**Done.** Pushed `release/0.3.1` to [origin](https://x.example)")
                == "Done. Pushed release/0.3.1 to origin")
        // The gateway cuts previews at 80 characters, which can leave bold unclosed.
        #expect(Contact.plainPreview("**Back to the rest of this week...") == "Back to the rest of this week...")
        #expect(Contact.plainPreview("## Summary  of   today") == "Summary of today")
        #expect(Contact.plainPreview("2 * 3 = 6") == "2 * 3 = 6")
    }
}
