# Design System

디자인 토큰(색상 등)의 단일 소스는 `Components/Theme.swift`다. 화면에서 색을 직접
`Color(red:green:blue:)`로 하드코딩하지 않고 `Theme.xxx`를 참조한다.

## 색상

| 토큰 | 값 | 의미 |
|---|---|---|
| `Theme.heart` | `#F94F63` | 로딩 인디케이터(`HeartLoader`) 하트 색 |
| `Theme.mood` | `#f43f5e` | 기분 막대그래프 |
| `Theme.coffee` | `#92400e` | 커피 막대그래프 |
| `Theme.hrvLine` | `#3b82f6` | HRV(심박변이) 라인 차트 |
| `Theme.sdnn` | `#22c55e` | 검사 SDNN 포인트(세모 마커) |
| `Theme.exercise` | `#16a34a` | 운동 Gantt 레인 |
| `Theme.sleep` | `#6366f1` | 수면 Gantt 레인 |

같은 항목(기분/커피/HRV/수면/운동)을 나타내는 색은 mind-record 웹 버전(`app/hrv-analysis/page.tsx`,
`app/chart`)에서 쓰던 색을 그대로 이식한 것 — 웹과 네이티브에서 같은 지표는 같은 색으로 보이게 유지한다.

## 원칙

- **새 색이 필요하면 `Theme.swift`에 먼저 추가**하고, 화면에서는 토큰만 참조한다.
- 같은 지표를 여러 화면에서 그릴 때(예: 기분은 홈/통계 양쪽에서 다룸) 반드시 같은 `Theme` 토큰을 쓴다.
- 임시/1회성 색(예: 에러 텍스트의 `.red`, placeholder의 `.secondary`)은 시스템 시맨틱 컬러를 그대로 쓰고
  `Theme`에 넣지 않는다 — `Theme`는 "이 앱만의 지표 색"을 위한 것.

세부 레이아웃/타이포/차트 스타일 규칙은 [ui-style.md](ui-style.md) 참고.
