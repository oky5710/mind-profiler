# UI Style

색상 토큰 자체는 [design-system.md](design-system.md) 참고. 이 문서는 레이아웃/타이포/차트 그리는 방식의 규칙.

## 공통

- 화면 최상단은 `NavigationStack` + `.navigationBarTitleDisplayMode(.inline)`.
- 로딩 상태는 `ProgressView()`보다 `HeartLoader`(하트 박동 애니메이션)를 우선 사용 — 로딩이 오래 걸릴 수 있는
  화면(HealthKit/네트워크 동시 로딩 등)에서 통일된 느낌을 준다.
- 에러 메시지는 화면을 막지 않고 `.font(.footnote).foregroundStyle(.red)`로 관련 콘텐츠 위/아래에 노출한다
  (AGENTS.md 규칙: 에러는 숨기지 않고 UI에 노출).

## 차트 (Swift Charts)

- **여러 지표를 겹쳐 그리지 않는다** — y축 단위가 다른 데이터(예: HRV 값 vs 수면/운동 구간)는 반드시
  별도의 `Chart` 인스턴스로 분리한다. 하나의 y축에 억지로 맞추면 가짜 눈금 값이 생긴다.
- **여러 Chart를 세로로 쌓아 하나처럼 보이게 할 때, x축 눈금 위치는 반드시 동일해야 한다.** Swift Charts의
  자동 눈금 계산에 맡기면 차트마다 다른 위치에 그려질 수 있으므로, 눈금 `Date` 배열을 직접 계산해서
  모든 차트의 `.chartXAxis`에 동일하게 적용한다 (`HRVAnalysisView.xAxisTickDates` 참고).
- 그리드 라인(`AxisGridLine`)은 옅게(`.gray.opacity(0.25)`), 눈금 틱(`AxisTick`)은 그보다
  진하게(`.gray.opacity(0.85)`) — 그리드보다 축 자체가 도드라져야 읽기 편하다.
- 축 라벨 폰트는 `.font(.system(size: 9))`로 작게, 날짜가 바뀌는 지점(자정)은 `.bold()`로 강조.
- y축은 0부터 시작하고 고정 간격(예: 50 단위)으로 그린다 — 데이터 min/max에 맞춰 축을 움직이면
  값이 실제보다 과장되어 보인다.
- 가로 스크롤은 Swift Charts 내장 `.chartScrollableAxes`가 아니라 `DragGesture` +
  `.chartOverlay`로 직접 구현한다 (`dragToScrollOverlay` 참고) — 내장 스크롤은 이 조합(다중 Chart,
  커스텀 x축)에서 반응하지 않았다. 스크롤은 "지금 이후"로는 이동하지 못하게 클램프한다.

## 인터랙션

- 간편 입력(홈 화면의 기분/커피 등)은 탭 한 번으로 끝나야 한다 — 폼을 열지 않고 바로 기록.
- 상세 입력(캘린더 날짜 탭)은 bottom sheet로 열어서 유형 선택 → 폼 순서로 진행.
