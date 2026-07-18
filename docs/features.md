# Features

전체 제품 범위는 [PRD.md](../PRD.md) 참고. 이 문서는 그중 MindProfiler(iOS)에서 **현재 구현된 것**과
**아직 안 된 것**을 구분해서 추적한다.

## 구현됨

### 로그인 (`Views/Login`)
- Google Sign-In(`GoogleSignIn` SDK) → 백엔드 `POST /auth/google`로 idToken 교환 → JWT를 Keychain에 저장.

### 진입 화면 / 홈 (`Views/Home`)
- Pixabay 랜덤 고양이 사진 + 랜덤 위로 문구.
- 그 외 PRD의 기분/커피 간편 입력, 복용약 퀵버튼은 **아직 홈 화면엔 없음** (기분/커피는 통계에서만 조회 가능,
  입력 폼은 캘린더 쪽에 있음).

### 달력보기 (`Views/Calendar`)
- 월 달력 그리드, 날짜 탭 → bottom sheet로 유형 선택 후 입력.
- 구현된 유형: 검사(HRV, `ExamEntryForm`) / 커피(`CoffeeEntryForm`) / 기분(`MoodEntryForm`).
- PRD에 있는 운동/약복용/이벤트 유형은 **폼 미구현**.

### 나의 Trend / 통계 (`Views/Statistics`)
- 기분·커피 막대그래프만 구현. PRD의 "나의 Trend"(HRV/웨어러블 통합 대시보드)는 대부분
  [오늘의 패턴](#오늘의-패턴-viewshrvanalysis)이 흡수함.

### 오늘의 패턴 (`Views/HRVAnalysis`)
- 시간별/일별/월별 HRV 라인 차트 (검사 SDNN 포인트 오버레이).
- 애플워치 HRV/수면/운동을 HealthKit에서 직접 조회 — 수면·운동은 별도 Gantt 레인으로 표시.
- 가로 드래그 스크롤(현재 시각 이후로는 스크롤 불가), 워치 미착용 구간은 선이 끊김.
- PRD에 있는 이벤트/커피/기분 오버레이, 구글 캘린더 레인은 **미구현** (의도적으로 이 화면에서 뺀 상태).

## 아직 없음 (PRD 대비 미구현)

- **복용약 관리** 화면 및 아침/취침 퀵버튼 (`/medicine` 대응 화면 없음).
- **이벤트 기록** (약 변경/대인관계/업무 스트레스/병원 진료/기타).
- **운동 기록 입력 폼** (HealthKit에서 읽어오는 것과 별개로, 캘린더에서 수동 입력하는 기능).
- **구글 캘린더 연동** (읽기 전용 일정 오버레이).
- `Views/Settings/SettingsView.swift`는 초기 스캐폴딩 이후 `RootTabView`에서 빠졌고 현재 어디서도
  참조되지 않는 미사용 파일 — 정리하거나 실제 설정 화면으로 채울지 결정 필요.

## 백엔드 의존성

기능별로 호출하는 API는 [api.md](api.md) 참고. 이 앱은 mind-record 웹과 백엔드/DB를 공유하므로,
새 기능이 백엔드 스키마 변경을 필요로 하면 `mind-chart-backend`/`mind-record` 양쪽에 미치는 영향을
먼저 확인한다.
