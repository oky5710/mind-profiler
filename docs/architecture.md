# Architecture

## 레이어

- **Views** — SwiftUI 화면/컴포넌트. 비즈니스 로직 없이 ViewModel이 노출한 상태만 그림.
- **ViewModels** — `@Observable` + `@MainActor` 클래스. 화면 하나당 하나. `async/await`로 Service를 호출하고 결과를 `@State`로 노출.
- **Models** — API 요청/응답 Codable 구조체 (`ExamModels`, `MoodModels`, `CoffeeModels`, `AuthModels` 등).
- **Services** — 외부 세계(백엔드 API, HealthKit, EventKit, Keychain, Google Sign-In)와 번들 리소스의 실제 접근. ViewModel은 Service만 알고 URLSession/HealthKit/EventKit 등을 직접 다루지 않음. 대부분 상태 없는 enum 네임스페이스지만, `ReminderNotificationService`(`UNUserNotificationCenterDelegate` 구현, 예약된 알림 캐시)와 `RMSSDThresholdMonitorService`(`HKObserverQuery` 참조 보관)는 예외로 class다 — 둘 다 참조 타입으로 뭔가를 계속 들고 있어야 해서다.
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

- NestJS 백엔드(`mind-chart-backend`)와 Postgres(Neon) DB를 공유한다. Google 최초 로그인 시 `User`를
  자동 생성하고 `UserRole` 기본값 `user`를 적용한다. `admin`으로의 승격/강등은 DB에서만 한다 —
  `user`↔`researcher` 전환만 `PATCH /users/:id/role`(admin 전용, 설정 > 사용자 권한 관리)로 가능하다.
- 인증은 `POST /auth/google`로 Google idToken을 보내고, 백엔드가 발급한 JWT를 이후 모든 요청에 `Authorization: Bearer`로 사용한다. 자세한 엔드포인트는 [api.md](api.md) 참고.
- JWT는 Keychain(`KeychainService`)에 저장하고, 앱 재실행 시 저장된 토큰 유무로 로그인 상태를 판단한다.

## HealthKit

- 네이티브 전환의 핵심 이유. mind-record 웹은 iOS 단축어로 HealthKit 데이터를 간접적으로만 받았지만, 이 앱은 `HealthKitService`로 HRV(SDNN)/수면/운동/원시 박동 데이터를 **직접** 읽는다.
- rMSSD는 HealthKit이 직접 주지 않아, SDNN 측정마다 같이 기록되는 원시 박동 시리즈(`HKHeartbeatSeriesSample`)에서 `HealthKitService`가 직접 계산한다 — 자세한 내용은 [features.md](features.md)의 rMSSD 항목 참고.
- HRV(SDNN)는 HealthKit 제약상 `HKSeriesType.heartbeat()`(원시 박동) 읽기 권한과 반드시 같이 요청해야 해서
  (안 하면 앱이 즉시 크래시) 읽기는 하지만, 화면에서는 rMSSD와의 값 차이를 참고만 하도록 옅게(시간별 모드,
  `Theme.systemGray4`) 보여주기만 한다.
- HealthKit 데이터는 백엔드에 저장하지 않는다. 계산 비용이 큰 rMSSD만 기기 내부 SwiftData에
  `RMSSDMeasurement`(측정별 계산 캐시)와 `DailyRMSSDSummary`(날짜·수면·기상 후 오전·오후별 중앙값)로
  저장한다. 저장소는 iCloud/기기 백업에서 제외하고 Data Protection을 적용하며 원시 RR 간격은 보관하지
  않는다. 검사 기록·기분·커피 등 사용자가 직접 입력하는 기존 기록만 백엔드에 저장한다.
- 애플 워치가 Health 앱에 보여주는 "수면 점수"는 HealthKit 공개 API로 노출되지 않는다 — 수면 상세
  패널(`SleepDetailPanel`)에 보이는 추정 점수는 애플이 공개한 가중치 구성을 흉내 낸 자체 계산값이다
  (`SleepAnalysisService`). 자세한 내용은 [features.md](features.md) 참고.
- 원시 HealthKit 샘플(수면 단계, rMSSD 등)을 화면에 쓸 모양으로 가공하는 순수 계산 로직은
  `SleepAnalysisService`(수면 구간·추정 점수)와 `HRVStatistics`(중앙값·일별 중앙값·Pearson 상관계수)로
  분리해뒀다 — "오늘의 패턴"과 "보고서" 화면이 이 계산을 그대로 공유해서 쓴다.
- 겹치거나 맞닿은 시간 구간을 합치는 로직도 `SleepAnalysisService.mergeIntervals`를 공통으로 사용해
  홈 브리핑과 수면 연속성 분석의 각성 시간 계산 기준이 달라지지 않게 한다.

### 로컬 rMSSD 캐시 흐름

```
HealthKit HeartbeatSeries
  → RMSSDLocalStore (UUID별 신규/변경 측정만 계산, 한 윈도우에서 측정값·일별·월별 요약 동시 반환)
  → RMSSDMeasurement
  → DailyRMSSDSummary (신규 측정일·버전 변경일·오늘/어제만 증분 재집계)
  → MonthlyRMSSDSummary (완료된 과거 월의 일별 중앙값 분포를 기기 내부에 저장)
  → HRV Trend / Recovery / 오늘 단서 / 장기 미제 사건 / 보고서
```

- `calculationVersion`은 RR 필터·rMSSD 공식 변경 시 측정 캐시를 다시 계산하기 위한 버전이고,
  `aggregationVersion`은 수면·오전·오후 분류 변경 시 일별 Summary만 다시 만들기 위한 버전이다.
- 일별 오전값은 자정~정오가 아니라 마지막 기상 후~정오의 비수면 측정만 포함한다. 수면 여부를 먼저
  판정하므로 수면 중 측정은 `sleepMedian`에만 포함된다.
- 공개 `HealthKitService.fetchRMSSDSamples`가 로컬 저장소를 경유하므로 시간별 차트와 기존 분석 코드도
  같은 측정 캐시를 공유한다. 일별 HRV Trend와 장기 미제 사건은 `DailyRMSSDSummary`를 직접 사용한다.
- 월별 HRV Trend는 측정 횟수가 많은 날의 편향을 막기 위해 원시 측정값이 아니라 일별 중앙값으로
  1Q·중앙값·3Q·CV를 집계한다. 조회 범위에 월 전체가 포함된 완료 월만 `MonthlyRMSSDSummary`에
  저장하며, 아직 바뀌는 이번 달은 저장하지 않고 현재 일별 Summary에서 실시간으로 계산한다.

## 백그라운드 HealthKit 관찰

- `RMSSDThresholdMonitorService`가 `HKObserverQuery` + `HKHealthStore.enableBackgroundDelivery`로
  SDNN 측정을 관찰한다 — rMSSD 자체(원시 박동 시리즈, `HKSeriesType.heartbeat()`)가 아니라 SDNN을
  보는 이유는, 관찰 쿼리는 `HKQuantityType`(SDNN)에 붙이는 게 표준적이고 잘 검증된 방식이고, SDNN과
  그 짝이 되는 원시 박동 시리즈는 같은 측정에서 몇 초 이내로 같이 기록되기 때문이다(`HealthKitService`의
  `fetchSDNNRMSSDPairs`가 이미 그 전제로 짝을 짓는다) — "새 SDNN이 왔다"가 "새 rMSSD도 계산 가능하다"의
  안정적인 대리 신호가 된다.
- 필요한 entitlement(`com.apple.developer.healthkit.background-delivery`)는 이미 있었다 — 새 Xcode
  capability나 `Info.plist`의 `UIBackgroundModes` 추가는 필요 없었다(HealthKit 백그라운드 배달은
  `UIBackgroundModes`가 아니라 이 entitlement로 게이트된다).
- 관찰 시작은 `AppDelegate.didFinishLaunchingWithOptions`에서만 한다(뷰의 `.task` 등에서는 안 함) —
  앱이 백그라운드로 깨어난 실행 경로를 포함해 유일하게 타이밍이 보장되는 시점이라, 여기서만 불러도
  중복 등록 걱정이 없다.
- 자세한 임계값·중복 방지·알림 흐름은 [features.md](features.md)의 "rMSSD 급격한 변화 알림" 참고.

## EventKit

- 애플 캘린더 연동은 `CalendarEventService`가 `EKEventStore`로 기기의 모든 캘린더에서 직접 읽는다 —
  HealthKit과 마찬가지로 백엔드를 거치지 않고 기기에서만 읽어와 화면에 쓴다(저장 안 함).
- `EKEventStore.requestFullAccessToEvents()`로 전체 접근 권한을 요청한다 (`NSCalendarsFullAccessUsageDescription`
  필요). 조회 기간은 HealthKit 쿼리와 달리 반드시 명시해야 한다 — `fetchEvents(start:end:)`에 안 넘기면
  "오늘의 패턴" 화면이 쓰는 기본값(과거 1년~미래 3개월)으로 조회하고, 보고서처럼 임의의 과거 기간을
  분석할 때는 그 기간을 그대로 넘긴다(안 그러면 1년보다 오래된 기간엔 일정이 조용히 누락된다).
- 공휴일/휴가는 EventKit에 전용 타입이 없어서, 일정이 속한 캘린더 이름으로 구분한다("Holiday"/"공휴일",
  "휴가"/"vacation" 포함 여부) — `CalendarEventCategory`.

## 로컬 알림

- `AppDelegate`(순수 SwiftUI 라이프사이클이던 이 앱에 이 기능 하나만을 위해 새로 추가함,
  `MindProfilerApp`이 `@UIApplicationDelegateAdaptor`로 붙인다)의
  `application(_:didFinishLaunchingWithOptions:)`에서 `UNUserNotificationCenter.current().delegate`를
  `ReminderNotificationService.shared`로 등록한다 — 앱 struct의 `init()`에서 등록하면 앱이 완전히
  종료된 상태에서 알림 액션으로 재실행되는 launch 경로에 타이밍이 너무 늦을 수 있어서, 애플이
  문서화한 확실한 시점(`didFinishLaunchingWithOptions`)을 쓴다.
- 알림 "설정값"은 백엔드(`MedicationReminder`)에 저장하고, 실제 `UNNotificationRequest` 예약은
  기기에서 `ReminderNotificationService`가 로컬로 한다 — 자세한 스케줄링 방식은
  [features.md](features.md)의 "알림 설정" 항목 참고.
- `ReminderNotificationService`는 이 앱에서 `UNUserNotificationCenterDelegate`를 구현하는 유일한
  객체다(iOS는 앱마다 delegate를 하나만 허용) — rMSSD 급격한 변화 알림도 새 delegate를 만들지 않고
  이 서비스에 카테고리(`RMSSD_THRESHOLD`)만 하나 더 등록해서 처리한다. 그 알림을 탭했을 때 특정
  화면으로 이동해야 하는 건 이 서비스의 책임이 아니라서, `onRMSSDThresholdTapped` 콜백으로
  `RMSSDThresholdAlertCenter`에 알려준다 — `APIClient.onUnauthorized`가 `AuthViewModel`에 로그아웃을
  알려주는 것과 같은 패턴이다.

## 화면 ↔ 코드 매핑

| 화면(PRD.md) | View | ViewModel |
|---|---|---|
| 스플래시 / 홈 | `App/MindProfilerApp.swift`의 `SplashView` / `Views/Home/HomeView.swift` | 스플래시는 자체 이미지 상태 / 홈은 `HomeViewModel` |
| 달력보기 | `Views/Calendar/CalendarView.swift` | `CalendarViewModel` |
| 오늘의 패턴 | `Views/HRVAnalysis/HRVAnalysisView.swift` (+ `HRVAnalysisView+Axes.swift`, `HRVAnalysisView+Charts.swift`) | `HRVAnalysisViewModel` |
| 오늘의 패턴 (수면 탭) | `Views/HRVAnalysis/HRVAnalysisView.swift`의 `SleepOverviewView` | `SleepOverviewViewModel` |
| 보고서 | `Views/Report/ReportView.swift` | `ReportViewModel` |
| 설정 (SDNN vs rMSSD 분석) | `Views/Settings/AnalysisSettingsView.swift` | `HRVCorrelationViewModel` |
| 설정 (전체 기간 상관계수 분석) | `Views/Settings/CorrelationAnalysisView.swift` | `CorrelationAnalysisViewModel` |
| 설정 (알림 설정) | `Views/Settings/ReminderListView.swift` / `ReminderEntryForm.swift` | `ReminderListViewModel` |
| rMSSD 급격한 변화 알림 (메뉴 없음, 알림 탭으로만 진입) | `Views/RMSSDEvent/RMSSDEventEntryForm.swift` | `RMSSDEventEntryViewModel` |

PRD에는 없던 "보고서" 화면은 정신과 진료용 요약 보고서로, 원래 있던 "나의 Trend"(통계, 기분·커피
막대그래프만 있던 화면)를 대체했다 — 자세한 내용은 [features.md](features.md) 참고.

아직 포팅되지 않은 화면/기능은 [features.md](features.md) 참고.
