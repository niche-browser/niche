import AppKit
import NicheCEF
import Observation

/// Shields in the app: keeps the filter packs (Application Support/…/Shields), builds the engine
/// from the lists the switches in Settings ▸ Privacy ask for (the groups, and the optional
/// lists of "More lists"), and looks for newer packs every six hours. A pack is trusted only with the signature of the repository's Shields workflow
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

    private(set) var status = Status.waiting
    private(set) var credits: [Credit] = []
    /// When the lists in use were put together, and when Niche last looked for newer ones.
    private(set) var built: Date?
    private(set) var lastChecked: Date?
    private(set) var checking = false
    /// The optional lists there are (Settings ▸ Privacy "More lists"); empty until the first look.
    private(set) var catalog = ShieldsCatalog()
    /// Optional lists switched on whose pack hasn't arrived yet.
    private(set) var extrasPending: Set<String> = []

    @ObservationIgnored private var groups: Set<ShieldsGroup> = []
    @ObservationIgnored private var extras: Set<String> = []
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

    /// Starts Shields with the groups and optional lists the settings ask for; after that, `use`
    /// follows the switches.
    func start(groups: Set<ShieldsGroup>, extras: Set<String> = [], clock: Scheduler) {
        guard !started else { return use(groups, extras: extras) }
        started = true
        self.groups = groups
        self.extras = extras
        self.clock = clock
        NicheCEFRuntime.setShieldsPageScript(ShieldsPageScript.content)
        rebuild()
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

    func use(_ groups: Set<ShieldsGroup>, extras: Set<String>) {
        guard started, groups != self.groups || extras != self.extras else { return }
        let regionalAdded = groups.contains(.regional) && !self.groups.contains(.regional)
        // A list just switched on has no pack on this Mac yet: it is fetched now.
        let extrasAdded = !extras.subtracting(self.extras).isEmpty
        self.groups = groups
        self.extras = extras
        rebuild()
        if regionalAdded || extrasAdded { look() }
    }

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

    private func rebuild() {
        generation += 1
        let generation = generation, groups = groups, extras = extras
        guard !groups.isEmpty else {
            NicheCEFRuntime.removeShields()
            status = .off
            credits = []
            NicheLog.note("Shields off")
            return
        }
        let languages = Locale.preferredLanguages
        work.async {
            guard let main = Self.pack(ShieldsUpdate.mainPack) else {
                DispatchQueue.main.async {
                    let me = ShieldsService.shared
                    guard me.generation == generation else { return }
                    if !NicheCEFRuntime.shieldsInstalled() { me.status = .waiting }
                    NicheLog.note("Shields: no lists yet")
                }
                return
            }
            var lists = main.lists(for: groups)
            if groups.contains(.regional), let data = try? Data(contentsOf: Self.file(ShieldsUpdate.regionalIndex)),
               let index = try? JSONDecoder().decode(ShieldsRegionalIndex.self, from: data) {
                for entry in index.wanted(languages: languages) {
                    if let pack = Self.pack(ShieldsUpdate.regionalPack(entry.id)) { lists += pack.lists.filter { $0.group == .regional } }
                }
            }
            // The optional lists switched on, each from its own pack. One whose pack isn't here
            // yet is left out until it arrives.
            var pending: Set<String> = []
            for id in extras.sorted() {
                if let pack = Self.pack(ShieldsUpdate.extraPack(id)) { lists += pack.lists } else { pending.insert(id) }
            }
            let build = NicheShieldsBuild()
            for list in lists { build.addList(list.text, group: list.group.number, trusted: list.trusted) }
            build.addResources(main.scriptlets, forPages: true)
            build.addResources(main.redirects, forPages: false)
            let started = Date()
            let rules = build.install()
            let took = Date().timeIntervalSince(started)
            let credits = lists.map { Credit(id: $0.id, title: $0.title, group: $0.group, licence: $0.licence, homepage: $0.homepage) }
            DispatchQueue.main.async {
                let me = ShieldsService.shared
                guard me.generation == generation else { return }
                me.status = .ready(rules: rules)
                me.credits = credits
                me.built = main.built
                me.extrasPending = pending
                NicheLog.note("Shields ready: \(lists.count) lists, \(rules) rules, groups \(groups.map(\.rawValue).sorted().joined(separator: "+")), built in \(Int(took * 1000)) ms")
            }
        }
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
        guard let source = Self.source, !checking, !groups.isEmpty else { return }
        checking = true
        state.lastAttempt = Date()
        stateFile.save(state)
        let wantsRegional = groups.contains(.regional), languages = Locale.preferredLanguages, extras = extras
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
                if didChange || !NicheCEFRuntime.shieldsInstalled() || !me.extrasPending.isEmpty { me.rebuild() }
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
