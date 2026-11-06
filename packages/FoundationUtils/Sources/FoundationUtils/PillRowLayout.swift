import CoreGraphics

public enum PillRowAlignment {
    case left
    case center
    case right
    case justify
}

private let pillHeight: CGFloat = 40.0
private let pillSpacing: CGFloat = 6.0
private let maximumPillsPerRow = 8
// iOS justified rows wrap only at 8 columns; Mac pages can be much narrower.
private let minimumJustifiedColumnWidth: CGFloat = 80.0

/// Frames for equal-width pills filling each row, in the order of the pills.
public func justifiedPillFrames(count: Int, availableWidth: CGFloat, rtl: Bool) -> [CGRect] {
    let columnsThatFit = Int((availableWidth + pillSpacing) / (minimumJustifiedColumnWidth + pillSpacing))
    let columns = max(1, min(maximumPillsPerRow, columnsThatFit))
    var frames: [CGRect] = []
    var y: CGFloat = 0.0
    var index = 0
    while index < count {
        let rowCount = min(columns, count - index)
        let width = (availableWidth - pillSpacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
        for position in 0 ..< rowCount {
            let column = rtl ? rowCount - 1 - position : position
            frames.append(CGRect(x: CGFloat(column) * (width + pillSpacing), y: y, width: width, height: pillHeight))
        }
        y += pillHeight + pillSpacing
        index += rowCount
    }
    return frames
}

/// Frames for pills of the given widths, wrapped when a row is full, in the
/// order of the pills. `.justify` is treated as `.left`.
public func huggingPillFrames(widths: [CGFloat], alignment: PillRowAlignment, availableWidth: CGFloat, rtl: Bool) -> [CGRect] {
    var rows: [[Int]] = []
    var currentRow: [Int] = []
    var currentWidth: CGFloat = 0.0
    for (index, width) in widths.enumerated() {
        let projected = currentWidth + pillSpacing + width
        if !currentRow.isEmpty, projected > availableWidth || currentRow.count >= maximumPillsPerRow {
            rows.append(currentRow)
            currentRow = []
        }
        currentWidth = currentRow.isEmpty ? width : projected
        currentRow.append(index)
    }
    rows.append(currentRow)

    var frames = [CGRect](repeating: .zero, count: widths.count)
    var y: CGFloat = 0.0
    for row in rows {
        let rowWidth = row.reduce(pillSpacing * CGFloat(row.count - 1)) { $0 + widths[$1] }
        let slack = max(0.0, availableWidth - rowWidth)
        var x: CGFloat
        // Left and right mean leading and trailing, so RTL mirrors them.
        switch alignment {
        case .center:
            x = slack / 2.0
        case .right:
            x = rtl ? 0.0 : slack
        case .left, .justify:
            x = rtl ? slack : 0.0
        }
        for index in rtl ? row.reversed() : row {
            frames[index] = CGRect(x: x, y: y, width: widths[index], height: pillHeight)
            x += widths[index] + pillSpacing
        }
        y += pillHeight + pillSpacing
    }
    return frames
}
