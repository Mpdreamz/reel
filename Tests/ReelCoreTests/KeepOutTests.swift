@testable import ReelCore
import Testing

struct KeepOutTests {
    @Test func anAppThatStartsMidTakeIsANewcomer() {
        #expect(Recorder.newcomers([10, 20, 30], already: [10, 20], owned: []) == [30])
    }

    @Test func whatIsAlreadyKeptOutOrRecordedIsNot() {
        // 20 is the app recorded (or a browser's helper); 10 was kept out from the first frame.
        #expect(Recorder.newcomers([10, 20], already: [10], owned: [20]).isEmpty)
    }

    @Test func eachNewcomerOnceInTheOrderListed() {
        #expect(Recorder.newcomers([40, 30, 40, 50], already: [], owned: [50]) == [40, 30])
    }
}
