import Foundation

/// Which filter engine sits in which slot of the bridge (NicheShields): one engine for each set of
/// lists some browser profile asks for (`ShieldsLists`), profiles set up alike sharing one. Kept by
/// ShieldsService, which builds the engines off the main thread and asks this what to build, what
/// to keep and when an engine no profile asks for can go.
///
/// A profile whose lists change keeps the engine it had until the new one is built (AppDelegate),
/// so an old engine stays in its slot until every set of lists asked for has one: freed earlier,
/// that profile's pages would have no lists at all for as long as the build took.
public struct ShieldsSlots: Equatable, Sendable {
    /// The slot of each set of lists, built, building or no longer asked for and not yet freed.
    public private(set) var slots: [ShieldsLists: Int] = [:]
    /// The sets of lists asked for now.
    public private(set) var wanted: Set<ShieldsLists> = []
    /// The sets of lists with an engine in their slot.
    public private(set) var built: Set<ShieldsLists> = []
    /// The sets of lists on their way to an engine.
    public private(set) var queued: Set<ShieldsLists> = []

    public init() {}

    /// What a build finished with: keep the engine (it is what its lists' profiles get now), or
    /// empty the slot it went into (its lists were given up while it built and nobody has the slot).
    public enum Finished: Equatable, Sendable {
        case keep
        case empty(slot: Int)
        /// Its lists were given up, but the slot is another set's now: that one's build replaces it.
        case drop
    }

    /// The sets of lists the profiles ask for now (none switched off entirely). Returns the builds
    /// to start: those not built or building yet, or every one asked for when `all` (the packs
    /// changed). Each new set gets the lowest slot nobody holds.
    public mutating func want(_ lists: Set<ShieldsLists>, all: Bool = false) -> [(lists: ShieldsLists, slot: Int)] {
        wanted = lists.filter { !$0.isOff }
        let order = wanted.sorted { Self.key($0) < Self.key($1) }
        for l in order where slots[l] == nil {
            slots[l] = (0...).first { slot in !slots.values.contains(slot) }
        }
        let jobs = order.filter { all || (!built.contains($0) && !queued.contains($0)) }.map { (lists: $0, slot: slots[$0]!) }
        queued.formUnion(jobs.map(\.lists))
        return jobs
    }

    /// Every profile switched Shields off: the slots to empty now (nothing is left to fall back on).
    public mutating func clear() -> [Int] {
        wanted = []
        let all = Array(slots.values).sorted()
        slots = [:]
        built = []
        return all
    }

    /// A build for `lists` finished in `slot` (or found no packs: `installed` false).
    public mutating func finished(_ lists: ShieldsLists, slot: Int, installed: Bool = true) -> Finished {
        queued.remove(lists)
        guard installed else { return .drop }
        if wanted.contains(lists), slots[lists] == slot {
            built.insert(lists)
            return .keep
        }
        return slots.values.contains(slot) ? .drop : .empty(slot: slot)
    }

    /// The slots of lists nobody asks for any more, to empty now; none while a set asked for has
    /// no engine yet (a profile may still be on an old one) or a build is under way.
    public mutating func freeable() -> [Int] {
        guard queued.isEmpty, wanted.allSatisfy(built.contains) else { return [] }
        let gone = slots.filter { !wanted.contains($0.key) }
        for (lists, _) in gone {
            slots[lists] = nil
            built.remove(lists)
        }
        return gone.values.sorted()
    }

    /// A stable order, so slots are given out the same way each launch.
    private static func key(_ l: ShieldsLists) -> String {
        l.groups.map(\.rawValue).sorted().joined(separator: "+") + "|" + l.extras.sorted().joined(separator: "+")
    }
}
