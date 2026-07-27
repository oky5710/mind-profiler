import SwiftUI

// 캘린더 날짜 칸의 배지들을 가로로 나란히 놓다가, 칸 너비를 넘기면 다음 줄로 줄바꿈한다 —
// HStack은 넘치면 그냥 잘리거나 자식을 찌그러뜨리고, VStack은 매번 한 줄에 하나씩만 놓아서
// 배지가 몇 개든 세로로 계속 길어진다. 정확한 개수만큼 줄바꿈하려면 이 둘로는 안 되고 커스텀
// Layout이 필요하다 — 높이가 칸을 넘는 나머지 줄은 호출부에서 `.clipped()`로 잘라 숨긴다.
struct BadgeFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let isFirstInRow = current.indices.isEmpty
            let widthIfAdded = current.width + (isFirstInRow ? 0 : spacing) + size.width
            if !isFirstInRow && widthIfAdded > maxWidth {
                rows.append(current)
                current = Row()
            }
            let addsToEmptyRow = current.indices.isEmpty
            current.width += (addsToEmptyRow ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
