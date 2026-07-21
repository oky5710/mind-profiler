extension Comparable {
    // 여러 화면에서 `min(max(x, lo), hi)` 형태로 반복되던 클램프를 하나로 모았다.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
