# Design System

## 철학

- 귀엽지만 유치하지 않게.
- 사용자가 불안장애·우울증을 겪는 사람일 수 있다는 전제로, 색과 이미지는 차분하고 편안하게.
- 그럼에도 재미 요소를 느낄 수 있게.
- 나이·장애·교육 수준에 관계없이 누구나 쉽게 쓸 수 있게.

---

# 색상

디자인 토큰(색상)의 단일 소스는 `Components/Theme.swift`다. 화면에서 색을 직접
`Color(red:green:blue:)`로 하드코딩하지 않고 반드시 `Theme.xxx`를 참조한다.

## 브랜드 컬러

Primary color : **`#9683EC`**

Primary는 앱의 브랜드를 나타내는 색이다.

다음과 같은 UI 요소에 사용한다.

- Primary Button
- Toggle
- Selected Tab
- Selected Segment
- Link
- Focus 상태
- Progress
- 활성 상태(Active)

Primary는 **브랜드를 위한 색**이며, 개별 건강 지표의 의미를 표현하는 용도로 사용하지 않는다.

---

## 지표 색상 팔레트

지표 색은 **Radix UI Colors**를 사용한다.

원래 mind-record 웹에서 사용하던 Tailwind 계열 색을 색상 거리가 가장 가까운 Radix Color Scale로 모두 교체했다.

새로운 지표 색이 필요하면 임의의 HEX를 선택하지 않고 **Radix Color Scale**에서 선택한다.

기본은 **9단계(solid)** 를 사용하며 필요하면 **10, 11단계**를 사용한다.

| 토큰 | Radix | 값 | 의미 |
|------|--------|------|------|
| `Theme.rmssd` | `iris-9` | `#5b5bd6` | rMSSD 라인 차트 및 월별 막대 차트 |
| `Theme.examRmssd` | `green-9` | `#30a46c` | 병원 검사 rMSSD 포인트(세모 마커) |
| `Theme.exercise` | `jade-9` | `#29a383` | 운동 Gantt 레인 |
| `Theme.sleep` | `indigo-9` | `#3e63dd` | 수면 Gantt 레인 |
| `Theme.mood` | `amber-9` | `#ffc53d` | 기분 막대그래프 |
| `Theme.coffee` | `orange-10` | `#f76808` | 커피 막대그래프 |
| `Theme.calendarCoffeeBadge` | custom pastel | `#CCA685` | 캘린더 커피 원 배지 |
| `Theme.calendarExerciseBadge` | custom pastel | `#B3D9BF` | 캘린더 운동 원 배지 |
| `Theme.calendarMedicationBadge` | custom pastel | `#FAE69E` | 캘린더 약 복용 원 배지 |
| `Theme.calendarEventBadge` | custom pastel | `#B8D1F2` | 캘린더 이벤트 원 배지 |
| `Theme.hourlyCoffeeMarker` | custom muted | `#AD8563` | 시간별 커피 원 마커 |
| `Theme.hourlyMedicationMarker` | custom bright | `#F8C755` | 시간별 약 복용 원 마커 |
| `Theme.holiday` | `ruby-9` | `#e54666` | 공휴일 |
| `Theme.vacation` | `orange-9` | `#f76b15` | 휴가 |
| `Theme.heart` | `ruby-9` | `#e54666` | 로딩 인디케이터 하트 |
| `Theme.systemMint` | system mint | asset | 일별 안정시 심박수 막대·범례 |

---

## 브랜드 컬러와 지표 색의 역할

브랜드 컬러와 데이터 컬러는 역할을 명확히 구분한다.

- 빨강 계열은 임계값 이탈, 짧은 수면 등 경고 상태에만 사용한다. 정상 범위의 건강 지표를 단순히
  표현할 때는 빨강을 사용하지 않는다.

### 브랜드 컬러 (Primary)

앱 자체를 나타낸다.

예)

- 버튼
- 선택 상태
- 토글
- 링크
- 진행 상태
- 앱의 강조 요소

### 지표 색

데이터의 종류를 나타낸다.

예)

- 차트
- Gantt
- 막대그래프
- 범례
- 데이터 포인트

브랜드 컬러와 데이터 컬러가 같은 화면에 있어도 서로 경쟁하지 않도록 한다.

---

## 수면 단계 도넛 팔레트

수면 상세 패널의 단계별 도넛 차트는 지표 색과 별개의 카테고리 팔레트를 사용한다.

| 단계 | 토큰 |
|------|------|
| 깊은 잠 | `Theme.sleepStageDeep` |
| REM | `Theme.sleepStageREM` |
| Core | `Theme.sleepStageCore` |
| 미상 | `Theme.sleepStageUnspecified` |
| Awake | Gray |

이 팔레트는 `dataviz`에서 검증된 카테고리 팔레트를 그대로 사용하며,
색각 이상(CVD) 테스트를 통과한 조합이다.

각성(Awake)은 하나의 수면 단계가 아니라 "나머지 시간"이므로 무채색을 사용한다.

---

## 시스템 색상 팔레트

건강 지표와 관계없는 일반 UI는 Apple System Color를 사용한다.

- `Theme.systemRed`
- `Theme.systemOrange`
- `Theme.systemYellow`
- `Theme.systemGreen`
- `Theme.systemMint`
- `Theme.systemTeal`
- `Theme.systemCyan`
- `Theme.systemBlue`
- `Theme.systemIndigo`
- `Theme.systemPurple`
- `Theme.systemPink`
- `Theme.systemBrown`

회색 계열

- `Theme.systemGray`
- `Theme.systemGray2`
- `Theme.systemGray3`
- `Theme.systemGray4`
- `Theme.systemGray5`
- `Theme.systemGray6`

예)

- 일반 캘린더 일정
- SDNN 참고선
- Placeholder
- Divider
- 비활성 상태
- Border(카드/입력 필드 테두리) — `Theme.systemGray5`

---

## 빨강 사용 규칙

**빨강 계열은 "문제", "위험", "경고"를 표현할 때만 사용한다.**

빨강은 가장 시선을 끄는 색이므로 일반적인 데이터 색으로 사용하지 않는다.

### 빨강을 사용하는 경우

- 에러
- 경고
- 위험 상태
- 이상치
- 수면 5시간 미만
- 삭제 버튼

### 예외

#### `Theme.heart`

로딩 인디케이터의 하트 고유 색이다.

지표 색이 아니므로 빨강을 유지한다.

#### `Theme.holiday`

공휴일은 캘린더의 관례상 빨강으로 표현하는 것이 가장 자연스럽기 때문에 예외로 한다.

### 새로운 색을 추가할 때

먼저 아래 기준으로 판단한다.

> 이 색이 "데이터의 종류"를 나타내는가?

→ 빨강을 사용하지 않는다.

> 이 색이 "문제" 또는 "위험"을 나타내는가?

→ 빨강 계열을 사용한다.

---

## 색상 선택 원칙

### 1. 브랜드 컬러와 데이터 컬러를 구분한다.

브랜드는 Primary를 사용하고,
데이터는 지표 색을 사용한다.

### 2. 같은 의미는 항상 같은 색을 사용한다.

예)

- rMSSD는 모든 화면에서 동일한 보라(Iris)
- 수면은 항상 Indigo
- 운동은 항상 Jade
- 기분은 항상 Amber

### 3. 새로운 데이터 색은 Radix에서 선택한다.

임의의 HEX를 추가하지 않는다.

### 4. 의미 없는 장식 색은 만들지 않는다.

색은 항상 의미를 가져야 한다.

---

## 원칙

- 앱 고유 색은 모두 `Theme.swift`에서 관리한다.
- 화면에서는 HEX를 직접 사용하지 않는다.
- 동일한 지표는 모든 화면에서 같은 `Theme` 토큰을 사용한다.
- 브랜드 컬러와 데이터 컬러의 역할을 섞지 않는다.
- 임시 UI 색(`.secondary`, `.tertiary`, `.red` 등)은 시스템 시맨틱 컬러를 그대로 사용한다.
- 새로운 지표 색은 반드시 Radix UI Color Scale에서 선택한다.


## Typography

### 철학

텍스트는 **읽기 쉬움**과 **접근성**을 가장 우선한다.

모바일에서는 웹보다 약간 큰 글자를 사용하며, 작은 글씨보다 충분한 여백을 통해 정보의 위계를 만든다.

사용자가 불안하거나 피곤한 상태에서도 부담 없이 읽을 수 있도록 명확하고 일관된 타이포그래피를 유지한다.

---

### Typography Token

타이포그래피의 단일 소스는 `Components/Typography.swift`다.

화면에서

```swift
.font(.system(size: 17))
```

처럼 크기를 직접 지정하지 않고 반드시 `Typography.xxx`를 사용한다.

예)

```swift
Typography.largeTitle
Typography.screenTitle
Typography.sectionTitle
Typography.cardTitle
Typography.body
Typography.button
Typography.secondary
Typography.caption
```

---

### 기본 원칙

- 글자를 작게 만들어 정보를 많이 넣지 않는다.
- 폰트 크기보다 여백으로 레이아웃을 정리한다.
- 한 화면에 너무 많은 크기의 텍스트를 사용하지 않는다.
- Weight와 Size로 위계를 만든다.
- Dynamic Type을 지원할 수 있도록 시스템 폰트를 사용한다.
- 같은 의미의 텍스트는 항상 같은 스타일을 사용한다.

---

### 타입 스케일

| 토큰 | 크기 | Weight | 용도 |
|------|------:|--------|------|
| `Typography.largeTitle` | 28pt | Bold | 페이지 대표 제목 |
| `Typography.screenTitle` | 24pt | Bold | 화면 제목 |
| `Typography.sectionTitle` | 20pt | Bold | 섹션 제목 |
| `Typography.reportSectionTitle` | 19pt | Bold | 여러 패널이 반복되는 보고서 섹션 제목 |
| `Typography.cardTitle` | 16pt | Semibold | 카드 제목 |
| `Typography.body` | 17pt | Regular | 본문 |
| `Typography.button` | 17pt | Semibold | 버튼 |
| `Typography.secondary` | 15pt | Regular | 보조 설명 |
| `Typography.caption` | 13pt | Regular | 캡션 |

---

## 버튼

버튼은 **읽는 요소보다 누르는 요소**이다.

글자를 작게 만들지 않는다.

### Primary Button

- `Typography.button`
- 17pt
- Semibold

### Secondary Button

- `Typography.button`
- 17pt
- Medium

### Chip

- 15pt
- Medium

### Tab

- 15pt
- Medium

---

### 버튼 크기

버튼은 글자보다 **터치 영역**이 중요하다.

최소 터치 영역은 Apple Human Interface Guidelines를 따라 **44pt 이상**으로 한다.

| 용도 | 높이 |
|------|------:|
| Small | 44pt |
| Default | 50pt |
| Large | 56pt |

기본 버튼은 **50pt**를 사용한다.

---

## 정보 위계

텍스트 크기보다 **여백으로 위계를 만든다.**

예)

```
28pt
페이지 제목


20pt
섹션 제목


17pt
본문


15pt
보조 설명
```

같은 크기의 텍스트라도 충분한 여백을 주는 것이 작은 글자를 사용하는 것보다 읽기 쉽다.

---

## 접근성

- Dynamic Type을 지원한다.
- 버튼은 44pt 이상의 터치 영역을 가진다.
- 본문은 17pt를 기본으로 사용한다.
- 작은 설명 텍스트도 13pt 이하로 사용하지 않는다.
- 색만으로 정보를 구분하지 않는다.

---

## 새로운 스타일 추가

새로운 Typography를 추가하기 전에 아래 순서로 검토한다.

1. 기존 Typography로 표현 가능한가?
2. 같은 의미의 스타일이 이미 존재하는가?
3. 정말 새로운 역할인가?

역할이 다르지 않다면 새로운 Typography를 만들지 않는다.

---

## 원칙

- 모든 타이포그래피는 `Typography.swift`에서 관리한다.
- 화면에서는 폰트 크기를 직접 지정하지 않는다.
- 동일한 역할은 항상 동일한 Typography 토큰을 사용한다.
- 시스템 폰트를 사용한다.
- Body는 17pt를 기본으로 한다.
- Button도 17pt를 사용한다.
- 새로운 스타일보다 기존 스타일의 재사용을 우선한다.
