import AppKit
import NicheCEF
import Observation
import QuickLookThumbnailing

/// Finished downloads, newest last, for the list Arc shows when you hover the Library
/// button (its downloads tray) and on Library ▸ Downloads. Kept in downloads.json; files deleted
/// since drop out. Downloads still running, and ones that failed or were cancelled, are listed
/// in both too (`live`, not saved): Arc shows progress and failures there, not in a toast. Which
/// rows each list shows is `DownloadList` (NicheCore).
@MainActor
@Observable
final class DownloadHistory {
    static let shared = DownloadHistory()

    typealias Entry = DownloadList.Entry
    typealias Live = DownloadList.Live
    typealias Listed = DownloadList.Listed

    /// Arc 1.170 listed every recent download it still had on disk (four, oldest at the
    /// top); how many it shows at most was not observed.
    static let listLimit = 5

    private(set) var entries: [Entry]
    /// Quick Look thumbnails by path, made on demand.
    private(set) var thumbnails: [String: NSImage] = [:]
    @ObservationIgnored private let file = JSONStore<[Entry]>("downloads.json")
    @ObservationIgnored private var loading: Set<String> = []

    private init() {
        entries = file.load(or: { [] })
    }

    private(set) var live: [Live] = []

    /// The hover list: newest downloads, oldest first: files still on disk, and running, failed
    /// or cancelled ones.
    var recent: [Listed] {
        DownloadList.tray(entries: entries, live: live, limit: Self.listLimit) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Library ▸ Downloads: every download, newest first, running ones included (#245).
    func library(query: String) -> [Listed] {
        DownloadList.library(entries: entries, live: live, query: query) { FileManager.default.fileExists(atPath: $0) }
    }

    var hasRunningDownloads: Bool { live.contains(where: \.running) }

    /// Chromium's report on a download: running ones update their row, a finished one leaves for
    /// `add(path:)`, a failed or cancelled one stays listed for this session.
    /// `danger` and `blocked`: what Chromium decided about its safety (DownloadDanger); `partPath`:
    /// where the bytes are while it runs.
    func report(id: UInt32, name: String, path: String, url: String = "", received: Int64, total: Int64, percent: Int,
                complete: Bool, cancelled: Bool, failed: Bool, paused: Bool = false, danger: DownloadDanger? = nil,
                blocked: Bool = false, partPath: String = "", now: Date = Date()) {
        if complete {
            live.removeAll { $0.id == id }
            return
        }
        // A row taken off the list (Remove from List, Clear) stays off it: Chromium can report an
        // ended download once more.
        guard !dismissed.contains(id) else { return }
        var l = live.first { $0.id == id } ?? Live(id: id, name: name, path: path, started: now, received: received, total: total,
                                                    percent: percent, updated: now)
        l.take(name: name, path: path, url: url, received: received, total: total, percent: percent,
               failed: failed, cancelled: cancelled, paused: paused, now: now, danger: danger, blocked: blocked, partPath: partPath)
        if let i = live.firstIndex(where: { $0.id == id }) { live[i] = l } else { live.append(l) }
    }

    /// `remembered` false for a download in an incognito window: listed until Niche quits, never
    /// written to downloads.json.
    @discardableResult
    func add(path: String, profile: String? = nil, url: String? = nil, remembered: Bool = true) -> Entry {
        let entry = Entry(id: UUID(), path: path, date: Date(), profile: profile, url: url.flatMap { $0.isEmpty ? nil : $0 })
        if !remembered { offRecord.insert(entry.id) }
        entries = DownloadList.adding(entry, to: entries)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        save()
        return entry
    }

    /// Entries of incognito windows: in the list this run, not in the file.
    @ObservationIgnored private var offRecord: Set<UUID> = []

    /// The last incognito window closed: what was downloaded in them leaves the list (the files
    /// stay where they were saved).
    func forgetOffRecord() {
        guard !offRecord.isEmpty else { return }
        entries.removeAll { offRecord.contains($0.id) }
        offRecord = []
    }

    private func save() {
        file.save(offRecord.isEmpty ? entries : entries.filter { !offRecord.contains($0.id) })
    }

    // MARK: Acting on a download

    /// Live rows taken off the list this run.
    @ObservationIgnored private var dismissed: Set<UInt32> = []
    /// How long Chromium gets to pick an interrupted download up again before Try Again starts it
    /// over: it answers within a report or two, or not at all.
    private static let resumeGrace: TimeInterval = 2

    var canClear: Bool {
        DownloadList.canClear(entries: entries, live: live) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Clear Downloads: finished, failed and cancelled rows leave the list; files stay on disk and
    /// a download still running or paused stays listed.
    func clear() {
        dismissed.formUnion(live.filter { !$0.running }.map(\.id))
        (entries, live) = DownloadList.cleared(entries: entries, live: live)
        save()
    }

    /// A row's button or menu row (`DownloadAction`); what each row offers is decided there.
    func perform(_ action: DownloadAction, on listed: Listed) {
        // The action and the kind of row only, never the file or its address: scenarios wait for this.
        NicheLog.note("Download \(action.rawValue) on a \(listed.state.word) row")
        switch (action, listed) {
        case (.pause, .live(let l)):
            guard NicheCEFRuntime.pauseDownload(l.id) else { return }
            update(l.id) { $0.paused = true; $0.bytesPerSecond = nil; $0.sampleAt = .distantPast }
        case (.resume, .live(let l)):
            guard NicheCEFRuntime.resumeDownload(l.id) else { return }
            update(l.id) { $0.paused = false }
        case (.cancel, .live(let l)):
            // Chromium reports the cancel back; a download it no longer reports on ends here.
            NicheCEFRuntime.cancelDownload(l.id)
            update(l.id) { $0.cancelled = true; $0.paused = false }
        case (.retry, .live(let l)):
            retry(l)
        case (.keep, .live(let l)):
            keep(l)
        case (.discard, .live(let l)):
            // Chrome's Delete: Chromium deletes what it got under its temporary name.
            NicheCEFRuntime.cancelDownload(l.id)
            dismissed.insert(l.id)
            live.removeAll { $0.id == l.id }
        case (.remove, .live(let l)):
            // A failed download Chromium still holds, with the part of the file it got: let go of both.
            NicheCEFRuntime.cancelDownload(l.id)
            discardPart(of: l)
            dismissed.insert(l.id)
            live.removeAll { $0.id == l.id }
        case (.remove, .finished(let e)):
            entries.removeAll { $0.id == e.id }
            save()
        case (.moveToTrash, .finished(let e)):
            let id = e.id
            NSWorkspace.shared.recycle([URL(fileURLWithPath: e.path)]) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self, error == nil else { return }
                    self.entries.removeAll { $0.id == id }
                    self.save()
                }
            }
        case (.open, .finished(let e)):
            NSWorkspace.shared.open(URL(fileURLWithPath: e.path))
        case (.showInFinder, .finished(let e)):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)])
        case (.copyFile, .finished(let e)):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([URL(fileURLWithPath: e.path) as NSURL])
        case (.copyLink, _):
            guard let link = listed.link else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        default:
            break
        }
    }

    /// Keep a download Chromium held. One Safe Browsing knows to be dangerous asks first, as Chrome
    /// does; the others are kept at once. The row carries on as a download once Chromium says so.
    private func keep(_ l: Live) {
        guard let danger = l.danger else { return }
        if danger.isKnownBad, (confirmKeep?(l.name) ?? true) == false { return }
        // The row carries on once Chromium reports the download kept (Niche.download says no danger).
        if !NicheCEFRuntime.keepDownload(l.id) { NicheLog.note("Download keep: no page of its profile to ask") }
    }

    /// Asks whether to keep a file Safe Browsing knows to be dangerous (true to keep). Set by the app;
    /// a scenario can answer without a panel (`niche://debug?downloadKeepAnswer=`).
    @ObservationIgnored var confirmKeep: ((String) -> Bool)? = { name in
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Keep “\(name)”?"
        alert.informativeText = "Safe Browsing knows this file to be dangerous. It can harm your Mac or steal your information."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Keep Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func update(_ id: UInt32, _ change: (inout Live) -> Void) {
        guard let i = live.firstIndex(where: { $0.id == id }) else { return }
        change(&live[i])
    }

    /// Try Again: an interrupted download carries on from the bytes it has when Chromium can pick
    /// it up; one it can't, and a cancelled one, starts over as a new download.
    private func retry(_ l: Live) {
        guard l.failed, NicheCEFRuntime.resumeDownload(l.id) else { return startOver(l) }
        NicheLog.note("Download retry: asked Chromium to resume")
        let asked = Date()
        update(l.id) { $0.failed = false; $0.updated = asked; $0.sampleAt = .distantPast }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeGrace) { [weak self] in
            // No report since: Chromium couldn't resume it.
            guard let self, let now = self.live.first(where: { $0.id == l.id }), now.updated == asked else { return }
            self.startOver(now)
        }
    }

    /// The part of a file a failed download left behind goes to the Trash when its row is removed
    /// or it starts over (Chromium keeps it for a resume that is no longer coming). Never a
    /// whole file: only one that stopped short of its size.
    private func discardPart(of l: Live) {
        // The bytes are under their own name while it runs (a .crdownload); never the file it was
        // going to be, which a finished download Chromium went quiet about can be.
        let part = l.partPath
        guard !part.isEmpty, part != l.path, l.total <= 0 || l.received < l.total, FileManager.default.fileExists(atPath: part) else { return }
        NSWorkspace.shared.recycle([URL(fileURLWithPath: part)]) { _, _ in }
    }

    private func startOver(_ l: Live) {
        let started = NicheCEFRuntime.restartDownload(l.id)
        NicheLog.note("Download retry: \(started ? "started over as a new download" : "no page left to start it in")")
        if started {
            // The one it replaces is let go of, with the part of the file it got.
            NicheCEFRuntime.cancelDownload(l.id)
            discardPart(of: l)
            dismissed.insert(l.id)
            live.removeAll { $0.id == l.id }
        } else {
            update(l.id) { $0.failed = true }
        }
    }

    /// A renamed (or reverted) file keeps its place in the list.
    func move(from old: String, to new: String) {
        guard let i = entries.lastIndex(where: { $0.path == old }) else { return }
        entries[i].path = new
        thumbnails[new] = thumbnails.removeValue(forKey: old)
        save()
    }

    func thumbnail(for path: String) -> NSImage? {
        if let image = thumbnails[path] { return image }
        loadThumbnail(path)
        return nil
    }

    private func loadThumbnail(_ path: String) {
        guard !loading.contains(path) else { return }
        loading.insert(path)
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 40, height: 40),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(path)
                self.thumbnails[path] = image ?? NSWorkspace.shared.icon(forFile: path)
            }
        }
    }
}
