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
- UIKit 사용 금지
- async/await 사용
- MVVM 유지
- 재사용 가능한 View 우선

## 폴더 구조
MindProfiler
├── App
│   ├── MindProfilerApp.swift
│   └── RootTabView.swift
│
├── Views
│   ├── Home
│   ├── Calendar
│   ├── Statistics
│   └── Settings
│
├── ViewModels
├── Models
├── Services
├── Components
├── Resources
│
├── Assets.xcassets
└── Info.plist
