# Design System

## 철학

- 귀엽지만 유치하지 않게.
- 사용자가 불안장애·우울증을 겪는 사람일 수 있다는 전제로, 색과 이미지는 차분하고 편안하게.
- 그럼에도 재미 요소를 느낄 수 있게.
- 나이·장애·교육 수준에 관계없이 누구나 쉽게 쓸 수 있게.

## 색상

디자인 토큰(색상)의 단일 소스는 `Components/Theme.swift`다. 화면에서 색을 직접
`Color(red:green:blue:)`로 하드코딩하지 않고 `Theme.xxx`를 참조한다.

지표 색 팔레트는 **Radix UI Colors**(radix-ui.com/colors)로 통일되어 있다 — 원래 mind-record 웹에서
이식한 Tailwind 계열 하드코딩 값이었지만, 색상 거리가 가장 가까운 Radix 스케일 단계로 전부 교체했다.
새 지표 색이 필요하면 임의로 hex를 고르지 말고 Radix 스케일에서 고른다 (보통 "solid" 단계인 9,
필요하면 10/11도 사용 — 아래 표의 실제 사용례 참고).

| 토큰 | 값 (Radix 스케일) | 의미 |
|---|---|---|
| `Theme.heart` | `red-9` `#e5484d` | 로딩 인디케이터(`HeartLoader`) 하트 색 (`Theme.holiday`와 같은 값 — 동시에 화면에 안 나와서 무관) |
| `Theme.mood` | `amber-10` `#ffba18` | 기분 막대그래프 |
| `Theme.coffee` | `amber-11` `#ab6400` | 커피 막대그래프 |
| `Theme.rmssd` | `violet-9` `#6e56cf` | rMSSD 라인 차트 및 월별 막대 차트 (HealthKit 원시 박동에서 계산) |
| `Theme.examRmssd` | `green-9` `#30a46c` | 검사(병원) rMSSD 포인트(세모 마커) |
| `Theme.exercise` | `green-10` `#2b9a66` | 운동 Gantt 레인 |
| `Theme.sleep` | `indigo-9` `#3e63dd` | 수면 Gantt 레인 |
| `Theme.holiday` | `red-9` `#e5484d` | 오늘의 패턴 — 종일 일정 중 공휴일(캘린더 이름에 "Holiday"/"공휴일" 포함) |
| `Theme.vacation` | `orange-9` `#f76b15` | 오늘의 패턴 — 종일 일정 중 휴가(캘린더 이름에 "휴가"/"vacation" 포함) |

일반 캘린더 일정(공휴일/휴가가 아닌 것)과 SDNN 참고 라인은 지표 전용 색이 아니라 Apple 시스템 색
(`Theme.systemBlue`, `Theme.systemGray4`)을 쓴다 — 아래 "시스템 색상 팔레트" 참고.

### 수면 단계 도넛 팔레트

수면 상세 패널의 단계별(코어/깊은/렘/미상) 도넛 차트는 위 지표 색과 별개로 `Theme.sleepStageDeep`/
`sleepStageREM`/`sleepStageCore`/`sleepStageUnspecified`(블루/그린/마젠타/옐로)를 쓴다. 이 4개는
Radix 스케일이 아니라 `dataviz` 스킬의 검증된 카테고리컬 팔레트에서 순서 그대로 가져온 것이다 —
서로 다른 지표와 안 겹치는 새 카테고리 색이 필요했고, 이 팔레트는 4개 전 쌍 CVD 검증(`validate_palette.js`)을
이미 통과해서다. 각성(수면 중 깬 시간)은 단계가 아니라 "나머지"라 무채색(`.gray`)으로 별도 처리한다.

### 시스템 색상 팔레트

위 지표 색과 별개로, `Theme.systemRed`~`Theme.systemGray6`(Apple HIG 표준 색상 12개 + 회색조 6단계)도
`Theme.swift`에 있다. `Color.red`처럼 SwiftUI가 기본 제공하는 이름과 값은 같지만, `systemGray2`~`6`처럼
SwiftUI에 없는 회색조 단계까지 라이트/다크/대비 높음 4가지 조합 전부 필요해서 UIKit 없이
`Assets.xcassets/SystemColors` 컬러셋으로 등록해 참조한다. 지표 색이 아니라 범용 팔레트라
"임시/1회성 색은 Theme에 넣지 않는다" 원칙의 예외.

### 빨강 사용 규칙

**빨강은 "문제/경고"를 나타낼 때만 쓴다** (예: 에러 메시지, 수면 5시간 미만 강조).
문제를 나타내는 용도가 아니면 빨강·장미색 계열을 쓰지 않는다.

- `Theme.mood`는 원래 장미색이었지만 "기분이 나쁘다"는 문제가 아니라 그냥 지표 색이므로
  이 규칙에 따라 앰버 계열(`amber-10`)로 교체했다.
- `Theme.heart`(로딩 하트)는 **예외**로 그대로 둔다 — 로딩 인디케이터는 지표 색이 아니라
  하트 모양 자체의 고유 색으로 취급한다.
- `Theme.holiday`(공휴일)도 **예외**다 — "공휴일"은 문제/경고가 아니라 캘린더 관례상 빨강으로
  표기하는 게 자연스러운 카테고리 색이라 이 규칙을 적용하지 않는다.
- 새로 색을 추가할 때: 그 색이 "정상 상태를 나타내는 지표 색"이면 빨강 계열을 피하고, "경고/이상치"를
  나타내는 색이면 빨강 계열을 쓴다.

## 원칙

- **새 색이 필요하면 `Theme.swift`에 먼저 추가**하고, 화면에서는 토큰만 참조한다.
- 같은 지표를 여러 화면에서 그릴 때(예: 기분은 홈/통계 양쪽에서 다룸) 반드시 같은 `Theme` 토큰을 쓴다.
- 임시/1회성 색(예: 에러 텍스트의 `.red`, placeholder의 `.secondary`)은 시스템 시맨틱 컬러를 그대로 쓰고
  `Theme`에 넣지 않는다 — `Theme`는 "이 앱만의 지표 색"을 위한 것.

세부 레이아웃/타이포/차트 스타일 규칙은 [ui-style.md](ui-style.md) 참고.
