# Code Review — 2026-08-08

## 검토 범위

- 기준 리비전: `ae34bad` (`main`)
- 비교 범위: `origin/main...HEAD`의 로컬 커밋 33개
- 주요 검토 영역: HRV 차트 범위 로딩·취소, 로컬 rMSSD 월별 캐시, 홈 브리핑, 인증·온보딩
- 검증: iOS Simulator Debug 전체 빌드 성공

## 발견 사항

### [High] 취소된 HRV 로딩 작업이 최신 요청까지 취소할 수 있음

- 위치: `Views/HRVAnalysis/HRVAnalysisView.swift:446-456`
- 관련 위치: `ViewModels/HRVAnalysisViewModel.swift:395-425`
- 근거:
  - 새 viewport가 들어오면 View가 기존 `healthKitViewportLoadTask`를 취소하고 새 Task를 즉시 시작한다.
  - ViewModel이 이미 로딩 중이면 새 요청은 `pendingWindowRequest`에 저장된 뒤 호출 자체는 바로 반환한다.
  - 취소된 기존 Task가 pending 요청을 이어서 처리하면, Task의 취소 상태를 그대로 상속한 채 최신 요청까지 취소될 수 있다.
- 재현 가능한 순서:
  1. 월별 범위 A 로딩 시작
  2. 시간별로 이동하면서 A 취소
  3. 시간별 범위 B는 `pendingWindowRequest`에 저장 후 반환
  4. 취소된 A가 B를 이어받아 실행
  5. B도 취소 상태로 끝나 시간별 범위가 로드되지 않음
- 영향: 빠른 탭 전환 뒤 무한 로딩, 빈 차트 또는 데이터 없음 안내가 남을 수 있다.
- 권장 수정:
  - ViewModel이 현재 로딩 Task를 소유하고 새 요청으로 원자적으로 교체하거나,
  - 새 요청이 이전 Task의 완전한 종료를 기다린 뒤 별도 Task에서 시작되도록 한다.
  - 취소된 Task가 pending 요청을 처리하지 않도록 해야 한다.

### [Medium] 강제 새로고침이 일반 스크롤 요청에 덮일 수 있음

- 위치: `ViewModels/HRVAnalysisViewModel.swift:399-401`
- 근거: `pendingWindowRequest`가 한 개뿐이고 새 요청이 이전 요청을 튜플 전체로 덮어쓴다.
- 재현 가능한 순서:
  1. 일반 범위 로딩 진행 중
  2. 새로고침 요청이 `force: true`로 pending에 저장
  3. 추가 스크롤 요청이 `force: false`로 pending을 덮어씀
  4. 강제 새로고침 의도가 사라짐
- 영향: 사용자가 새로고침을 눌러도 HealthKit의 새 데이터를 다시 확인하지 않을 수 있다.
- 권장 수정: 최신 범위는 교체하되 `force`는 기존 값과 새 값의 논리합으로 유지한다.

```swift
pending.force = pending.force || newRequest.force
```

### [Medium] 온보딩 상태가 계정 사이에 남을 수 있음

- 위치: `ViewModels/AuthViewModel.swift:108-123`
- 근거:
  - 신규 사용자 로그인에서만 `onboardingPending`을 `true`로 설정한다.
  - 기존 사용자 로그인과 로그아웃에서는 해당 값을 초기화하지 않는다.
- 재현 가능한 순서:
  1. 신규 계정 로그인
  2. 온보딩 완료 전에 로그아웃
  3. 같은 기기에서 기존 계정 로그인
- 영향: 기존 계정에도 신규 사용자 온보딩이 표시될 수 있다.
- 권장 수정: 온보딩 상태를 사용자 ID별로 저장하거나 기존 사용자 로그인·로그아웃 시 명시적으로 초기화한다.

### [Low] 오늘 표시 데이터가 있어도 자동으로 전날로 이동할 수 있음

- 위치: `Views/Home/HomeView.swift:35-43`
- 근거: 자동 이동 조건이 `recoveryScore == nil`과 `briefingCaseType == nil`만 확인한다.
- 영향: 다음 데이터가 오늘 존재해도 전날 화면으로 이동할 수 있다.
  - 최근 HRV
  - 오늘 확보한 단서
  - 오늘의 신호
  - 커피·복약 기록
- 권장 수정: 요약 카드, 오늘 단서, 오늘 신호까지 모두 비었을 때만 전날로 이동하거나 자동 이동 자체를 제거한다.

## 빌드 및 동시성 경고

전체 빌드는 성공했다. 다만 Swift 6 언어 모드에서 오류가 될 수 있는 동시성 경고가 남아 있다.

- `AuthViewModel`, `RMSSDThresholdAlertCenter`: 동시 실행 클로저의 `self` 캡처
- `CalendarEventService`: detached task에서 MainActor 격리 값 접근
- `HRVAnalysisViewModel`의 `DatedPoint` 채택 타입: MainActor 격리 준수 경고
- `ReminderListView`: MainActor 격리된 정적 메서드를 동기 nonisolated 문맥에서 호출

## 우선순위

1. HRV viewport 요청 취소·교체 구조 수정
2. pending 강제 새로고침 보존
3. 계정별 온보딩 상태 분리
4. 홈의 자동 전날 이동 조건 수정
5. Swift 6 동시성 경고 정리
