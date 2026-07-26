# Architecture

## 레이어

- **Views** — SwiftUI 화면/컴포넌트. 비즈니스 로직 없이 ViewModel이 노출한 상태만 그림.
- **ViewModels** — `@Observable` + `@MainActor` 클래스. 화면 하나당 하나. `async/await`로 Service를 호출하고 결과를 `@State`로 노출.
- **Models** — API 요청/응답 Codable 구조체 (`ExamModels`, `MoodModels`, `CoffeeModels`, `AuthModels` 등).
- **Services** — 외부 세계(백엔드 API, HealthKit, EventKit, Keychain, Google Sign-In, Pixabay)와의 실제 통신. ViewModel은 Service만 알고 URLSession/HealthKit/EventKit 등을 직접 다루지 않음.
- **Components** — 여러 화면에서 재사용하는 View/디자인 토큰 (`Theme.swift`, `HeartLoader`, `SleepDetailPanel`).

View 파일 하나가 너무 커지면(대략 500줄 이상) `extension`으로 여러 파일에 나눠 담는다 — 새 타입/프로토콜을
만들지 않고 관심사별로만 파일을 쪼갠다 (예: `HRVAnalysisView.swift`의 상태/구성 vs
`HRVAnalysisView+Axes.swift`의 축·스크롤 오버레이 vs `HRVAnalysisView+Charts.swift`의 차트 정의).
이렇게 나눈 멤버는 `private`가 아니라 기본 접근 수준(internal)으로 둬야 다른 파일의 extension에서 볼 수 있다.

## 데이터 흐름

```
View → ViewModel (async 호출) → Service → APIClient / HealthKitService / KeychainService
                ↑                                    │
                └──────────── @Observable 상태 갱신 ───┘
```

## 백엔드

- NestJS 백엔드(`mind-chart-backend`)와 Postgres(Neon) DB를 그대로 공유한다. 백엔드는 이 앱을 위해 변경하지 않는다.
- 인증은 `POST /auth/google`로 Google idToken을 보내고, 백엔드가 발급한 JWT를 이후 모든 요청에 `Authorization: Bearer`로 사용한다. 자세한 엔드포인트는 [api.md](api.md) 참고.
- JWT는 Keychain(`KeychainService`)에 저장하고, 앱 재실행 시 저장된 토큰 유무로 로그인 상태를 판단한다.

## HealthKit

- 네이티브 전환의 핵심 이유. mind-record 웹은 iOS 단축어로 HealthKit 데이터를 간접적으로만 받았지만, 이 앱은 `HealthKitService`로 HRV(SDNN)/수면/운동/원시 박동 데이터를 **직접** 읽는다.
- rMSSD는 HealthKit이 직접 주지 않아, SDNN 측정마다 같이 기록되는 원시 박동 시리즈(`HKHeartbeatSeriesSample`)에서 `HealthKitService`가 직접 계산한다 — 자세한 내용은 [features.md](features.md)의 rMSSD 항목 참고.
- HRV(SDNN)는 HealthKit 제약상 `HKSeriesType.heartbeat()`(원시 박동) 읽기 권한과 반드시 같이 요청해야 해서
  (안 하면 앱이 즉시 크래시) 읽기는 하지만, 화면에서는 rMSSD와의 값 차이를 참고만 하도록 옅게(시간별 모드,
  `Theme.systemGray4`) 보여주기만 한다.
- HealthKit 데이터는 백엔드에 저장하지 않고, 매번 기기에서 읽어와 화면에서만 사용한다 (검사 기록(SDNN·rMSSD 등)·기분·커피 등 사용자가 직접 입력하는 기록만 백엔드에 저장).
- 애플 워치가 Health 앱에 보여주는 "수면 점수"는 HealthKit 공개 API로 노출되지 않는다 — 수면 상세
  패널(`SleepDetailPanel`)에 보이는 추정 점수는 애플이 공개한 가중치 구성을 흉내 낸 자체 계산값이다
  (`SleepAnalysisService`). 자세한 내용은 [features.md](features.md) 참고.
- 원시 HealthKit 샘플(수면 단계, rMSSD 등)을 화면에 쓸 모양으로 가공하는 순수 계산 로직은
  `SleepAnalysisService`(수면 구간·추정 점수)와 `HRVStatistics`(중앙값·일별 중앙값·Pearson 상관계수)로
  분리해뒀다 — "오늘의 패턴"과 "보고서" 화면이 이 계산을 그대로 공유해서 쓴다.

## EventKit

- 애플 캘린더 연동은 `CalendarEventService`가 `EKEventStore`로 기기의 모든 캘린더에서 직접 읽는다 —
  HealthKit과 마찬가지로 백엔드를 거치지 않고 기기에서만 읽어와 화면에 쓴다(저장 안 함).
- `EKEventStore.requestFullAccessToEvents()`로 전체 접근 권한을 요청한다 (`NSCalendarsFullAccessUsageDescription`
  필요). 조회 기간은 HealthKit 쿼리와 달리 반드시 명시해야 한다 — `fetchEvents(start:end:)`에 안 넘기면
  "오늘의 패턴" 화면이 쓰는 기본값(과거 1년~미래 3개월)으로 조회하고, 보고서처럼 임의의 과거 기간을
  분석할 때는 그 기간을 그대로 넘긴다(안 그러면 1년보다 오래된 기간엔 일정이 조용히 누락된다).
- 공휴일/휴가는 EventKit에 전용 타입이 없어서, 일정이 속한 캘린더 이름으로 구분한다("Holiday"/"공휴일",
  "휴가"/"vacation" 포함 여부) — `CalendarEventCategory`.

## 화면 ↔ 코드 매핑

| 화면(PRD.md) | View | ViewModel |
|---|---|---|
| 진입 화면 | `Views/Home/HomeView.swift` | `HomeViewModel` |
| 달력보기 | `Views/Calendar/CalendarView.swift` | `CalendarViewModel` |
| 오늘의 패턴 | `Views/HRVAnalysis/HRVAnalysisView.swift` (+ `HRVAnalysisView+Axes.swift`, `HRVAnalysisView+Charts.swift`) | `HRVAnalysisViewModel` |
| 보고서 | `Views/Report/ReportView.swift` | `ReportViewModel` |
| 설정 (SDNN vs rMSSD 분석) | `Views/Settings/SettingsView.swift` | `HRVCorrelationViewModel` |

PRD에는 없던 "보고서" 화면은 정신과 진료용 요약 보고서로, 원래 있던 "나의 Trend"(통계, 기분·커피
막대그래프만 있던 화면)를 대체했다 — 자세한 내용은 [features.md](features.md) 참고.

아직 포팅되지 않은 화면/기능은 [features.md](features.md) 참고.
