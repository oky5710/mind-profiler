# MindProfiler

## Tech Stack
- SwiftUI
- MVVM
- Swift Concurrency
- Apple Health
- Google Sign-In
- PostgreSQL (Neon)
- NestJS API

## Rules
- UI는 SwiftUI만 사용
- UIKit 사용 금지 — 단, SwiftUI에 대응 API가 없어 서드파티 SDK 연동에 꼭 필요한 경우는 예외
  (예: `AuthViewModel`이 Google Sign-In SDK에 표시용 `UIViewController`를 넘겨줘야 해서 사용).
  화면 크기처럼 SwiftUI로 구할 수 있는 값(`GeometryReader` 등)에 UIKit(`UIScreen` 등)을 쓰지 않는다.
- async/await 사용
- MVVM 유지
- 재사용 가능한 View 우선

## 문서
| 문서 | 용도 |
|---|---|
| `PRD.md` | 제품 요구사항 — 화면/기능 정의, mind-record 원본 기획 |
| `docs/architecture.md` | 아키텍처 — 레이어 구성, 데이터 흐름, 폴더 구조 배경 |
| `docs/design-system.md` | 디자인 원칙 — 색상 등 `Theme.swift`에 반영되는 디자인 토큰 |
| `docs/ui-style.md` | UI 스타일 — 화면별 레이아웃/타이포/차트 스타일 규칙 |
| `docs/features.md` | 기능 명세 — 화면별 상세 동작/엣지 케이스 |
| `docs/api.md` | API 연동 — `mind-chart-backend` 엔드포인트/요청·응답 규격 |

새 규칙이나 결정 사항은 해당 목적에 맞는 문서에 기록한다.

## 폴더 구조
MindProfiler
├── App
│   ├── MindProfilerApp.swift
│   └── RootTabView.swift
│
├── Views
│   ├── Home
│   ├── Calendar
│   ├── HRVAnalysis
│   ├── Report
│   ├── Login
│   ├── RMSSDEvent
│   └── Settings
│
├── ViewModels
├── Models
├── Services
├── Components
├── Resources
│
├── docs
├── Assets.xcassets
└── Info.plist
