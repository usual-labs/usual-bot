import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

struct FileViewerTests {
    @Test func picksTheViewerByType() {
        #expect(FileKind(path: "/home/h/report.pdf") == .pdf)
        #expect(FileKind(path: "Notes.MD") == .markdown)
        #expect(FileKind(path: "docs/plan.markdown") == .markdown)
        #expect(FileKind(path: "/tmp/chart.PNG") == .image)
        #expect(FileKind(path: "/tmp/photo.heic") == .image)
        #expect(FileKind(path: "/tmp/data.csv") == nil)
        #expect(FileKind(path: "/tmp/memo.m4a") == nil)
        #expect(FileKind(path: "README") == nil)
    }

    @Test func aFileIsTheSameWithOrWithoutItsBytes() {
        let path = MediaSource.gateway("/tmp/chart.png")
        let sent = ViewedFile(source: path, name: "chart.png", profile: "ops", kind: .image, data: Data([1, 2]))
        let named = ViewedFile(source: path, name: "chart.png", profile: "ops", kind: .image)
        #expect(sent == named)
        #expect(sent.hashValue == named.hashValue)
        #expect(sent != ViewedFile(source: path, name: "chart.png", profile: "atlas", kind: .image))
    }

    @Test func aRequestOpensOnlyInItsOwnChat() {
        let request = FileRequest(
            contactID: "atlas", source: .gateway("/tmp/plan.md"), name: "plan.md", profile: "atlas")
        #expect(
            ViewedFile(request, for: "atlas")
                == ViewedFile(
                    source: .gateway("/tmp/plan.md"), name: "plan.md", profile: "atlas", kind: .markdown))
        #expect(ViewedFile(request, for: "forge") == nil)
        let unknown = FileRequest(contactID: "atlas", source: .gateway("/tmp/a.csv"), name: "a.csv", profile: nil)
        #expect(ViewedFile(unknown, for: "atlas") == nil)
    }
}
