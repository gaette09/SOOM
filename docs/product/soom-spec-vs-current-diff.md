# SOOM 원본 스펙 vs 현재 구현 Diff

`docs/product/soom-original-spec.md`(2026-08-19 PDF 판독)와 현재 코드베이스(2026-08-20 기준, Q1~Q3 IA 배치 완료 직후)를 항목별로 대조. 검증 방식: 코드 직접 읽기(오늘 세션에서 이미 정독한 파일들 + 이번에 재확인 grep), 실행 검증은 하지 않음 — 이 문서는 순수 코드-vs-스펙 정적 대조.

범례: ✅ 이미 일치 · 🟡 부분적으로 있음(구조는 다름) · ❌ 아예 없음

---

## 0. IA / 하단 탭 구조

| 스펙 | 현재 SOOM |
|---|---|
| 5탭, 라벨 미확정이나 **첫 탭이 "오늘"(Today, AI 코치 대시보드)**, Record가 가운데 원형 액션 | 5탭 확정: **피드/활동/기록/클럽/프로필** (`RootTabView.swift:5-42`, `SOOMTab` enum 선언 순서) — **첫 탭이 피드(소셜)**, 기록이 가운데(3번째) |

**🟡 부분 일치, 핵심 불일치 1건.** Record가 가운데 위치하는 것(Strava 패턴)은 일치. 하지만 **"오늘" 탭 자체가 SOOM에 없음** — AI 코치/4지표 대시보드 개념이 진입 지점으로 존재하지 않고, 대신 Feed가 첫 진입점. 아래 1번 항목과 직결.

## 1. Today (AI 코치 대시보드)

| 스펙 요소 | 현재 SOOM |
|---|---|
| "오늘" 전용 탭, 4지표 그리드(신체에너지/스트레스/회복/운동강도) | ❌ 전용 탭 없음 |
| 회복 점수 기반 "제안" 카드(AI 운동 추천) | 🟡 `RecordLaunchRecommendation`(Record 진입 화면 상단 배너)이 있지만 `docs/SOOM_KNOWN_ISSUES.md`의 "Record Launch Guidance Copy Not Score-Driven"에 이미 기록된 대로 **고정 카피**(점수 연동 안 됨) |
| 4지표(에너지/스트레스/회복/운동강도) 개별 표시 | ❌ `RecoverySummary`(`RecoveryModels.swift:3-15`)는 **단일 점수 + status + description** 구조. 4개 축으로 분리돼 있지 않음 |
| Today 하단의 Strava 참고 카드(Goals/Training Log/Best Efforts/Fitness/Power Skills 등) | ❌ 전부 없음(스펙에서도 Strava 그대로라 우선순위 낮음, 별개로 판단 필요) |

**❌ 이 영역은 SOOM에 사실상 없음.** 현재 "회복" 개념은 Feed의 Recovery Insight 카드(`FeedFoundationCards.swift`) → `RecoveryViewContainer`로 들어가는 **보조 진입점**으로만 존재하고, 스펙처럼 앱을 열자마자 보이는 **1번 탭**이 아니다. 이건 카드 레이아웃 diff가 아니라 **IA 우선순위 diff** — Q1~Q5가 "Feed가 진짜 진입점"이라는 전제로 진행됐는데, 스펙은 "Today가 진입점, Feed는 그 다음"이라고 말하고 있어서 **전제 자체가 다르다.**

## 2. Record

| 스펙 요소 | 현재 SOOM |
|---|---|
| 지도+HUD, Start/Pause, 라이브 데이터 필드 커스터마이즈 화면 | ✅ `RecordView.swift`에 상응하는 라이브 기록 플로우 있음(이번 세션 Q1~Q5에서 실사용 확인) |
| HUD 데이터 필드 커스터마이즈(레이아웃 변경/추가/정렬삭제) | ❌ 없음 — SOOM은 고정 필드 |
| 심박수 실시간 캡처 | ❌ 없음 — Q2 조사에서 확인됨(`RecordWorkoutSession.swift`가 GPS/거리만 캡처, HR 필드 자체가 없음) — **스펙엔 실시간 심박수가 HUD 필드로 명시돼 있는데 이게 구조적으로 안 됨** |

**🟡 골격은 있으나 스펙 대비 데이터 축이 좁음.** 이건 이번 세션 Q2에서 이미 "구조적으로 불가능(심박 미수집)"으로 판정하고 범위 밖으로 뺀 것과 정확히 같은 지점 — 스펙이 그 필요성을 다시 한번 확인해준 셈.

## 3. 피드 카드 — 최우선 확인 영역

`FeedItemCard.swift`(706줄, 이번 세션 Q1에서 정독) 기준.

| 스펙 필드 | 현재 SOOM (`FeedItemCard.swift`) |
|---|---|
| 프로필 아바타(실사진/문장 아이콘) | 🟡 `FeedProfileAvatar` — 사람 실루엣 아이콘 placeholder, 실제 아바타 이미지 없음 |
| 아이디(이름) | ✅ `item.authorName` |
| 헬스케어기기(Apple Watch Series 6 등) | ❌ 없음 — 기록 소스(디바이스) 표시 필드 자체가 모델에 없음 |
| 날짜시간 | ✅ `relativeTimeText`(상대시간만, 스펙은 절대시각 "January 31, 2026 at 8:56 AM") |
| 운동종류/제목 | ✅ `feedTitle`(종목별 타이틀) |
| 구조화 요약(Running Summary■/R파워·강도·훈련량/회복시간, 이모지 태그) | ❌ 없음 — `feedBody`는 `caption ?? optionalShortStory ?? emotionalContext` 순 자유 텍스트, 스펙처럼 강도/훈련량/회복시간이 구조화된 필드로 박혀있지 않음 |
| 운동 정보(종목별로 다른 4개 통계) | ✅ `FeedReferenceMetricGrid`(거리/시간/페이스·속도/획득고도, 종목별 분기 있음) — **이 부분은 스펙과 구조적으로 가장 가까움** |
| 좋아요 / 댓글 / 공유하기 | 🟡 `FeedReferenceAction` 3개 — 但 라벨이 **응원/댓글/저장**(Cheer/Comment/Save)로 스펙(좋아요/댓글/공유하기)과 동사가 다름. 그리고 **셋 다 `Button(action: {})` — 탭해도 아무 일도 안 일어남**(더보기 버튼도 동일) |
| 댓글 탭 → 전용 Discussion 화면 | ❌ 없음(버튼 자체가 미연결) |
| 공유하기 탭 → Share Activity 시트(5종 카드 + Share to) | 🟡 공유 기능 자체는 있음(Record 완료 후 `RecordShareDraftCoordinator`, Q5에서 다룸) — **但 이건 "운동 완료 시점"에만 있고, 스펙처럼 "이미 올라온 피드 카드에서 공유 버튼을 눌러 재공유"하는 경로는 없음** |
| 지도/사진 있을 때 훈련상태 이모지 라인 + Achievements 배지 | ❌ 없음 |

**요약**: 레이아웃 골격(헤더→제목→미디어→통계→액션)은 스펙과 구조적으로 일치. 하지만 (a) 구조화된 AI 캡션 필드 부재, (b) 액션 버튼 3개가 전부 미연결(장식), (c) 디바이스/기기 표시 없음 — 이 세 가지가 실질적 격차.

## 4. 피드 카드 탭 → 상세 화면 — 최우선 확인 영역

`FeedItemDetailView.swift`(이번 세션 Q1에서 신규 작성) 기준. 스펙의 "피드 상세페이지"는 Strava 활동 상세를 통째로 요구하는 매우 깊은 화면(13개 이상 섹션 + 집계 화면 별도) — SOOM 현재 구현은 의도적으로 **얕게** 설계돼 있음(Q1 당시 결정: "sanitize된 FeedItem 필드만 그대로 렌더링, 원본 재조회 금지").

| 스펙 섹션 | 현재 SOOM (`FeedItemDetailView.swift`) |
|---|---|
| 사진/영상 캐러셀, 경로 리플레이 영상 생성 제안 | ❌ 없음 |
| Peak Paces(구간 최고 페이스) | ❌ 없음 |
| "같이 운동한 친구 태그" | ❌ 없음 |
| Relative Effort(+ 3주 비교 카드) | ❌ 없음 — SOOM의 "운동점수" 개념 자체가 아직 Feed 레벨에 없음(Today 부재와 같은 원인) |
| Pace Analysis / Splits / Pace 차트 | ❌ 없음 — `WorkoutChartStack`/`WorkoutSplitsCard`가 SOOM에 있긴 하지만(Q2에서 실데이터 배선함) 이건 **Activity 상세**(`WorkoutDetailContent.swift`) 전용이고 Feed 상세엔 연결 안 됨 |
| Athlete Intelligence(AI 서술형 인사이트) | 🟡 개념은 있음 — SOOM도 `primaryMessage`/`growthMessage`/`recoveryMessage`로 AI 생성 서술형 카피를 보여주지만, 스펙처럼 지표별(페이스별/심박별/파워별 각각)로 따로 붙지 않고 카드 전체에 3줄만 |
| Grade Adjusted Pace / Pace Zones / Heart Rate / Heart Rate Zones | ❌ 없음 |
| Power Curve / Power / Power Zones | ❌ 없음 |
| Speed / Cadence / Elevation | ❌ 없음 |
| 집계 Training Zones 화면(기간별 Zone 분포) | ❌ 없음 |

**요약**: SOOM의 Feed 상세는 스펙 대비 **의도적으로 훨씬 얕다.** 이게 "아직 안 만들어서 얕은 것"인지 "Feed는 원래 얕아야 하고 저 깊이는 Activity 상세의 몫"인지가 스펙에선 구분이 안 되는데, Q1 배치 당시 판단(ShareCardPrivacyPolicy로 sanitize된 데이터만 노출)은 여전히 유효 — 스펙의 Peak Paces/Splits/Zones 같은 raw 훈련 데이터를 Feed 상세에 그대로 노출하면 그 privacy 설계 원칙과 충돌한다. **이 부분은 diff이지만 "고쳐야 할 버그"가 아니라 "스펙과 SOOM의 프라이버시 설계가 실제로 상충하는 지점"으로 사용자 판단이 필요.**

## 5. Group / Challenge

Club 관련 코드는 `SOOM/Features/Profile/ClubsView.swift` + `ClubDomainFoundation.swift`(위치 참고: 별도 `Club` 디렉터리가 아니라 `Profile` 폴더 안에 있음).

| 스펙 요소 | 현재 SOOM |
|---|---|
| Groups 탭(Active/Challenges/Clubs 세그먼트) | 🟡 클럽 단위 화면은 있음(`ClubsView.swift`), 스펙처럼 독립된 상위 탭에서 Active/Challenges/Clubs를 가로지르는 구조는 아님 |
| "클럽 기준"(목표·규칙), "멤버 미리보기" | ✅ `ClubsView.swift:526`, `:571` |
| 클럽 내 랭킹 | ✅ `ClubsView.swift:631` |
| Challenges(진행률 중심) | 🟡 `ClubsView.swift:814` 섹션은 있으나 `docs/SOOM_KNOWN_ISSUES.md`의 "Club Challenge Engine" 항목대로 **실제 진행률 계산 엔진은 deferred**(카탈로그/카피만 존재) |
| Badge Wall | ✅ `ClubsView.swift:869` |
| 챌린지 상세(배너/진행바/참가자순위/국가순위/팔로워 초대/배지획득방법) | ❌ 없음 — 위 스펙 3개 스티키노트가 요구하는 필드(배너 타이틀/이미지, 진행 바, 완료 유저 수, 참가자 순위 버튼, 국가 순위) 전부 미구현 |
| 참가자 순위 / 국가 순위 리더보드 | ❌ 없음 — `docs/SOOM_KNOWN_ISSUES.md`의 "Club Ranking Engine" 항목과 동일한 gap |

**요약**: 스펙 쪽 Challenge는 참가/진행률/순위가 실제로 도는 완결된 소셜 경쟁 기능인데, SOOM은 카탈로그·카피 수준(foundation)까지만 있고 계산 엔진이 전부 deferred — 이건 새 발견이 아니라 **기존에 이미 알려진 gap이 스펙으로도 재확인된 것.**

## 6. Profile 및 설정 — 최우선 확인 영역, Q3와 정면 충돌

### 6-1. 상단 구조

| 스펙 요소 | 현재 SOOM (`SettingsView.swift`, 이번 세션 Q3에서 재정리) |
|---|---|
| 아바타 + 이름 + Following/Followers + Share/QR/Edit | 🟡 `ProfileSummaryCard`(`SettingsView.swift:24-33`)에 이름/handle/정체성 문구/대표뱃지/압축통계는 있으나 **Following/Followers 카운트, Share, QR Code 기능 자체가 없음** — SOOM은 아직 팔로우 그래프가 없음(`docs/SOOM_KNOWN_ISSUES.md`에 없지만 ROADMAP `feed-follows-table`가 이번 세션에 막 unblock된 상태, 아직 미구현) |
| ⚙️ 우측 상단 톱니바퀴 → "Profile 편집"(이름/Bio/City/State/종목/생년월일/성별/체중) | ❌ 이런 개인정보 편집 화면 자체가 SOOM에 없음. `authViewModel.session.currentUser?.displayName`을 표시만 하고 편집 UI 없음 |
| "Connections" 탭 = 소셜 팔로워 목록 | ❌ 없음(팔로우 그래프 자체가 없으므로) |
| Data Sources 카드(연결 기기 리스트 + Manage Apps & Devices) | 🟡 SOOM의 `connectionsSection`(`SettingsView.swift`, Q3에서 설정 블록으로 이동)이 개념적으로 제일 가까움 — HealthKit 카드 하나만 실제 연동, 나머지(Strava/Garmin/위치·날씨)는 "준비중" 플레이스홀더 |
| Trophy Case(마일스톤+연도별 챌린지 배지) | 🟡 `badgeShowcaseSection`(`SettingsView.swift:39`, `ProfileWorkoutAggregator.badges`)은 있으나 스펙처럼 연도별 그룹핑된 대량의 챌린지 배지 아카이브가 아니라 대표 뱃지 4종 정도 |
| 사진 그리드/갤러리, "All media" | ❌ 없음 |
| 본인 피드 카드 아카이브(Profile 하단에 내 피드 재나열) | ❌ 없음 |

### 6-2. ⚠️ Q3와 정면 충돌하는 지점

이번 세션 Q3(`ia-fix-q3-profile-reorganization`, 완료 상태)는 **"정체성 vs 설정을 같은 화면 안에서 헤더로만 구분"**하는 방향으로 진행했다(`SettingsView.swift`에 `identityAreaHeader`/`supportAreaHeader` 두 헤더로 한 화면 안을 2블록으로 나눔, 탭 분리는 명시적으로 기각 — "이미 5탭이 꽉 차 있다"는 이유).

**스펙은 이 판단의 전제 자체를 흔든다**:
- 스펙에서 ⚙️(설정) 버튼은 "Profile 편집"(개인정보) **하나의 작은 화면**으로만 이어진다 — SOOM의 `SettingsView.swift`처럼 계정/기준값/공개범위/알림/프로토타입/앱정보까지 다 들어있는 **14개 섹션짜리 메가 화면**이 아니다.
- 스펙에서 "정체성"(Hero/성향/기록/뱃지/Signature Routes에 해당하는 것들)과 "설정"이 애초에 **같은 화면에 공존한다는 전제 자체가 약하다** — Profile은 사실상 "내 피드 아카이브 + 통계"이고, 설정다운 설정(Data Sources 정도를 빼면)은 거의 없다.
- 즉 Q3가 풀려고 했던 문제("한 화면에 정체성 7개 + 설정 7개가 섞여있다")는 **SOOM이 자체적으로 설정 섹션을 실제 스펙보다 훨씬 많이 만들어놓은 결과**일 가능성이 높다. 스펙 기준으로 보면 정답은 "그 화면 안에서 헤더로 분리"가 아니라 **"설정다운 설정(계정/기준값/공개범위/알림/프로토타입/앱정보)을 애초에 Profile에서 들어내고, 저 ⚙️ 버튼 뒤에는 훨씬 작은 개인정보 편집 화면만 두는" 방향일 수 있다.**

**결론: 마이그레이션 계획에서 반드시 재검토 필요.** Q3에서 한 재배치(헤더 2개 추가, Connections 위치 이동)가 틀린 건 아니지만(그 자체로는 여전히 유효한 개선), 스펙 기준으로 보면 **더 큰 방향("설정 섹션들을 Profile 밖으로 빼낼지")이 아직 결정 안 된 채로 작은 재배치만 먼저 한 상태**다. 이 문서 다음 단계(마이그레이션 계획)에서 반드시 이 질문부터 사용자 확인을 받아야 함 — Q3를 되돌릴지, 그 위에 더 큰 재구조화를 얹을지.

---

## 종합 판단

1. **가장 큰 구조적 diff는 카드/화면 레이아웃이 아니라 IA 우선순위다** — 스펙은 "오늘(AI 코치)"이 1번 탭이고 Feed·Profile은 그 다음인데, SOOM은 오늘 탭 자체가 없고 Feed가 1번 탭이다. 이번 세션 Q1~Q5 전체가 "Feed가 진짜 진입점"이라는 이미 굳어진 전제 위에서 진행됐다는 점을 감안해야 함.
2. **피드 카드**는 골격은 맞는데 액션 버튼(응원/댓글/저장)이 전부 미연결이고, 구조화된 AI 캡션 필드가 없다 — 이건 스펙 준수 여부와 별개로 "지금 있는 버튼이 가짜"라는, Q1~Q4가 잡아온 패턴(배선 실수)과 같은 종류의 문제이기도 하다.
3. **피드 상세**는 의도적으로 얕게 설계돼 있고, 스펙은 Strava 수준의 깊이를 요구한다 — 근데 이건 Q1의 프라이버시 설계(ShareCardPrivacyPolicy)와 정면으로 긴장 관계에 있어서, 단순히 "더 채워넣기"로 풀 문제가 아니다.
4. **Profile/설정은 Q3와 직접 충돌** — 마이그레이션 계획 논의 시 최우선으로 다뤄야 함(위 6-2 참고).
5. **Club/Challenge**는 새로운 발견이 없고 기존 known issue(Ranking/Challenge Engine deferred)가 스펙으로 다시 확인된 정도.
