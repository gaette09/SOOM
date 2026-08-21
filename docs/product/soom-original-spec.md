# SOOM Original Spec (Freeform 초안 판독)

원본: `docs/product/reference/AI FITNESS.pdf` (Freeform 보드를 PDF로 내보낸 것, 1페이지 3395×3340pt 캔버스, 2026-08-19 생성).

방법론: `pdftoppm`(poppler, 이번에 설치)으로 72dpi 전체 개요 1장 + 영역별 250~400dpi 고해상도 크롭 다수를 렌더링해 전수 확인. 캔버스에는 두 종류의 콘텐츠가 섞여 있다 — **(a) Strava/Adidas Running 등 실제 앱의 미가공 스크린샷**(자체 브랜딩·네비게이션 그대로, 참고용 레퍼런스)과 **(b) 손글씨/텍스트 박스로 단 주석**(화살표로 특정 요소를 가리키며 한국어로 설명 — 이게 SOOM이 실제로 원하는 것에 가장 가까운 신호). 아래 문서는 이 둘을 항상 구분해서 표기한다: **[Strava 동일]** = 주석 없이 그대로 가져온 참고 스크린샷, **[SOOM 차별점]** = 손글씨 주석이 명시적으로 설명한 부분.

## 0. IA / 하단 탭 구조 — 중요: 캔버스 안에 세 가지 다른 버전이 공존함

"하단 메뉴" 라벨이 붙은 클러스터 하나에서 세 가지 서로 다른 탭 구성이 동시에 발견됨(같은 캔버스 안에서 여러 번 고쳐 쓴 흔적으로 보임, 하나로 정리되지 않았음):

1. 손글씨 텍스트: **"오늘 / 그룹 / 피드 / 훈련 / 나"** (Today / Group / Feed / Training / Me — 5개)
2. 탭바 목업 자체의 아이콘 라벨: **"오늘 / 트렌드 / 저널 / 운동 / 훈련"** (Today / Trend / Journal / Workout / Training — 아이콘: 사각형/막대그래프/원형(Record)/번개/역삼각형)
3. 그 아래 영문 화살표 주석: **"Today"**(1번 탭) / **"Play"**(3번째, 원형 Record 아이콘 가리킴) / **"You"**(5번째, 마지막 탭)

세 버전 다 탭 개수는 5개로 일치하지만 라벨이 서로 다르다. 확실히 공통되는 것: **첫 번째 탭은 "오늘"(Today) — AI 코치/신체 상태 대시보드**이고, 소셜 피드는 첫 탭이 아니라 중간 어딘가(2~4번째)에 위치한다. "Play"(원형 아이콘)가 가운데 위치한 것으로 보아 탭이 아니라 중앙 플로팅 액션 버튼(기록 시작)일 가능성이 높음 — Strava의 실제 탭바(Home/Maps/**Record**/Groups/You, Record가 가운데)와 정확히 같은 배치 패턴.

**결론(확인 필요 사항으로 남김, 추측 금지)**: 정확한 5개 탭의 최종 라벨과 순서는 이 캔버스만으로는 확정할 수 없음 — 다음 사용자 확인 필요. 다만 구조적으로 확실한 것 두 가지: (1) "오늘"이 첫 진입 탭이라는 점, (2) Record가 탭 목록 가운데 위치한 원형 액션 버튼이라는 점(Strava와 동일 패턴).

## 1. Today (오늘) — [SOOM 차별점]

첫 진입 탭. 상단부터:

- **날짜 헤더**: "2월 4일, 수" + 우측 프로필 아이콘.
- **"제안"(Suggestion) 카드** — 손글씨 주석: *"AI가 추천 추천을 해주는 공간, 운동 제안"*. 현재 예시 내용: "HRV 데이터가 없습니다. 수동으로 측정해 회복 상태를 확인하세요." + "HRV 수동 측정" 버튼. AI가 그날의 컨디션에 맞는 운동을 추천하는 자리.
- **4칸 신체 상태 그리드** — 손글씨 주석: *"현재 나의 신체 상태 데이터: 1.신체에너지(바디배터리) 2.스트레스(실시간스트레스) 3.회복(HRV) 4.운동강도(운동점수)"*. 각 칸: 신체 에너지(스파크라인 + %, 예 "47% 낮음"), 스트레스(반원 게이지), 회복(HRV 기반, 현재 "데이터 없음"), 운동 강도(운동점수 기반, 현재 "데이터 없음"). Garmin Body Battery류의 4지표 대시보드 — **SOOM의 핵심 차별 개념**.
- 이 아래부터는 **[Strava 동일]** — Strava 홈("You" 탭 하단부와 동일한 카드 세트, 캔버스에 중복 등장): 스포츠 필터(Swim/Run/Virtual Ride) + "This week" 주간 차트, 스트릭 캘린더("Your Streak · Streak Activities"), 월간 리캡("View Your Full Recap"), Performance Predictions(5K/10K/하프/풀 예측), Training Zones(Zone별 시간 분포), Power Skills(스프린트~클라임 레이더 차트), Goals(목표별 진행률), Training Log, Best Efforts(파워 PR 리스트), Monthly Activities, Fitness(피트니스 트렌드 차트, CTL류), Relative Effort(주간 훈련부하 vs 제안 범위), Data Sources(연결 기기 목록 + 기기 연결/관리 링크).

**운동점수 → 회복 자동 설정 컨셉**[SOOM 차별점]: Record 섹션 근처 및 이 근방에 반복 등장하는 손글씨 주석 — *"운동정수(운동점수)를 부여하고 운동점수와 회복에 따라 목표 운동강도를 자동으로 설정 해주는 컨셉"*, 그리고 Relative Effort 카드 근처(피드 상세 쪽)의 확장 설명: *"각 운동에 점수를 부여하고 주간으로 데이터를 쌓아서 이번주 적정 운동강도의 범위를 지정하고 그 범위에 못미치면 운동강도를 높이거나 운동량을 늘리거나, 범위를 넘어서면 빨간색으로 표시하면서 회복을 유도하는 기능."* — 이게 사실상 SOOM Recovery 기능의 원형(原形) 스펙.

## 2. Record (기록 시작) — [Strava 동일, 참고용]

- 지도 + 하단 시트: "Ride / **Start** / Add Route" 3버튼, 현재 값(Time/Avg.speed/Distance) 미리보기, "Stay safe and send a text to start sharing your location" + Send Beacon Text.
- 시작 후: 큰 숫자 HUD(00:00:00, Avg. speed, Distance), Pause 버튼.
- "설정" 화면(⚠️ 앱 설정 아님, **기록 중 HUD에 표시할 데이터 필드 커스터마이즈 화면**) — 평균/실시간 속도/최대, 캐디언스, 실시간 파워, 실시간 심박수, 경사도, 거리, 운행 시간, 좌우 밸런스 등을 그리드에 배치. "이 페이지의 레이아웃 변경", 여러 데이터 화면(1/2 페이지) 전환, 미리보기/추가/정렬삭제.
- "Choose a Sport" 종목 선택 시트(Your Top Sports: Swim/Run 등, Foot Sports 카테고리).
- Split 화면(구간별 평균 페이스).

## 3. 피드 카드 (Feed Card) — 최우선 확인 영역

### 기본형

```
[프로필 아이콘] jihwan CHUNG            ← 프로필 / 아이디
January 31, 2026 at 8:56 AM · Apple Watch Series 6   ← 날짜시간 / 헬스케어기기
2026-01-31Run                            ← 운동종류 / 제목 (날짜+종목으로 자동 생성)
■ Running Summary ■
R파워 161, 강도 0.98, 훈련량 34
✨ 회복시간 12 시간...
Read more...                             ← 내용 (AI 생성 캡션, 접기/펼치기)
Distance 2.69 km   Pace 7:53/km   Time 21m 15s   ← 운동 정보(운동 종류별로 다르게 구성됨, 주석: "운동에 따라 보여주는 내용이 조금씩 달라짐")
👍 좋아요    💬 댓글    ↗ 공유하기
```

- 아바타는 사진이 아니라 방패/문장(紋章) 아이콘 — Strava의 "achievement badge" 아이콘 스타일.
- 본문(내용)은 이모지 태그가 붙은 구조화된 요약(러닝 서머리 / R파워·강도·훈련량 / 회복시간)이지 자유 텍스트가 아님. **[SOOM 차별점]** — 이 회복시간/훈련량 라인이 Today의 4지표(신체에너지/스트레스/회복/운동강도)와 같은 데이터 축.

### 지도/사진이 있는 경우 (변형)

지도 데이터 또는 사진이 있으면 헤더 아래 지도(경로 라인, "Start and end hidden" 프라이버시 처리 포함) 또는 사진/영상(가상 라이딩 AR 오버레이 등)이 추가로 들어간다. 이 경우 상단 요약 블록에 "훈련상태" 이모지 라인(😮 훈련량 부족 (57) / 🌱 체력 13, 피로 11, 균형 2...)과 Achievements(뱃지 개수) 필드가 추가되고, 획득 배지가 있으면 "Congrats! That was your 3rd best power output for 3 minutes." 같은 축하 배너가 붙는다.

### 댓글 탭 → [Strava 동일]

전용 "Discussion" 화면(뒤로가기 / 제목 / 댓글 리스트 / 댓글 입력창)으로 이동. 피드 화면 안에서 인라인 확장이 아님.

### 공유하기 탭 → [Strava 동일]

"Share Activity" 시트. 스와이프로 넘기는 5종 공유 이미지 카드(전부 투명/체커보드 배경):
1. 큰 신발 아이콘 아웃라인 + STRAVA 로고 + 하단 통계
2. 작은 STRAVA 워드마크 + 통계
3. STRAVA 워드마크 + 통계 + Cal/AvgHR/RelativeEffort
4. STRAVA 워드마크 + 큰 엄지척 아이콘 아웃라인 + 통계
5. 브랜딩 없이 통계만 + 신발 아이콘 + STRAVA 로고

"Share to": Instagram Story / Snapchat / Copy to Clipboard / Save / Copy Link / More.

## 4. 피드 상세페이지 (Feed Detail) — 최우선 확인 영역

전체가 **[Strava 동일]** 참고 스크린샷 — Strava의 실제 "활동 상세" 화면을 통째로 가져온 것. 이 볼륨 자체가 스펙의 의도: "SOOM Activity/Feed 상세도 이 정도 깊이여야 한다"는 벤치마크로 읽어야 함.

### 헤더 영역

- 사진/영상 캐러셀(스와이프 인디케이터 ●●●) 또는 지도 — 있으면 최상단.
- "경로 영상을 시청하시겠습니까?" 같은 **경로 리플레이 영상 생성 제안**(취소/확인) — Record된 GPS로 애니메이션 영상을 만들어주는 기능, 재생 버튼 오버레이.
- 작성자/날짜/제목/구조화 요약(피드 카드와 동일 포맷) + **"Peak Paces (GAP)"**(구간 최고 페이스, 100m/400m 단위) — 피드 카드에는 없던 필드가 상세에는 추가됨.
- 통계 표: Distance / Moving Time / Avg Pace, Avg Heart Rate / Elevation Gain / Cal.
- "With someone who didn't record?" + 기기 태그(Apple Watch Series 6 / MyWhoosh / Virtual) + "Add" — **같이 운동했지만 직접 기록은 안 한 친구를 태그하는 기능**. 그룹 운동 시엔 별도 "Group Activity → Add Others" 화면(내 팔로워 검색, "Were you with someone not on Strava? → Invite Friends")으로 이어짐.
- 좋아요/댓글/공유 행.

### 본문 섹션 (스크롤 순서)

1. **Relative Effort** — 점수 + "Great job managing your effort." + Higher/3주평균/Lower 막대. "View Weekly Effort" → 최근 3주 비교 카드 3장(보라/빨강/보라, "Below weekly range" / "Well above weekly range" / "Consistent training", 각각 그 주 활동 리스트 포함). **이 카드가 위 0번 섹션의 "운동점수" SOOM 차별점 컨셉과 정확히 대응.**
2. **Pace Analysis** — 히스토그램, "View Pace Details" → Laps 화면(구간별 막대 차트).
3. **Splits** — 구간별 페이스 막대 리스트.
4. **Pace** — 페이스 추이 영역 차트.
5. **Athlete Intelligence** — AI 서술형 인사이트("Solid 7:53/km average with consistent effort across splits...") — SOOM의 "AI 해석"과 동일 개념, 이미 SOOM에도 있음.
6. 통계 표: Avg Pace / Moving Time / Avg Elapsed Pace / Elapsed Time / Fastest Split.
7. **Grade Adjusted Pace** — 경사보정 페이스 차트 + Avg GAP.
8. **Pace Zones** — 페이스 존 히스토그램("구독하면 페이스 존 분석 가능" 페이월 힌트 포함).
9. **Heart Rate** — 심박 추이 차트 + AI 인사이트 + Avg/Max Heart Rate.
10. **Heart Rate Zones** — Z1~Z5 막대(%, 시간, bpm 범위) + AI 인사이트 + "View your aggregate Heart Rate Zones"(→ 별도 집계 화면, 아래 참고).
11. (파워 기반 종목이면) **Workout Analysis / Power Curve / Power**(Avg/Total Work/Max/Weighted Avg/Training Load/Intensity) **/ Power Zones**(Z1~Z7).
12. **Speed / Cadence / Elevation** 차트(종목에 따라 표시).
13. **Results**(달성 배지 수 / 챌린지 수) 요약.

### 집계 화면(Training Zones) — 개별 활동과 별개인 화면

"View your aggregate Heart Rate/Power Zones" 링크로 진입. 종목 필터(Run/Virtual Ride 등) + 지표 필터(Heart Rate/Pace/Power) + "Exclude Commutes" + 기간 필터(7D/1M/3M/6M/YTD/1Y/커스텀) + "X% in Zone N" 헤드라인 + Zone별 막대 + "Your zones at a glance" AI 코멘트. 여러 종목·기간 조합으로 같은 레이아웃이 반복(=하나의 재사용 가능한 "Training Zones" 화면, 파라미터만 다름).

### 필터/네비게이션

"Choose a Sport" 시트(All Sports/Run/All Run/All Ride/Swim/Ride/Weight Training/Virtual Ride/Walk).

## 5. Group / Challenge — [Strava·Adidas Running 참고, 스타일 A/B 두 안 병치]

### A타입 — [Strava 동일]

Groups 탭: Active/Challenges/Clubs 세그먼트, 종목 필터 칩, 챌린지 배너 카드("February Ride 200K Challenge", Join 버튼), "Recommended For You".

### B타입 — [Adidas Running 앱 스크린샷, 참고용]

"커뮤니티" 홈: 챌린지 가로 스크롤("월간 15KM", 마감 D-19, 참가자 수), 이벤트 가로 스크롤, 커뮤니티 섹션. 하단 탭 **"피드/커뮤니티/액티비티/진행현황/프로필"** — 위 0번 섹션의 세 가지 탭 후보와도 또 다른, 네 번째 탭 구성(주의: 이건 명백히 Adidas Running 앱 고유 네비게이션이라 SOOM 채택 여부 불명, 그대로 베끼면 안 됨).

### 챌린지 상세 (B타입에서 진입) — [Adidas Running 참고 + 손글�스 요구사항 주석]

- 히어로 이미지 + "월간 15KM" + "19일 후 종료" + 참가자 수.
- "정지환님, 화이팅!" 개인화 인사 + 진행률("0/15km") + 배지 아이콘.
- "85,505명의 사용자가 챌린지를 완료했습니다" 소셜 프루프.
- "시작하기" 버튼.
- "누가 참여했을까요?" → **참가자 순위**(이름/총거리 랭킹 리스트) / **국가 순위**(국기별 총거리 랭킹) / **그룹**(참여 그룹) 3개 진입점.
- "팔로워에게 도전하기" → 초대 CTA.
- 메타 정보: 타겟(15km) / 진행기간(2/1~2/28) / 해당 스포츠 유형(러닝, 트레드밀, 걷기, 트레일 러닝, 휠체어, 버추얼 러닝) / 배지 획득 방법 / adiClub포인트(⚠️ Adidas 고유 로열티 포인트 — SOOM에 그대로 옮기면 안 되는 브랜드 종속 요소) / 세부사항.

**손글씨 요구사항 스티키노트 3장** (챌린지 생성/표시 로직에 필요한 필드 목록으로 보임):
- 🟡 "배너 타이틀 / 배너 이미지 등록 · 종목: 수영,자전거,런닝 · 제목: 월간 100km · 날짜: 2일 후 시작, 20일 후 종료 · 참가자: 12,923명"
- ⚪ "상세 내용 / 배지 아이콘 이미지 등록 · 현재진행사항 바: 23/100km 배지 · 완료 유저: 850명의 유저가 챌린지를 완료했습니다 · 참가하기 버튼 · 진행기간: 2026.3.1~2026.3.31 · 참가자 순위: 버튼"
- 🔵 "참가자 순위 상세 내용 · 참가자 순위 / 총 거리 · 1위 gaette09 / 150km · 2위 CEO / 130km · 빨간 화살표는 메뉴에 뭐가 있는지 지정하면서 화면을 유도하는 기능"

## 6. Profile("You(나)") 및 설정 — 최우선 확인 영역

### 상단 헤더

```
[<]                                    [share] [search] [⚙️ 설정]
[아바타(문장 아이콘)] jihwan CHUNG   SUBSCRIBER
Following 5    Followers 5
[Share] [QR Code] [Edit]
[사진1] [사진2] [사진3] [All media]
```

- ⚙️ 우측 상단 톱니바퀴 → **"Profile" 편집 화면** (아래 참고). 이게 스펙에서 확인되는 "설정 버튼"의 유일한 목적지.
- "Following/Followers" → **Profile / Connections 탭 화면**, "Connections" 탭 안에 다시 "Following / Followers" 서브탭 — 여기서 "Connections"는 **디바이스/서비스 연동이 아니라 소셜 팔로우 관계**를 뜻함(용어 충돌 주의). 팔로워 리스트: 아바타/이름/지역 + Following 버튼.
- "Edit" 버튼 → 위와 동일한 Profile 편집 화면으로 추정(같은 대상 두 진입점).
- 사진 X 아이콘(삭제 제스처) → "Delete Picture / Take Picture / Choose Existing / Cancel" 액션시트, 그리고 사진 상세(Grid/List 토글, 개별 사진 + "Add a description") 화면.

### "Profile" 편집 화면 (⚙️의 목적지)

```
Cancel   Profile   Save
[아바타]  jihwan
          CHUNG
Bio
City
State
Primary Sport: Cycling
— ATHLETE INFORMATION —
Select Birthdate: Jun 1, 1979
Gender: Man
Weight (kg): 70   "Used to calculate calories, power and more."
```

이름이 이름/성 두 필드로 분리, Bio/City/State/Primary Sport/생년월일/성별/체중까지 — **순수 "내 정보(개인 프로필)" 편집 화면**이지, 연동·알림·공개범위·앱정보 같은 시스템 설정은 이 화면에 없음.

### ⚠️ 중요한 공백: "연동/계정/시스템 설정" 전용 화면이 스펙에 없음

캔버스 전체를 훑었지만 ⚙️를 눌러서 나오는 화면은 위 "Profile 편집" 하나뿐이다. 다만 **간접적으로 연동 목록이 존재하는 자리**는 하나 있다 — 프로필 하단부(Strava 참고 스크린샷 블록)의 **"Data Sources" 카드**: "Here's where your activities came from in the last 30 days" + Apple Watch Series 6(마지막 사용 4일 전) / MyWhoosh(2주 전) 리스트 + "Connect a new device to Strava" + **"Manage Apps & Devices"** 링크. 이 "Manage Apps & Devices" 링크가 눌리면 이어질 실제 설정 화면(계정 관리/알림/공개범위/앱 정보 등)은 **캔버스에 붙여넣어지지 않았음** — 즉 원본 스펙은 "여기에 더 깊은 설정이 있어야 한다"는 진입점만 표시했지, 그 내부 내용은 설계하지 않은 상태다. 이건 확인이 필요한 갭이지 내가 추측해서 채울 부분이 아님.

### Profile 하단 콘텐츠 — [Strava 동일]

- 종목 필터(Swim/Run/Virtual Ride) + "This week" 주간 통계 카드(같은 컴포넌트가 Today 탭에도 등장).
- **Trophy Case**(개수 배지) — 마일스톤(150th~500th Activity) + 연도별로 그룹핑된 챌린지 뱃지("Streak to the Finish", "December Ten Days Active Challenge" 등 다수) → "All trophies" → 전체 Trophy Case 화면.
- 종목별 평균 카드(Avg {Swims/Rides}/Week, Avg Time/Week, Avg Distance/Week) — 탭으로 종목 전환.
- 이 아래로 **본인이 쓴 피드 카드들**이 그대로 나열됨(피드 카드와 완전히 같은 컴포넌트 재사용) — Profile은 "내 피드 아카이브"이기도 하다.
- 이후 Best Efforts / Monthly Activities / Fitness / Relative Effort / Data Sources 카드는 Today 탭 하단부와 동일한 세트가 여기도 반복 등장(Strava에서 Home 탭과 You 탭이 하단 콘텐츠를 공유하는 것과 같은 패턴 — 스펙 저자가 같은 참고 스크린샷을 두 군데 다 붙여넣은 것으로 보임, 의도적 중복인지는 불명).

---

## 부록: 화면 간 재사용 컴포넌트 정리

| 컴포넌트 | 등장 위치 |
|---|---|
| 구조화 요약 캡션(운동요약■/R파워·강도·훈련량/회복시간) | 피드 카드, 피드 상세, Profile 내 피드 목록 |
| 주간 스냅샷 카드(종목 필터 + 거리/시간 + 미니 차트) | Today, Profile |
| Relative Effort 카드 | 피드 상세, Today, Profile |
| Zone(HR/Power/Pace) 집계 화면 | 피드 상세("View your aggregate...") |
| Athlete Intelligence(AI 서술형 인사이트) | 피드 상세 여러 섹션(Pace/HR/Power/Zone 각각) |
| Data Sources 카드 | Today, Profile |
