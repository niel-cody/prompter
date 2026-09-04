import Testing
import Foundation
@testable import PrompterCore

@Suite struct ScriptLibraryTests {
    func makeLibrary() -> ScriptLibrary {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PrompterTests-\(UUID().uuidString)")
        return ScriptLibrary(directory: dir)
    }

    @Test func savesAndReloadsFromDisk() throws {
        let lib = makeLibrary()
        let doc = try lib.save(ScriptDocument(title: "Update", text: "Hello team."))
        let reloaded = ScriptLibrary(directory: lib.directory)
        #expect(reloaded.all().count == 1)
        #expect(reloaded.script(id: doc.id)?.text == "Hello team.")
    }

    @Test func searchMatchesTitleAndBody() throws {
        let lib = makeLibrary()
        try lib.save(ScriptDocument(title: "Board update", text: "Revenue grew."))
        try lib.save(ScriptDocument(title: "Demo", text: "Let's look at inventory."))
        #expect(lib.search("inventory").count == 1)
        #expect(lib.search("board").first?.title == "Board update")
        #expect(lib.search("").count == 2)
    }

    @Test func deleteRemovesFile() throws {
        let lib = makeLibrary()
        let doc = try lib.save(ScriptDocument(title: "Temp", text: "x"))
        try lib.delete(id: doc.id)
        #expect(lib.all().isEmpty)
        #expect(ScriptLibrary(directory: lib.directory).all().isEmpty)
    }

    @Test func infersTitleFromFirstLine() {
        #expect(ScriptDocument.inferredTitle(from: "# Quarterly update\n\nBody") == "Quarterly update")
        #expect(ScriptDocument.inferredTitle(from: "   \n") == "Untitled")
        #expect(ScriptDocument.inferredTitle(from: String(repeating: "word ", count: 30)).hasSuffix("…"))
    }
}
