import Foundation

/// The clock behind every decision Niche makes from time: auto-archive, tab sleep, live folder
/// expiry, the command file poll. The app runs on `LiveScheduler`; a test host passes a manual
/// one and advances it, so a 30-minute timer runs in a millisecond (Tests/Support/ManualScheduler).
/// Animation and hover delays stay on Timer: they perform, they don't decide.
@MainActor
protocol Scheduler: AnyObject {
    var now: Date { get }
    @discardableResult func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
    @discardableResult func every(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
}

/// Cancels the work it came from; letting it go does not.
@MainActor
final class ScheduledWork {
    private var onCancel: (() -> Void)?
    private(set) var isCancelled = false
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
        onCancel = nil
    }
}

@MainActor
final class LiveScheduler: Scheduler {
    static let shared = LiveScheduler()

    var now: Date { Date() }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        timer(delay, repeats: false, work)
    }

    func every(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        timer(interval, repeats: true, work)
    }

    private func timer(_ interval: TimeInterval, repeats: Bool, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        var timer: Timer?
        let handle = ScheduledWork {
            timer?.invalidate()
            timer = nil
        }
        // The timer keeps the handle, so work whose handle the caller let go still runs (it
        // didn't until 18 Nov 2026: the handle was held weakly here and gone before the timer
        // fired). A fire already queued on the main actor when the work is cancelled does not run.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in
                if !handle.isCancelled { work() }
                // Work that runs once is over: the timer lets go of the handle, and the handle of it.
                if !repeats { timer = nil }
            }
        }
        return handle
    }
}
