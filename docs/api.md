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
| GET | `/hrv` | 전체 HRV 검사 기록 조회 (날짜 필터 없음, 클라이언트에서 그룹핑) | `ExamService.allExams` |
| POST | `/hrv` | HRV 검사 기록 생성 | `ExamService.createExam` |
| GET | `/moods?date=yyyy-MM-dd` | 특정 날짜 기분 기록 조회 | `MoodService.todayMood` |
| GET | `/moods` | 전체 기분 기록 조회 | `MoodService.allMoods` |
| POST | `/moods` | 기분 기록 생성/기록 | `MoodService.logMood` |
| GET | `/coffee?date=yyyy-MM-dd` | 특정 날짜 커피 기록 조회 (오늘 잔 수 배지용) | `CoffeeService.todayCount` |
| GET | `/coffee` | 전체 커피 기록 조회 | `CoffeeService.allCoffees` |
| POST | `/coffee` | 커피 기록 생성 | `CoffeeService.logCoffee` / `logQuickCoffee` |

## 아직 안 씀

운동/약복용/이벤트/구글 캘린더 관련 엔드포인트는 백엔드에 이미 있을 수 있지만 iOS 쪽에
`Service`가 아직 없다 — [features.md](features.md)의 "아직 없음" 항목 구현 시 여기 추가한다.

## HealthKit (백엔드 API 아님)

HRV 원시 샘플/수면/운동 범위는 백엔드를 거치지 않고 기기에서 `HealthKitService`가 직접
`HKHealthStore`로 읽는다 — 서버에 저장하지 않으므로 API 목록에는 없다. 자세한 내용은
[architecture.md](architecture.md)의 HealthKit 섹션 참고.
