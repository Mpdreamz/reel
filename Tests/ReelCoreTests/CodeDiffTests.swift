@testable import ReelCore
import Testing

struct CodeDiffTests {
    @Test func linesKeptAddedAndRemovedInOrder() {
        let diff = CodeDiff(
            before: "a\nb\nc\nd\n",
            after: "a\nc\nd\ne\n"
        )
        #expect(diff.rows.map(\.kind) == [.kept, .removed, .kept, .kept, .added])
        #expect(diff.rows.map(\.text) == ["a", "b", "c", "d", "e"])
        // Numbered as the new file numbers them; a removed line has none.
        #expect(diff.rows.map(\.number) == [1, nil, 2, 3, 4])
        #expect(diff.hunks == [1, 4])
        #expect(diff.added == 1 && diff.removed == 1)
    }

    @Test func anEditedLineMarksTheWordsThatChanged() {
        let diff = CodeDiff(
            before: "let start = max(now, speechEnd)\n",
            after: "let start = max(now, speechEnd, floor)\n"
        )
        #expect(diff.rows.map(\.kind) == [.removed, .added])
        // Removals first, then additions, as a unified diff has them.
        #expect(diff.rows[0].words == [])
        let added = diff.rows[1]
        #expect(added.words.map { String(Array(added.text)[$0]) } == [", floor"])
    }

    @Test func aRenameMarksBothSides() {
        let diff = CodeDiff(before: "    func speak(_ text: String)\n", after: "    func say(_ text: String)\n")
        #expect(diff.rows[0].words.map { String(Array(diff.rows[0].text)[$0]) } == ["speak"])
        #expect(diff.rows[1].words.map { String(Array(diff.rows[1].text)[$0]) } == ["say"])
    }

    @Test func aReplacedLineIsNotAnEdit() {
        let diff = CodeDiff(before: "return nil\n", after: "throw ReelError(\"gone\")\n")
        #expect(diff.rows.map(\.kind) == [.removed, .added])
        let marked = diff.rows.flatMap(\.words)
        #expect(marked.isEmpty)
    }

    @Test func theSameFileHasNoHunks() {
        let diff = CodeDiff(before: "a\nb\n", after: "a\nb\n")
        #expect(diff.hunks.isEmpty)
        let kinds = Set(diff.rows.map(\.kind))
        #expect(kinds == [.kept])
    }
}
