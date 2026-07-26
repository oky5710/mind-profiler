# API

MindProfiler는 mind-record(웹)와 **같은** NestJS 백엔드(`mind-chart-backend`)를 그대로 쓴다.
백엔드 자체 문서는 `mind-chart-backend/README.md` / `api-docs.html` 참고 — 이 문서는
**iOS 클라이언트(`APIClient`)가 실제로 호출하는 부분**만 정리한다.

## 공통

- Base URL: `https://mind-profiler-backend.onrender.com` (`Services/APIClient.swift`).
- 인증: `POST /auth/google` 성공 후 받은 JWT를 Keychain에 저장하고, 이후 모든 요청에
  `Authorization: Bearer <token>` 헤더로 붙인다 (`authorized: true`가 기본값).
- 에러: 2xx가 아니면 `APIError.server(statusCode:message:)`로 응답 바디를 그대로 실어 던진다 —
  화면에는 `error.localizedDescription`을 그대로 노출한다 (원인 은폐 금지, AGENTS.md 규칙).
- 날짜 파라미터는 `yyyy-MM-dd`(`DateKey.string(from:)`), 응답의 날짜/시각 필드는 ISO 8601
  (`DateKey.parseISODate`로 파싱, fractional seconds 유무 둘 다 대응).

## 엔드포인트

| Method | Path | 용도 | 클라이언트 코드 |
|---|---|---|---|
| POST | `/auth/google` | Google idToken → 백엔드 JWT 교환 (`authorized: false`) | `AuthViewModel.signInWithGoogle` |
| GET | `/hrv` | 전체 HRV 검사 기록 조회 (날짜 필터 없음, 클라이언트에서 그룹핑 — `ExamEntryForm` 목록도 여기서 그 날짜만 걸러낸다) | `ExamService.allExams` / `entries` |
| POST | `/hrv` | HRV 검사 기록 생성 | `ExamService.createExam` |
| DELETE | `/hrv/:id` | HRV 검사 기록 삭제 | `ExamService.removeExam` |
| GET | `/moods?date=yyyy-MM-dd` | 특정 날짜 기분 기록 조회 (홈 화면 오늘 기분·`DayDetailSheet`/`MoodEntryForm` 목록용) | `MoodService.todayMood` / `entries` |
| GET | `/moods` | 전체 기분 기록 조회 | `MoodService.allMoods` |
| POST | `/moods` | 기분 기록 생성 | `MoodService.logMood` |
| PATCH | `/moods/:id` | 기분 기록 수정 (날짜 요약 시트의 수정 아이콘) | `MoodService.updateMood` |
| DELETE | `/moods/:id` | 기분 기록 삭제 | `MoodService.removeMood` |
| GET | `/coffee?date=yyyy-MM-dd` | 특정 날짜 커피 기록 조회 (오늘 잔 수 배지·`CoffeeEntryForm` 목록용) | `CoffeeService.todayCount` / `entries` |
| GET | `/coffee` | 전체 커피 기록 조회 | `CoffeeService.allCoffees` |
| POST | `/coffee` | 커피 기록 생성 | `CoffeeService.logCoffee` / `logQuickCoffee` |
| PATCH | `/coffee/:id` | 커피 기록 수정 (날짜 요약 시트의 수정 아이콘) | `CoffeeService.updateCoffee` |
| DELETE | `/coffee/:id` | 커피 기록 삭제 | `CoffeeService.removeCoffee` |
| GET | `/exercises?date=yyyy-MM-dd` | 특정 날짜 운동 기록 조회 (`DayDetailSheet`/`ExerciseEntryForm` 목록용) | `ExerciseService.entries` |
| GET | `/exercises` | 전체 운동 기록 조회 (날짜 필터 없음, 클라이언트에서 그룹핑) | `ExerciseService.allExercises` |
| POST | `/exercises` | 운동 기록 생성 | `ExerciseService.logExercise` |
| PATCH | `/exercises/:id` | 운동 기록 수정 (날짜 요약 시트의 수정 아이콘) | `ExerciseService.updateExercise` |
| DELETE | `/exercises/:id` | 운동 기록 삭제 | `ExerciseService.removeExercise` |
| GET | `/medications` | 등록된 약 전체 조회 | `MedicationService.allMedications` |
| POST | `/medications` | 약 등록(검색 결과+복용 시간대) | `MedicationService.addMedication` |
| DELETE | `/medications/:id` | 약 삭제(soft delete) | `MedicationService.removeMedication` |
| GET | `/medications/logs?date=yyyy-MM-dd` | 특정 날짜 복용 기록 조회(홈 화면 퀵버튼 체크 표시용) | `MedicationService.logs` |
| POST | `/medications/logs/quick` | 해당 시간대로 등록된 약 전부 복용 처리 | `MedicationService.logTiming` |
| DELETE | `/medications/logs/:id` | 복용 기록 삭제 | `MedicationService.removeLog` |
| GET | `/drugs/search?name=` | 식약처 낱알식별정보 검색(공개 엔드포인트) | `MedicationService.searchDrugs` |
| GET | `/events?date=yyyy-MM-dd` | 특정 날짜 이벤트 기록 조회 (`LifeEventEntryForm` 목록용) | `LifeEventService.entries` |
| GET | `/events` | 전체 이벤트 기록 조회 | `LifeEventService.allEvents` |
| POST | `/events` | 이벤트 기록 생성 | `LifeEventService.logEvent` |
| DELETE | `/events/:id` | 이벤트 기록 삭제 | `LifeEventService.removeEvent` |

## 아직 안 씀

구글 캘린더 관련 엔드포인트는 iOS에서 안 쓴다 — 아래 EventKit 섹션 참고.

## HealthKit (백엔드 API 아님)

수면/운동 범위와 rMSSD 계산용 원시 박동 시리즈는 백엔드를 거치지 않고 기기에서 `HealthKitService`가
직접 `HKHealthStore`로 읽는다 — 서버에 저장하지 않으므로 API 목록에는 없다. 읽는 타입: 운동, 수면,
rMSSD 계산용 원시 박동 시리즈(`HKSeriesType.heartbeat()`, iOS 13+), HRV(SDNN,
`heartRateVariabilitySDNN`) — SDNN은 HealthKit 제약상 heartbeat series 권한과 반드시 같이
요청해야 하고(안 하면 크래시), 화면에서는 rMSSD 참고용 옅은 라인으로만 쓴다 — 그리고 안정시 심박수
(`HKQuantityType(.restingHeartRate)`, 보고서의 "기간 요약" 중앙값용). 자세한 내용은
[architecture.md](architecture.md)의 HealthKit 섹션 참고.

## EventKit (백엔드 API 아님, 구글 캘린더 대체)

mind-record 웹의 "구글 캘린더 연동"(읽기 전용 일정 조회)에 대응하는 기능은 백엔드 API가 아니라
`CalendarEventService`가 기기의 `EKEventStore`(EventKit)로 직접 읽는다 — 서버를 거치지 않고
저장도 안 한다. 자세한 내용은 [architecture.md](architecture.md)의 EventKit 섹션 참고.
