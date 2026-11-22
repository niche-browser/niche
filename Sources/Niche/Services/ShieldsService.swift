import AppKit
import NicheCEF
import Observation

/// Shields in the app: keeps the filter packs (Application Support/…/Shields), builds an engine
/// for each set of lists some profile's switches in Settings ▸ Privacy ask for (the groups, and
/// the optional lists of "More lists"; profiles that ask for the same ones share it), and looks
/// for newer packs every six hours. A pack is trusted only with the signature of the repository's Shields workflow
/// (`ShieldsPack.isSigned`), on download and again every time it is read from disk. The only
/// thing sent anywhere is the request for the packs themselves, to GitHub.
///
/// `NICHE_SHIELDS_SOURCE` points a test instance at another place for the packs (a `file://`
/// folder, or `off` for none, which scenarios use so they never reach the network), and with
/// it `NICHE_SHIELDS_UNSIGNED=1` accepts packs without a signature.
@MainActor
@Observable
final class ShieldsService {
    static let shared = ShieldsService()

    enum Status: Equatable {
        /// Nothing switched on.
        case off
        /// No pack yet: the first download hasn't finished (or there is no network).
        case waiting
        case ready(rules: Int)
    }

    /// A list in use, for Settings' credits.
    struct Credit: Identifiable, Equatable {
        let id: String
        let title: String
        let group: ShieldsGroup
        let licence: String
        let homepage: String
    }

    /// An engine in use: its slot in the bridge (NicheShieldsBuild installInSlot:), how many rules
    /// its lists hold, and the lists, for the credits.
    struct Engine: Equatable {
        let slot: Int
        let rules: Int
        let credits: [Credit]
    }

    /// The engines built, by the lists each was built from.
    private(set) var engines: [ShieldsLists: Engine] = [:]
    /// No pack yet: the first download hasn't finished (or there is no network).
    private(set) var waitingForLists = true
    /// When the lists in use were put together, and when Niche last looked for newer ones.
    private(set) var built: Date?
    private(set) var lastChecked: Date?
    private(set) var checking = false
    /// The optional lists there are (Settings ▸ Privacy "More lists"); empty until the first look.
    private(set) var catalog = ShieldsCatalog()
    /// Optional lists switched on whose pack hasn't arrived yet.
    private(set) var extrasPending: Set<String> = []

    /// The sets of lists the profiles ask for (none switched off entirely).
    @ObservationIgnored private var wanted: Set<ShieldsLists> = []
    /// The slot each set of lists has, built or building; one no profile wants any more keeps its
    /// slot until it is freed, a little after the build that replaced it.
    @ObservationIgnored private var slots: [ShieldsLists: Int] = [:]
    /// Sets of lists on their way to an engine, so a second ask while one builds doesn't build it twice.
    @ObservationIgnored private var queued: Set<ShieldsLists> = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var clock: Scheduler?
    @ObservationIgnored private var looking: ScheduledWork?
    @ObservationIgnored private var state: State
    @ObservationIgnored private let stateFile = JSONStore<State>("Shields/state.json")
    /// One build at a time, in order: the last one asked for wins.
    @ObservationIgnored private let work = DispatchQueue(label: "niche.shields", qos: .utility)
    @ObservationIgnored private var generation = 0

    /// How long after launch the first look for newer lists waits.
    private static let firstLook: TimeInterval = 8

    private struct State: Codable {
        var lastSuccess: Date?
        var lastAttempt: Date?
    }

    nonisolated private static let folder: URL = {
        let url = AppPaths.supportDir.appendingPathComponent("Shields", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    nonisolated private static let override = ProcessInfo.processInfo.environment["NICHE_SHIELDS_SOURCE"]
    /// Where the packs come from; nil when a test instance asked for none.
    nonisolated private static let source: URL? = override == "off" ? nil : URL(string: override ?? ShieldsUpdate.source)
    nonisolated private static let acceptsUnsigned = override != nil && ProcessInfo.processInfo.environment["NICHE_SHIELDS_UNSIGNED"] == "1"

    private init() {
        _ = Self.folder
        state = stateFile.load(or: { State() })
        lastChecked = state.lastSuccess
        if let data = try? Data(contentsOf: Self.file(ShieldsUpdate.catalog)), let read = try? JSONDecoder().decode(ShieldsCatalog.self, from: data) {
            catalog = read
        }
    }

    // MARK: The switches

    /// What Settings shows for a profile's lists.
    func status(for lists: ShieldsLists) -> Status {
        if lists.isOff { return .off }
        if let e = engines[lists] { return .ready(rules: e.rules) }
        return .waiting
    }

    func credits(for lists: ShieldsLists) -> [Credit] { engines[lists]?.credits ?? [] }

    /// The slot of the engine built from these lists, once it is built.
    func slot(for lists: ShieldsLists) -> Int? { engines[lists]?.slot }

    /// Starts Shields with the sets of lists the profiles ask for; after that, `use` follows them.
    func start(lists: Set<ShieldsLists>, clock: Scheduler) {
        guard !started else { return use(lists) }
        started = true
        wanted = lists.filter { !$0.isOff }
        self.clock = clock
        NicheCEFRuntime.setShieldsPageScript(ShieldsPageScript.content)
        rebuild(all: true)
        // Soon after launch, not during it; then hourly, which is when a day may have passed.
        // A Mac with no lists yet (a first launch) asks at once; otherwise soon after launch,
        // not during it.
        if FileManager.default.fileExists(atPath: Self.file(ShieldsUpdate.mainPack).path) {
            clock.after(Self.firstLook) { [weak self] in self?.lookIfDue() }
        } else {
            look()
        }
        looking = clock.every(ShieldsUpdate.retry) { [weak self] in self?.lookIfDue() }
    }

    func use(_ lists: Set<ShieldsLists>) {
        let next = lists.filter { !$0.isOff }
        guard started, next != wanted else { return }
        let regionalAdded = Self.wantsRegional(next) && !Self.wantsRegional(wanted)
        // A list just switched on has no pack on this Mac yet: it is fetched now.
        let extrasAdded = !Self.extras(next).subtracting(Self.extras(wanted)).isEmpty
        wanted = next
        rebuild(all: false)
        if regionalAdded || extrasAdded { look() }
    }

    nonisolated private static func wantsRegional(_ lists: Set<ShieldsLists>) -> Bool { lists.contains { $0.groups.contains(.regional) } }
    nonisolated private static func extras(_ lists: Set<ShieldsLists>) -> Set<String> { lists.reduce(into: []) { $0.formUnion($1.extras) } }

    // MARK: Building

    nonisolated private static func file(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// A pack on disk, if it is there and (still) carries the signature.
    nonisolated private static func pack(_ name: String) -> ShieldsPack? {
        let url = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if !acceptsUnsigned {
            guard let signature = try? String(contentsOf: url.appendingPathExtension("sig"), encoding: .utf8),
                  ShieldsPack.isSigned(data, signature: signature) else {
                NicheLog.note("Shields: \(name) on disk has no valid signature, not used")
                return nil
            }
        }
        return try? ShieldsPack.read(data)
    }

    /// How long an engine no profile asks for stays in its slot after the one that replaced it is
    /// built: the profiles move to the new slot first, so no page is left without its lists.
    private static let freeAfter: TimeInterval = 10

    /// Builds the engines the profiles ask for that aren't built yet, or every one (`all`: the
    /// packs changed), each in its own slot.
    private func rebuild(all: Bool) {
        generation += 1
        let generation = generation, wanted = wanted
        let unwanted = Set(slots.keys).subtracting(wanted)
        guard !wanted.isEmpty else {
            for (lists, slot) in slots { NicheCEFRuntime.removeShields(fromSlot: slot); slots[lists] = nil }
            engines = [:]
            waitingForLists = false
            NicheLog.note("Shields off")
            return
        }
        for lists in wanted.sorted(by: Self.order) where slots[lists] == nil {
            slots[lists] = (0...).first { !slots.values.contains($0) }
        }
        let jobs = wanted.sorted(by: Self.order).filter { all || (engines[$0] == nil && !queued.contains($0)) }.map { ($0, slots[$0]!) }
        queued.formUnion(jobs.map(\.0))
        let languages = Locale.preferredLanguages
        work.async {
            guard let main = Self.pack(ShieldsUpdate.mainPack) else {
                DispatchQueue.main.async {
                    let me = ShieldsService.shared
                    me.queued.subtract(jobs.map(\.0))
                    guard me.generation == generation else { return }
                    if me.engines.isEmpty { me.waitingForLists = true }
                    NicheLog.note("Shields: no lists yet")
                }
                return
            }
            var built: [(ShieldsLists, Engine)] = [], pending: Set<String> = []
            for (lists, slot) in jobs {
                let (engine, missing) = Self.build(lists, main: main, languages: languages, slot: slot)
                built.append((lists, engine))
                pending.formUnion(missing)
            }
            DispatchQueue.main.async {
                let me = ShieldsService.shared
                me.queued.subtract(jobs.map(\.0))
                // An engine is kept while a profile still asks for its lists, whichever ask built it.
                for (lists, engine) in built where me.wanted.contains(lists) && me.slots[lists] == engine.slot { me.engines[lists] = engine }
                me.waitingForLists = false
                me.built = main.built
                if me.generation == generation {
                    for lists in unwanted where !me.wanted.contains(lists) { me.engines[lists] = nil }
                    me.extrasPending = pending
                }
                me.clock?.after(Self.freeAfter) { me.freeUnwanted() }
            }
        }
    }

    /// Frees the slots of lists no profile asks for any more.
    private func freeUnwanted() {
        for (lists, slot) in slots where !wanted.contains(lists) {
            NicheCEFRuntime.removeShields(fromSlot: slot)
            slots[lists] = nil
            engines[lists] = nil
        }
    }

    /// A stable order for the sets of lists, so slots are given out the same way each launch.
    nonisolated private static func order(_ a: ShieldsLists, _ b: ShieldsLists) -> Bool { key(a) < key(b) }
    nonisolated private static func key(_ l: ShieldsLists) -> String {
        l.groups.map(\.rawValue).sorted().joined(separator: "+") + "|" + l.extras.sorted().joined(separator: "+")
    }

    /// One engine, built and installed in `slot`; and the optional lists whose pack isn't here yet.
    nonisolated private static func build(_ wanted: ShieldsLists, main: ShieldsPack, languages: [String], slot: Int) -> (Engine, Set<String>) {
        let groups = wanted.groups
        var lists = main.lists(for: groups)
        if groups.contains(.regional), let data = try? Data(contentsOf: file(ShieldsUpdate.regionalIndex)),
           let index = try? JSONDecoder().decode(ShieldsRegionalIndex.self, from: data) {
            for entry in index.wanted(languages: languages) {
                if let pack = pack(ShieldsUpdate.regionalPack(entry.id)) { lists += pack.lists.filter { $0.group == .regional } }
            }
        }
        // The optional lists switched on, each from its own pack. One whose pack isn't here
        // yet is left out until it arrives.
        var pending: Set<String> = []
        for id in wanted.extras.sorted() {
            if let pack = pack(ShieldsUpdate.extraPack(id)) { lists += pack.lists } else { pending.insert(id) }
        }
        let build = NicheShieldsBuild()
        for list in lists { build.addList(list.text, group: list.group.number, trusted: list.trusted) }
        build.addResources(main.scriptlets, forPages: true)
        build.addResources(main.redirects, forPages: false)
        let started = Date()
        let rules = build.install(inSlot: slot)
        let took = Date().timeIntervalSince(started)
        let credits = lists.map { Credit(id: $0.id, title: $0.title, group: $0.group, licence: $0.licence, homepage: $0.homepage) }
        NicheLog.note("Shields ready: \(lists.count) lists, \(rules) rules, groups \(groups.map(\.rawValue).sorted().joined(separator: "+")), built in \(Int(took * 1000)) ms")
        return (Engine(slot: slot, rules: rules, credits: credits), pending)
    }

    // MARK: Updating

    private func lookIfDue() {
        guard ShieldsUpdate.isDue(lastSuccess: state.lastSuccess, lastAttempt: state.lastAttempt, now: clock?.now ?? Date())
                || !FileManager.default.fileExists(atPath: Self.file(ShieldsUpdate.mainPack).path)
                // A copy of Niche from before "More lists" has no catalogue yet: it asks once.
                || (Self.source != nil && !FileManager.default.fileExists(atPath: Self.file(ShieldsUpdate.catalog).path) && state.lastAttempt.map { (clock?.now ?? Date()).timeIntervalSince($0) >= ShieldsUpdate.retry } != false) else { return }
        look()
    }

    /// Looks for newer packs now (Settings ▸ Privacy "Update Now" too).
    func look() {
        guard let source = Self.source, !checking, !wanted.isEmpty else { return }
        checking = true
        state.lastAttempt = Date()
        stateFile.save(state)
        let wantsRegional = Self.wantsRegional(wanted), languages = Locale.preferredLanguages, extras = Self.extras(wanted)
        Task.detached(priority: .utility) {
            var changed = false, reached = false
            do {
                changed = try await Self.fetch(ShieldsUpdate.mainPack, from: source)
                reached = true
                if wantsRegional, let data = try? await Self.get(source.appendingPathComponent(ShieldsUpdate.regionalIndex)),
                   let index = try? JSONDecoder().decode(ShieldsRegionalIndex.self, from: data) {
                    try? data.write(to: Self.folder.appendingPathComponent(ShieldsUpdate.regionalIndex), options: .atomic)
                    for entry in index.wanted(languages: languages) {
                        if (try? await Self.fetch(ShieldsUpdate.regionalPack(entry.id), from: source)) == true { changed = true }
                    }
                }
                // What "More lists" offers, and the packs of the ones switched on. A list the
                // catalogue no longer has keeps the pack this Mac has.
                var offered: ShieldsCatalog?
                if let data = try? await Self.get(source.appendingPathComponent(ShieldsUpdate.catalog)),
                   let read = try? JSONDecoder().decode(ShieldsCatalog.self, from: data) {
                    try? data.write(to: Self.folder.appendingPathComponent(ShieldsUpdate.catalog), options: .atomic)
                    offered = read
                    for entry in read.wanted(extras) {
                        if (try? await Self.fetch(ShieldsUpdate.extraPack(entry.id), from: source)) == true { changed = true }
                    }
                }
                let found = offered
                await MainActor.run { if let found { ShieldsService.shared.catalog = found } }
            } catch {
                NicheLog.note("Shields: couldn't get the lists (\(error.localizedDescription))")
            }
            let (didChange, didReach) = (changed, reached)
            await MainActor.run {
                let me = ShieldsService.shared
                me.checking = false
                if didReach {
                    me.state.lastSuccess = Date()
                    me.lastChecked = me.state.lastSuccess
                    me.stateFile.save(me.state)
                }
                if didChange || me.wanted.contains(where: { me.engines[$0] == nil }) || !me.extrasPending.isEmpty { me.rebuild(all: didChange || !me.extrasPending.isEmpty) }
                NicheLog.note("Shields: looked for newer lists, \(didChange ? "got some" : didReach ? "none" : "unreachable")")
            }
        }
    }

    private enum Failure: LocalizedError {
        case status(Int), unsigned(String), unreadable(String)
        var errorDescription: String? {
            switch self {
            case .status(let code): "HTTP \(code)"
            case .unsigned(let name): "\(name) is not signed by Niche"
            case .unreadable(let name): "\(name) is not a pack"
            }
        }
    }

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Niche"]
        return URLSession(configuration: configuration)
    }()

    nonisolated private static func get(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.status(http.statusCode) }
        return data
    }

    /// Gets a pack when its signature differs from the one on disk; true when it was replaced.
    /// The download is checked (signed, readable) before it takes the old one's place.
    nonisolated private static func fetch(_ name: String, from source: URL) async throws -> Bool {
        let target = folder.appendingPathComponent(name), signatureFile = target.appendingPathExtension("sig")
        let signature = (try? await get(source.appendingPathComponent(name + ".sig"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        if signature.isEmpty, !acceptsUnsigned { throw Failure.unsigned(name) }
        // The same signature as the pack on disk: the same pack.
        if !signature.isEmpty, FileManager.default.fileExists(atPath: target.path),
           (try? String(contentsOf: signatureFile, encoding: .utf8)) == signature { return false }
        let data = try await get(source.appendingPathComponent(name))
        guard acceptsUnsigned || ShieldsPack.isSigned(data, signature: signature) else { throw Failure.unsigned(name) }
        guard (try? ShieldsPack.read(data)) != nil else { throw Failure.unreadable(name) }
        if signature.isEmpty, (try? Data(contentsOf: target)) == data { return false }
        try data.write(to: target, options: .atomic)
        try signature.write(to: signatureFile, atomically: true, encoding: .utf8)
        return true
    }
}
