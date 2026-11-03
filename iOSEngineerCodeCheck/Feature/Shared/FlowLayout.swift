import SwiftUI

/// 子 View を左から右へ並べ、幅に収まらなければ次の行へ送るレイアウト（ラベル単位で折り返す）。
///
/// 一覧の補助行（言語・Star 数・最終更新）のように短いラベルが複数並ぶ場所で使う。`HStack` では幅が足りないとき
/// 各ラベルが細い列に押し込まれて単語の途中で折り返される。幅より広いラベルは 1 行を占め、その幅で折り返す。
/// アクセシビリティサイズでは各ラベルが自然に 1 行ずつになるので、サイズで切り替える必要がない。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let rowWidths = rows.map { row in
            row.map(\.size.width).reduce(0, +) + CGFloat(max(row.count - 1, 0)) * horizontalSpacing
        }
        let rowHeights = rows.map { row in row.map(\.size.height).max() ?? 0 }
        return CGSize(
            width: rowWidths.max() ?? 0,
            height: rowHeights.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: proposal.width ?? bounds.width) {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    /// 各子 View を最大幅で計測し（幅を超えるものはその幅で折り返した大きさになる）、行に振り分ける。
    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [[Item]] {
        var rows: [[Item]] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let needed = current.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width
            if !current.isEmpty && needed > maxWidth {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(Item(index: index, size: size))
            currentWidth = current.count == 1 ? size.width : currentWidth + horizontalSpacing + size.width
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
