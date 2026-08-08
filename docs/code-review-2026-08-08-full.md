# 전체 코드 리뷰 — 2026-08-08

## 검토 기준

- 최초 검토 리비전: `272f08413f9fa1cc53a7473fb269a2501ad23df9` (`main`)
- 검토 영역: SwiftUI 화면, ViewModel 상태 관리, HealthKit/rMSSD 계산과 SwiftData 캐시, 수면 집계, 보고서·장기 분석, 인증/API, 알림
- 빌드: iOS Simulator Debug + `SWIFT_STRICT_CONCURRENCY=complete` 성공
- 자동 테스트 타깃: 리뷰 후 `MindProfilerTests` 추가

## 처리 결과

- 병합 수면의 실제 수면시간을 `SleepRange.actualSleepDuration`으로 통일했다.
- HRV viewport 로딩 종료 경계에서 마지막 pending 요청이 유실되지 않도록 수정했다.
- 운동하지 않은 날을 0분으로 포함하고, 보고서의 전날 운동을 합산·중복 제거하도록 수정했다.
- Google Sign-In, HealthKit observer, 알림 delegate 등의 Swift 6 동시성 경고를 정리했다.
- Typography를 UIKit 없이 SwiftUI `Font` 토큰으로 복구하고 기존 고정 크기를 유지했다.
- 회복 지수 캐시를 날짜 단위로 제한하고 로그아웃 시 삭제하도록 수정했다.
- 시스템 색상 asset에 `MPSystem` 접두사를 적용해 생성 심볼 충돌을 제거했다.
- 수면 실제 시간, 중앙값, Pearson 방향을 검증하는 단위 테스트 3개를 추가했다.
- iOS Simulator Debug 빌드 및 `SWIFT_STRICT_CONCURRENCY=complete` 빌드가 성공했다.
- iPhone 17 Pro 시뮬레이터에서 단위 테스트 3개가 모두 통과했다.

## 발견 사항

### [High] 병합된 수면의 깨어 있던 공백이 일부 화면에서 수면시간으로 합산됨

- 위치:
  - `ViewModels/ReportViewModel.swift:157`
  - `ViewModels/ReportViewModel.swift:378-384`
  - `ViewModels/CorrelationAnalysisViewModel.swift:95-115`
- 근거:
  - `SleepAnalysisService`는 2시간 이하로 떨어진 수면 구간을 하나의 `SleepRange`로 합치되, 그 사이 공백은 수면시간에 포함하지 않는 정책이다.
  - 홈과 장기 미제 사건은 `stageDurations.values`의 합으로 실제 수면시간을 계산한다.
  - 그러나 보고서 평균 수면시간, 보고서의 전날 수면시간, 일반 상관분석의 전날 수면시간은 `range.end - range.start`를 사용한다.
- 영향: 중간에 1시간 깨어 있다가 다시 잔 날은 보고서와 상관계수에서 수면시간이 최대 1시간 부풀려지고, 홈·오늘의 패턴·장기 미제 사건과 숫자가 달라진다.
- 권장 수정: 실제 수면시간 계산을 `SleepRange`의 공통 계산 프로퍼티로 만들고 모든 소비자가 이를 사용하게 한다.

### [High] HRV 로딩 완료 경계에서 최신 viewport 요청이 처리되지 않을 수 있음

- 위치: `ViewModels/HRVAnalysisViewModel.swift:408-440`
- 근거:
  - 로딩 루프가 `pendingWindowRequest == nil`을 확인하고 종료한 뒤, 호출자가 `activeLoadTask = nil`로 정리하기 전까지 짧은 구간이 존재한다.
  - 이때 새 요청이 들어오면 완료된 `activeLoadTask`가 아직 존재하므로 새 범위를 pending에 기록하고 이미 완료된 Task의 값을 반환한다.
  - 종료된 로딩 루프는 이 pending 값을 다시 확인하지 않으며, 새 Task도 생성되지 않는다.
- 영향: 빠르게 시간별·일별·월별 탭을 오가거나 스크롤할 때 마지막 범위가 로드되지 않아 빈 차트나 오래된 범위가 남을 수 있다.
- 권장 수정: ViewModel 내부에서 단일 요청 루프의 생명주기와 pending 소비를 원자적으로 관리하거나, 완료 후 pending 존재 여부를 다시 확인해 새 로딩 Task를 시작한다.

### [Medium] 오늘 운동량 비교에서 운동하지 않은 날이 기준에서 빠짐

- 위치: `ViewModels/HomeViewModel.swift:609-629`
- 근거: `exerciseMinutesByDay`에는 운동이 있었던 날짜만 들어가며, 최근 30일 기준 중앙값도 이 딕셔너리의 값만 사용한다.
- 영향: 실제로는 운동하지 않은 날이 많아도 기준이 “운동한 날들의 중앙값”이 된다. 오늘 0분을 이 기준과 비교하면 활동량 부족 신호가 과도하게 발생할 수 있다.
- 권장 수정: 오늘을 제외한 분석 기간의 모든 달력 날짜를 생성하고, 기록이 없는 날은 0분으로 포함한다.

### [Medium] 보고서의 전날 운동은 여러 건 중 첫 번째 한 건만 표시함

- 위치: `ViewModels/ReportViewModel.swift:406-412`
- 근거: `workoutSummaries.first`로 전날 첫 운동만 고른다.
- 영향: 하루에 여러 운동을 했거나 HealthKit 기록과 수동 기록이 함께 있으면 총 운동량과 나머지 운동이 누락된다.
- 권장 수정: 해당 날짜의 모든 운동을 모아 시간을 합산하고, 종목이 여러 개면 요약 문구를 생성한다. 중복된 HealthKit·수동 기록을 함께 쓸 경우 중복 제거 기준도 필요하다.

### [Medium] Swift 6 언어 모드에서 빌드 오류가 될 동시성 경고가 남아 있음

- 위치:
  - `ViewModels/AuthViewModel.swift:160`
  - `Services/CatPhotoService.swift:9`
  - `Services/ReminderNotificationService.swift:215-254`
  - `Services/HealthKitService.swift:114-135, 440, 470`
- 확인 내용:
  - Google Sign-In의 non-Sendable 결과 전달
  - detached Task에서 MainActor 격리 메서드 호출
  - 알림 delegate 객체와 completion handler의 actor 경계 전달
  - HealthKit observer 콜백의 non-Sendable 캡처
  - HealthKit 쿼리 콜백에서 MainActor 격리 initializer 호출
- 영향: 현재 Swift 5 모드 빌드는 성공하지만 Swift 6 전환 시 오류가 된다. 일부는 실제 데이터 경합 가능성을 컴파일러가 경고하는 항목이다.
- 권장 수정: DTO처럼 필요한 값만 Sendable 타입으로 추출하고, 콜백 타입에 `@Sendable`을 명시하며, 순수 enum 변환 로직은 `nonisolated`로 선언한다. 알림 completion handler는 한 실행 경로에서 한 번만 호출하도록 별도 Sendable 래퍼 또는 명확한 actor 경계를 둔다.

### [Medium] Typography가 프로젝트의 UIKit 금지 규칙을 위반함

- 위치: `Components/Typography.swift:1-84`
- 근거: `UIKit`, `UIFont`, `UIFontMetrics`를 사용한다. 프로젝트 규칙은 서드파티 SDK에 SwiftUI 대응 API가 없는 경우를 제외하고 UI에서 UIKit 사용을 금지한다.
- 영향: 타이포그래피 계층이 SwiftUI 전용이라는 아키텍처 원칙과 어긋나며, 최근 폰트 크기 회귀처럼 전역 UI 변경의 영향 범위를 예측하기 어려워진다.
- 권장 수정: SwiftUI `Font` 토큰과 필요한 곳의 `@ScaledMetric` 조합으로 이동하거나, 고정 크기 토큰 정책을 문서에서 명시한다.

### [Low] 스플래시용 회복 지수 캐시에 날짜가 없어 다음 날에도 전날 값이 사용됨

- 위치:
  - `Services/RecoveryScoreCache.swift:6-22`
  - `Services/CatPhotoService.swift:37-50`
- 근거: 캐시는 정수 하나만 저장하며 계산 날짜를 기록하지 않는다.
- 영향: 날짜가 바뀐 뒤 홈 계산이 끝나기 전에 앱을 열면 전날 회복 지수로 스플래시 고양이 카테고리를 선택한다. 로그아웃 시에도 초기화되지 않는다.
- 권장 수정: 값과 날짜 키를 함께 저장하고 오늘 날짜와 일치할 때만 사용한다.

### [Low] 시스템 색상 asset 이름이 생성 심볼과 충돌함

- 위치: `Assets.xcassets/SystemColors`
- 확인 내용: `SystemBlue`, `SystemRed`, `SystemGray` 등 18개 색상 이름이 UIKit의 `systemBlue`, `systemRed` 같은 생성 심볼과 충돌한다는 빌드 경고가 반복된다.
- 영향: 현재 문자열 기반 `Color("SystemBlue")` 사용은 동작하지만, 생성 asset 심볼을 사용하려 할 때 모호해지고 빌드 로그의 유효 신호를 가린다.
- 권장 수정: `MPSystemBlue`처럼 앱 전용 접두사를 붙인다.

## 테스트 공백

프로젝트에 unit test 또는 UI test 타깃이 없다. 특히 다음 로직은 순수 함수 테스트를 우선 추가할 가치가 높다.

1. 2시간 이하 공백을 포함한 수면 병합과 실제 수면시간
2. 자정 이후 시작한 수면의 `nightLabel` 및 다음 날 오전 rMSSD 매칭
3. HRV viewport 요청의 취소·pending·force 병합 상태 전이
4. 운동하지 않은 날을 포함한 30일 중앙값
5. rMSSD RR interval 필터와 gap 처리

## 우선순위

1. 수면시간 계산을 공통 프로퍼티로 통일
2. HRV viewport 로딩 완료 경합 제거
3. 운동 기준의 0분 날짜 포함 및 보고서 운동 합산
4. Swift 6 동시성 경고 정리
5. Typography의 SwiftUI 전용 구현 복구
6. 핵심 통계·날짜 매칭 unit test 타깃 추가
