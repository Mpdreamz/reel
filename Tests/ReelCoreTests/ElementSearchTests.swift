import CoreGraphics
@testable import ReelCore
import Testing

/// A made-up accessibility tree.
private struct Fake: ElementNode {
    var name: String
    var identifier: String?
    var labels: [String] = []
    var frame: CGRect? = CGRect(x: 0, y: 0, width: 10, height: 10)
    var children: [Fake] = []
}

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)

struct ElementSearchTests {
    private let tree = Fake(name: "window", labels: ["Music"], children: [
        Fake(name: "toolbar", children: [
            Fake(name: "play button", identifier: "play", labels: ["Play"]),
        ]),
        Fake(name: "list", children: [
            Fake(name: "row", children: [Fake(name: "deep play label", labels: ["Play"])]),
            Fake(
                name: "hidden row",
                identifier: "offscreen",
                labels: ["Far"],
                frame: CGRect(x: 0, y: 5000, width: 10, height: 10)
            ),
            Fake(name: "no frame", labels: ["Ghost"], frame: nil),
            Fake(name: "zero size", labels: ["Flat"], frame: CGRect(x: 1, y: 1, width: 0, height: 10)),
            Fake(name: "padded", labels: ["  Spaced \n"]),
        ]),
    ])

    private func find(_ target: Target) -> String? {
        ElementSearch.find(target, in: [tree], within: screen)?.name
    }

    @Test func labelsMatchExactlyAndPreferTheShallowest() {
        #expect(find(.label("Play")) == "play button")
        #expect(find(.label("play")) == nil)
        #expect(find(.label("Pla")) == nil)
        #expect(find(.label("Music")) == "window")
        #expect(find(.label("Spaced")) == "padded")
    }

    @Test func identifiers() {
        #expect(find(.identifier("play")) == "play button")
        #expect(find(.identifier("Play")) == nil)
    }

    @Test func onlyWhatShowsOnAScreen() {
        #expect(find(.label("Far")) == nil)
        #expect(find(.identifier("offscreen")) == nil)
        #expect(find(.label("Ghost")) == nil)
        #expect(find(.label("Flat")) == nil)
    }

    @Test func aPointIsNotAnElement() {
        #expect(find(.point(.zero)) == nil)
    }

    @Test func searchesEveryRoot() {
        let sheet = Fake(name: "sheet", children: [Fake(name: "ok", labels: ["OK"])])
        #expect(ElementSearch.find(.label("OK"), in: [tree, sheet], within: screen)?.name == "ok")
    }

    @Test func givesUpOnHugeTrees() {
        let wide = Fake(
            name: "huge",
            children: (0 ... ElementSearch.limit).map { Fake(name: "row \($0)") }
                + [Fake(name: "needle", labels: ["Needle"])]
        )
        #expect(ElementSearch.find(.label("Needle"), in: [wide], within: screen) == nil)
    }
}
