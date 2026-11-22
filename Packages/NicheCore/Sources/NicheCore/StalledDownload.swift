import Foundation

/// A download Chromium has gone quiet about: it stops reporting once the tab that started it is gone,
/// and the download carries on or ends silently. Its row reads the disk instead. The bytes are under
/// their own name while it runs (`Live.partPath`: `<name>.crdownload`, or Chromium's
/// "Unconfirmed <n>.crdownload" while it checks the file), never under the file's own name.
public enum StalledDownload {
    public enum Outcome: Equatable, Sendable { case running, complete, cancelled }

    /// How long Chromium must have said nothing before the disk is read. Finishing has quiet spells:
    /// Chromium renames the file and then has macOS mark it as downloaded (quarantine) before it
    /// reports it done, which took over 5 s on a busy Mac; at 5 s the row was finished from the disk
    /// first and lost its address (22 Nov 2026).
    public static let quietFor: TimeInterval = 20

    /// `exists` and `size` read the disk (size nil when there is no file).
    public static func outcome(_ l: DownloadList.Live, exists: (String) -> Bool, size: (String) -> Int64?) -> Outcome {
        let part = l.partPath.isEmpty ? l.path + ".crdownload" : l.partPath
        if exists(part) { return .running }
        guard exists(l.path), let bytes = size(l.path) else { return .cancelled }
        return l.total > 0 && bytes >= l.total ? .complete : .running
    }
}
