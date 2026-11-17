import Foundation

/// What can be done to a download from its row: the buttons a row shows under the pointer and the
/// rows of its menu. Which ones a download offers depends on where it stands (`DownloadRow.State`).
public enum DownloadAction: String, CaseIterable, Sendable {
    case pause, resume, cancel, retry, open, showInFinder, copyFile, copyLink, remove, moveToTrash

    public var title: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case .cancel: "Cancel Download"
        case .retry: "Try Again"
        case .open: "Open"
        case .showInFinder: "Show in Finder"
        case .copyFile: "Copy"
        case .copyLink: "Copy Download Link"
        case .remove: "Remove from List"
        case .moveToTrash: "Move to Trash"
        }
    }

    /// The SF Symbol on the row's button.
    public var symbol: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .cancel, .remove: "xmark"
        case .retry: "arrow.clockwise"
        case .open: "arrow.up.forward.app"
        case .showInFinder: "magnifyingglass"
        case .copyFile: "doc.on.doc"
        case .copyLink: "link"
        case .moveToTrash: "trash"
        }
    }

    /// The two buttons a row shows under the pointer: what one most wants at that point, and the
    /// way out. A running download can be held or stopped, a stopped one tried again or dismissed,
    /// a finished one found in Finder or taken off the list.
    public static func buttons(for state: DownloadRow.State) -> [DownloadAction] {
        switch state {
        case .downloading: [.pause, .cancel]
        case .paused: [.resume, .cancel]
        case .failed, .cancelled: [.retry, .remove]
        case .finished: [.showInFinder, .remove]
        }
    }

    /// The row's menu, in groups (a separator between each). Copy Download Link needs the address;
    /// a download that never got one (or was saved before Niche kept it) leaves it out.
    public static func menu(for state: DownloadRow.State, hasLink: Bool) -> [[DownloadAction]] {
        let link: [DownloadAction] = hasLink ? [.copyLink] : []
        let groups: [[DownloadAction]]
        switch state {
        case .downloading: groups = [[.pause, .cancel], link]
        case .paused: groups = [[.resume, .cancel], link]
        case .failed, .cancelled: groups = [[.retry], link, [.remove]]
        case .finished: groups = [[.open, .showInFinder], [.copyFile] + link, [.remove, .moveToTrash]]
        }
        return groups.filter { !$0.isEmpty }
    }
}
