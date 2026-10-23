import Foundation
import Testing

@testable import HermesKit

struct AttachmentRefTests {
    @Test func splitsAttachmentLinesOffTheMessage() {
        let message =
            "What's in these?\n\n@image:/home/h/.hermes/images/upload_1.png\n@file:`attachments/Q3 report.pdf`"
        let (text, attachments) = AttachmentRef.split(message)
        #expect(text == "What's in these?")
        #expect(
            attachments == [
                AttachmentRef(kind: .image, path: "/home/h/.hermes/images/upload_1.png"),
                AttachmentRef(kind: .file, path: "attachments/Q3 report.pdf"),
            ])
        #expect(attachments[1].name == "Q3 report.pdf")
    }

    @Test func leavesOrdinaryMessagesAlone() {
        for message in ["Hello", "Use @file:notes.md for this", "@image: not a path", ""] {
            #expect(AttachmentRef.split(message).text == message)
            #expect(AttachmentRef.split(message).attachments.isEmpty)
        }
        #expect(AttachmentRef.split("@image:a.png").text.isEmpty)
    }

    @Test func quotesPathsTheWayHermesReadsThemBack() {
        #expect(AttachmentRef(kind: .file, path: "attachments/notes.md").line == "@file:attachments/notes.md")
        #expect(AttachmentRef(kind: .file, path: "a b.pdf").line == "@file:`a b.pdf`")
        #expect(AttachmentRef(kind: .image, path: "it`s (1).png").line == "@image:\"it`s (1).png\"")
        #expect(AttachmentRef(line: AttachmentRef(kind: .file, path: "a b.pdf").line)?.path == "a b.pdf")
    }

    @Test func kindFollowsTheExtension() {
        #expect(Attachment(name: "Photo.JPG", data: Data()).kind == .image)
        #expect(Attachment(name: "IMG_0001.heic", data: Data()).kind == .file)
        #expect(Attachment(name: "report.pdf", data: Data()).kind == .file)
    }
}

@MainActor
struct AttachmentSendTests {
    private func openThread() async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private let photo = Attachment(name: "cat.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
    private let report = Attachment(name: "Q3 report.pdf", data: Data("%PDF".utf8))

    @Test func uploadsEachAttachmentThenSendsTheMessage() async throws {
        let (thread, gateway) = try await openThread()
        let sending = Task { await thread.send("Summarise these", attachments: [photo, report]) }

        let image = try await gateway.answer(
            1, method: "image.attach_bytes", result: ["attached": true, "path": "/h/images/upload_cat.png"])
        #expect(image["content_base64"] == .string(photo.data.base64EncodedString()))
        #expect(image["filename"] == "cat.png")
        let file = try await gateway.answer(
            2, method: "file.attach",
            result: ["attached": true, "ref_text": "@file:`attachments/Q3 report.pdf`", "name": "Q3 report.pdf"])
        #expect(
            file["data_url"] == .string("data:application/octet-stream;base64," + report.data.base64EncodedString()))
        let submit = try await gateway.answer(3, method: "prompt.submit", result: ["status": "streaming"])

        #expect(await sending.value)
        #expect(submit["text"] == "Summarise these\n\n@file:`attachments/Q3 report.pdf`")
        #expect(
            thread.state.items.map(\.content) == [
                .user("Summarise these\n\n@image:/h/images/upload_cat.png\n@file:`attachments/Q3 report.pdf`")
            ])
        #expect(thread.sentImages["/h/images/upload_cat.png"] == photo.data)
    }

    @Test func failedUploadSendsNothingAndTakesQueuedImagesBack() async throws {
        let (thread, gateway) = try await openThread()
        let sending = Task { await thread.send("Look", attachments: [photo, report]) }

        _ = try await gateway.answer(
            1, method: "image.attach_bytes", result: ["attached": true, "path": "/h/images/upload_cat.png"])
        _ = try await gateway.answer(2, method: "file.attach", error: (5028, "disk full"))
        let detach = try await gateway.answer(3, method: "image.detach", result: ["detached": true])

        #expect(await sending.value == false)
        #expect(detach == ["session_id": "live-1", "path": "/h/images/upload_cat.png"])
        #expect(thread.state.items.map(\.content) == [.notice("Couldn't attach Q3 report.pdf: disk full")])
        #expect(!thread.state.isRunning)
        #expect(!thread.isUploading)
    }

    @Test func tooLargeFileIsRefusedBeforeUploading() async throws {
        let (thread, gateway) = try await openThread()
        let huge = Attachment(name: "huge.png", data: Data(count: 25 * 1024 * 1024 + 1))
        #expect(await thread.send("", attachments: [huge]) == false)
        #expect(gateway.socket.sent.count == 1)
        #expect(thread.state.items.map(\.content) == [.notice("Couldn't attach huge.png: It's over the 25 MB limit.")])
    }
}
