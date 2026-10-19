import Foundation

/// How wide the pages are for a given window width, so full screen uses the room instead of
/// leaving wide empty margins. At the standard window size the pages look as they always did.
public enum PageLayout {
    public static let standardWindowWidth = 1180.0
    /// The narrowest the page's content column (padding included) is allowed to be.
    public static let minimumContentWidth = 1080.0
    /// A reading limit for very large displays.
    public static let maximumContentWidth = 1680.0
    /// Empty space kept on each side of the content column.
    public static let sideMargin = 50.0

    private static let narrowSideColumn = 194.0
    private static let widestSideColumn = 290.0
    private static let sideColumnGrowth = 0.15

    /// Width of the content column, padding included. It follows the window up to the limit.
    public static func contentWidth(forWindow width: Double) -> Double {
        max(minimumContentWidth, min(width - 2 * sideMargin, maximumContentWidth))
    }

    /// Width of the voice column on Generate. It only widens past the standard window.
    public static func sideColumnWidth(forWindow width: Double) -> Double {
        min(widestSideColumn, narrowSideColumn + max(0, width - standardWindowWidth) * sideColumnGrowth)
    }
}
