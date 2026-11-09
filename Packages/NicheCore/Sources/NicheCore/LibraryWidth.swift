import Foundation

/// The sidebar's width while the Library has it: the tab sidebar's width plus `extra`, which the
/// user sets by dragging the sidebar's edge in the Library (WindowPrefs.libraryExtraWidth), so it
/// grows and shrinks with the tab sidebar.
public enum LibraryWidth {
    public static let defaultExtra = 40.0
    /// The rail (74 pt) and a list that still fits a title.
    public static let minimum = 280.0
    public static let maximum = 720.0

    /// Never narrower than the tab sidebar: the pages under the Library keep the size they have
    /// beside that one, and a narrower Library would leave a gap beside them.
    public static func clamp(_ width: Double, sidebar: Double = 0) -> Double { min(max(width, minimum, sidebar), max(maximum, sidebar)) }

    public static func width(sidebar: Double, extra: Double?) -> Double { clamp(sidebar + max(0, extra ?? defaultExtra), sidebar: sidebar) }

    /// What to remember after the edge was dragged to `width`.
    public static func extra(forDragged width: Double, sidebar: Double) -> Double { clamp(width, sidebar: sidebar) - sidebar }
}
