import NicheCore
import Testing

/// One engine per set of lists some profile asks for, each in its own slot (#18), and never a
/// profile left without its lists while a new engine builds (review of #19, 22 Nov 2026).
struct ShieldsSlotsTests {
    private let x = ShieldsLists(groups: [.ads, .trackers])
    private let y = ShieldsLists(groups: [.trackers])
    private let w = ShieldsLists(groups: [.cookies])

    @Test func profilesSetUpAlikeShareOneEngine() {
        var s = ShieldsSlots()
        let jobs = s.want([x, x, y])
        #expect(jobs.count == 2)
        #expect(Set(jobs.map(\.slot)) == [0, 1])
        // Asked again while building: nothing more to build.
        #expect(s.want([x, y]).isEmpty)
    }

    @Test func listsSwitchedOffEntirelyHaveNoEngine() {
        var s = ShieldsSlots()
        #expect(s.want([ShieldsLists(groups: [])]).isEmpty)
        #expect(s.slots.isEmpty)
    }

    /// The review's case: Default goes from X to Y; Y is built and a free is timed; the user flips
    /// another switch (W) before the timer fires. Y's slot is what Default still uses until W is
    /// built, so neither it nor X's may go yet.
    @Test func anOldEngineStaysUntilTheNewOneIsBuilt() {
        var s = ShieldsSlots()
        let first = s.want([x])
        #expect(s.finished(x, slot: first[0].slot) == .keep)
        let toY = s.want([y])
        #expect(s.finished(y, slot: toY[0].slot) == .keep)
        let toW = s.want([w])
        #expect(toW.count == 1)
        #expect(s.freeable().isEmpty, "W is building: Default is still on Y's engine")
        #expect(s.finished(w, slot: toW[0].slot) == .keep)
        #expect(Set(s.freeable()) == [first[0].slot, toY[0].slot])
        #expect(s.slots == [w: toW[0].slot])
    }

    /// A slot that waits to be freed is nobody else's in the meantime.
    @Test func aSlotWaitingToBeFreedIsNotGivenOut() {
        var s = ShieldsSlots()
        let a = s.want([x])
        _ = s.finished(x, slot: a[0].slot)
        let b = s.want([y])
        #expect(b[0].slot != a[0].slot)
    }

    /// A build that finishes after Shields went off everywhere: its engine goes, nothing keeps it.
    @Test func anEngineBuiltForListsGivenUpIsEmptied() {
        var s = ShieldsSlots()
        let jobs = s.want([x])
        #expect(s.clear() == [jobs[0].slot])
        #expect(s.finished(x, slot: jobs[0].slot) == .empty(slot: jobs[0].slot))
    }

    /// Given up while it built, but its slot was given to another set: that set's build replaces it.
    @Test func anEngineWhoseSlotIsAnothersIsLeftForItsBuild() {
        var s = ShieldsSlots()
        let jobs = s.want([x])
        _ = s.clear()
        let next = s.want([y])
        #expect(next[0].slot == jobs[0].slot)
        #expect(s.finished(x, slot: jobs[0].slot) == .drop)
        #expect(s.finished(y, slot: next[0].slot) == .keep)
    }

    /// New packs: every engine asked for is built again, in the slot it has.
    @Test func newPacksRebuildEveryEngineInPlace() {
        var s = ShieldsSlots()
        for job in s.want([x, y]) { _ = s.finished(job.lists, slot: job.slot) }
        let again = s.want([x, y], all: true)
        #expect(again.count == 2)
        #expect(Dictionary(uniqueKeysWithValues: again.map { ($0.lists, $0.slot) }) == s.slots)
    }

    /// No packs on the Mac yet: nothing is built, and the build can be asked for again.
    @Test func aBuildWithNoPacksCanBeAskedForAgain() {
        var s = ShieldsSlots()
        let jobs = s.want([x])
        #expect(s.finished(x, slot: jobs[0].slot, installed: false) == .drop)
        #expect(s.want([x]).count == 1)
    }
}
