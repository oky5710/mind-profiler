# Architecture

## 레이어

- **Views** — SwiftUI 화면/컴포넌트. 비즈니스 로직 없이 ViewModel이 노출한 상태만 그림.
- **ViewModels** — `@Observable` + `@MainActor` 클래스. 화면 하나당 하나. `async/await`로 Service를 호출하고 결과를 `@State`로 노출.
- **Models** — API 요청/응답 Codable 구조체 (`ExamModels`, `MoodModels`, `CoffeeModels`, `AuthModels` 등).
- **Services** — 외부 세계(백엔드 API, HealthKit, Keychain, Google Sign-In, Pixabay)와의 실제 통신. ViewModel은 Service만 알고 URLSession/HealthKit 등을 직접 다루지 않음.
- **Components** — 여러 화면에서 재사용하는 View/디자인 토큰 (`Theme.swift`, `HeartLoader`, `BarChartCard`).

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

- 네이티브 전환의 핵심 이유. mind-record 웹은 iOS 단축어로 HealthKit 데이터를 간접적으로만 받았지만, 이 앱은 `HealthKitService`로 HRV/수면/운동 데이터를 **직접** 읽는다.
- HealthKit 데이터는 백엔드에 저장하지 않고, 매번 기기에서 읽어와 화면에서만 사용한다 (검사 SDNN/기분/커피 등 사용자가 직접 입력하는 기록만 백엔드에 저장).

## 화면 ↔ 코드 매핑

| 화면(PRD.md) | View | ViewModel |
|---|---|---|
| 진입 화면 | `Views/Home/HomeView.swift` | `HomeViewModel` |
| 달력보기 | `Views/Calendar/CalendarView.swift` | `CalendarViewModel` |
| 나의 Trend(통계) | `Views/Statistics/StatisticsView.swift` | `StatisticsViewModel` |
| 오늘의 패턴 | `Views/HRVAnalysis/HRVAnalysisView.swift` | `HRVAnalysisViewModel` |

아직 포팅되지 않은 화면/기능은 [features.md](features.md) 참고.
