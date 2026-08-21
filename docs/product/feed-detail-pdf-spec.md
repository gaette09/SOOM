# Feed 상세 (2) — PDF 정밀 판독

원본: `docs/product/reference/AI FITNESS.pdf`, "피드 상세페이지" 클러스터의 **"2" 배지가 붙은 스크린 플로우**(사이클링/MyWhoosh 가상 라이딩 예시, "2026-01-19 MyWhoosh - Power Passport"). `soom-original-spec.md`의 4번 섹션보다 훨씬 세밀하게 — 이 문서 하나로 재구현 가능한 수준을 목표로 함.

방법론: `pdftoppm`으로 이 컬럼만 200dpi로 다시 렌더링(포인트 좌표 x:[2900,3395] y:[900,3400], 페이지 우측 끝까지), PIL로 4등분해서 각 파트를 끝까지 읽음. 이 컬럼은 전체가 **[Strava 동일]** — 미가공 참고 스크린샷이라 손글씨 주석이 없다. 즉 이 화면 전체가 "SOOM이 이 정도 깊이로 벤치마크해야 하는 실제 Strava 활동 상세 화면"이라는 뜻으로 읽어야 함.

## 화면 전체 구조 (스크롤 순서, 정확히 21블록)

### 1. 헤더 — 지도/캐러셀

- 상태바 아래 네비게이션 바: 좌측 `<` 뒤로가기, 우측 북마크(저장) 아이콘 + `···`(더보기) 아이콘
- 지도: 경로 라인(주황), 좌하단에 축소된 미니맵 썸네일(다른 지도 스타일로 토글하는 것으로 보임), 하단 중앙에 캐러셀 페이지 인디케이터(가로 바 형태), 우하단에 원형 흰 배경 재생▶ 버튼(경로 리플레이 영상)
- **지도 위에 성취 마커가 핀으로 직접 꽂혀 있음** — SOOM 어디에도 없는 패턴: 각 마커는 트로피 아이콘 + 라벨 텍스트, 이 예시에서 2개: "3rd best power - 3 min / Lifetime", "Best power - 1 min / Lifetime". 마커는 실제 그 구간이 발생한 경로 지점에 위치.

### 2. 작성자/날짜/종목 라인

- 아바타(방패/문장 아이콘, 사진 아님) + `jihwan CHUNG`
- 그 아래 줄: 종목 아이콘(🚴) + `January 19, 2026 at 2:31 AM · Virtual` — **날짜/시간이 절대시각**(상대시간 아님), 뒤에 세션 종류(`Virtual`)가 붙음

### 3. 제목 (2줄까지 허용)

`2026-01-19 MyWhoosh - Power Passport`

### 4. 구조화 본문 — 이모지 라인 2블록

첫 블록(그날의 컨디션/훈련상태):
```
■ 1월 19일 훈련상태 ■
😐 훈련량 부족 (57)
🌍 체력 13, 피로 11, 균형 2
```
빈 줄 하나, 둘째 블록(이 활동 자체의 성격):
```
■ 라이딩 종합 ■
🐾 자유로운 훈련 (적정강도)
🟧 적정강도 훈련, 지속성과 동기부여, 즐거움...
```
`Read more...` (접힌 상태, 탭하면 펼쳐지는 것으로 추정)

**필드 단위로 보면**: 훈련상태 블록 3줄(제목/훈련량점수/체력·피로·균형) + 활동성격 블록 3줄(제목/훈련유형·강도/설명)로 정확히 대칭 구조.

### 5. 성취 배너

주황/베이지 배경 카드, 왼쪽에 브론즈 메달 아이콘, 텍스트: `Congrats! That was your 3rd best power output for 3 minutes.` — 피드 카드에도 있던 요소지만 상세에서는 지도 위 마커(1번 블록)와 **중복 표시**됨(같은 성취가 지도 마커+이 배너 두 군데 다 나옴).

### 6. 통계 그리드 (2열 × 3행, 6칸)

| 좌열 | 우열 |
|---|---|
| Distance **20.42 km** | Elevation Gain **203 m** |
| Moving Time **1:00:22** | Avg Power **108 W** |
| Avg Speed **20.3 km/h** | Calories **389 Cal** |

라벨은 회색 소문자 캡션(위), 값은 굵은 검정(아래) — 라벨/값이 같은 칸 안에서 수직 배치.

### 7. Athlete Intelligence (요약형, 첫 등장)

- 아이콘 + `Athlete Intelligence` 제목
- 본문: `Powerful virtual ride with impressive short-burst performance, hitting personal bests in 1-minute and 30-second power outputs.`
- 주황 필 버튼: `Say More` (전체 폭)

이 카드는 이후 15/17/21번에서 각 지표(파워/심박/고도)별로 **다시, 다른 문구로** 등장 — 즉 Athlete Intelligence는 한 번만 나오는 게 아니라 **섹션마다 그 섹션 전용 한두 문장이 붙는 반복 컴포넌트**.

### 8. 동승자 태그

- `With someone who didn't record?` + 우측 아웃라인 버튼 `Add Others`
- 그 아래 태그 리스트 3개(아이콘 + 텍스트, 별도 배경 없이 나열): `MyWhoosh`(연결 아이콘) / `Virtual`(태그 아이콘) / `MyWhoosh`(기기 아이콘, 아이콘만 다르고 텍스트는 반복) — 이 활동을 기록한 기기/소스를 태그처럼 나열한 것으로 보임(피드 상세(1)의 "Apple Watch Series 6" 단일 태그가 여기선 소스별로 여러 개).

### 9. 액션 바

`👍 좋아요` `💬 댓글` `↗ 공유` 3개 아이콘, 가로 배치(아이콘만, 텍스트 라벨 없음 — 상세 화면에서는 피드 카드와 달리 라벨이 생략됨).

### 10. Fitness Increased

- 제목 `Fitness Increased`
- 좌측: `Points +3` / `Fitness Score 35` (라벨/값 쌍 2개, 가로 배치)
- 우측: 작은 스파크라인 트렌드 차트(주황, 최근 상승 곡선)
- `View your Fitness trend` 링크(주황, 우측 정렬)

### 11. Relative Effort

- 제목 `Relative Effort` + 우측 큰 숫자 `29`
- 부제 `Great job managing your effort.`
- 3단 가로 컬러 바(각 구간이 곧 범례): `Higher than average`(빨강) / `Your 3-week average`(진보라) / `Lower than average`(연보라) — 우측 끝에 흰 점 마커로 오늘 값 위치 표시
- `View Weekly Effort` 링크

이 컴포넌트가 `soom-original-spec.md`에서 이미 짚은 "운동점수 → 회복 자동 설정" SOOM 차별점 컨셉과 개념적으로 정확히 대응.

### 12. Results

- 제목 `Results`
- 2×2 그리드: `Power Skills 14` / `Segments 3` / `Achievements 5` / `Challenges 1`
- `View All Results` 링크

### 13. Workout Analysis

- 제목 + 좌측 작은 아이콘
- 차트: 보라 막대(파워 구간별 시간 분포) + 회색 삼각형 오버레이(피크 지점 강조) + 회색 점선(임계값 라인), Y축 `0/100/200/300`, 좌하단 단위 라벨 `W`
- `View Workout` 링크

### 14. Power Curve

- 제목 + 좌측 아이콘
- 라인 차트(보라), Y축 `0~500`(W), X축은 **로그스케일 시간**: `0:01:00 / 0:05:00 / 0:15:00 / 0:30:00`(초/분 단위가 아니라 최대평균파워 지속시간 축 — Strava 특유의 Power Curve 표기)
- `View Power Curve` 링크

### 15. Power

- 제목 + 우측 info(ⓘ) 아이콘
- 차트: 보라 영역(파워) + 회색 오버레이(비교/평균으로 추정), Y축 `0~300`(W), X축 **거리** `5km/10km/15km`
- 통계 4행: `Avg Power 108 W` / `Total Work 390 kJ` / `Max Power 458 W` / `Weighted Avg Power 123 W` / `Training Load 104` / `Intensity 102` (실제 6행)

### 16. Power Zones

- 제목 + 우측 info 아이콘
- 부제: `Based on data from a power meter and estimated FTP of 146 W.`
- Z7~Z1 가로 막대(퍼센트 + W 범위, 색은 존이 높을수록 진한 보라):
  - Z7 `1%` `220 W+`
  - Z6 `3%` `176-219 W`
  - Z5 `6%` `154-175 W`
  - Z4 `14%` `132-153 W`
  - Z3 `9%` `111-131 W`
  - Z2 `65%` `81-110 W` (가장 긴 막대)
  - Z1 `2%` `0-80 W`
- Athlete Intelligence: `Your average power was solid, with peak efforts hitting 410W. You excelled in short bursts and sprints, setting new 30-day bests at 5s and 1:00 efforts.`
- `View your aggregate Power Zones` 링크 — **이 링크가 별도의 "Training Zones" 집계 화면(기간 필터 있는 화면, soom-original-spec.md 4번 섹션에 이미 기록)으로 연결됨을 화살표로 명시**. 그 집계 화면 예시 2장도 이 컬럼 왼쪽에 나란히 붙어있고 내용은: "30% in Zone 2"(Nov 12 2025~Today, 3M 필터) / "42% in Zone 2"(Jan 7 2026~Today, 1M 필터, "▲27% vs. prior month" 배지) — 종목 필터는 `Virtual Ride`, 지표 필터는 `Heart Rate`/`Power` 토글.

### 17. Heart Rate

- 제목 + 우측 info 아이콘
- 차트: 빨강 영역(심박) + 회색 오버레이, Y축 `100~160`(bpm), X축 `5km/10km/15km`
- Athlete Intelligence: `Your average heart rate of 124 bpm stayed comfortable, peaking at 161 bpm. You kept things controlled while still pushing into higher zones during efforts.`
- `Avg Heart Rate 124 bpm` / `Max Heart Rate 161 bpm`

### 18. Heart Rate Zones

- 부제: `Based on your max heart rate of 180 bpm.`
- Z5~Z1: `Z5 0% >176bpm` / `Z4 2% 159-175bpm` / `Z3 13% 141-158bpm` / `Z2 82% 107-140bpm`(최장) / `Z1 3% 0-106bpm`
- Athlete Intelligence: `You spent most of your time in zone 2 endurance (82%), with meaningful tempo and threshold work mixed in. A solid endurance-focused ride with intensity sprinkled throughout.`
- `View your aggregate Heart Rate Zones` 링크

### 19. Speed

- 제목만(info 아이콘 없음 — 16/17/18/20/21과 다르게 이 카드만 아이콘 없음, 확인된 그대로 기록)
- 차트: 파랑 영역 + 회색 오버레이, Y축 `0~70`(km/h), X축 `5/10/15km`
- `Avg Speed 20.3 km/h` / `Max Speed 61.3 km/h` / `Moving Time 1:00:22` / `Elapsed Time 1:00:22`(4행, Speed 카드에만 시간 정보가 다시 나옴)

### 20. Cadence

- 제목 + 우측 info 아이콘
- 차트: 마젠타/핑크 영역 + 회색 오버레이, Y축 `0~120`(rpm), X축 `5/10/15km`
- `Avg Cadence 89 rpm` / `Max Cadence 142 rpm`

### 21. Elevation

- 제목 + 우측 info 아이콘
- 차트: 회색 단색 영역(비교 오버레이 없음 — 유일하게 오버레이가 없는 차트), Y축 `0~80`(m), X축 `5/10/15km`
- Athlete Intelligence: `203m of elevation gain on a virtual ride—a moderate climbing effort that paired well with your power spikes.`
- `Elevation Gain 203 m` / `Max Elevation 72 m`

화면은 여기서 끝(카드 컨테이너 하단이 둥글게 마감됨).

## 차트 종류 요약표

| 섹션 | 차트 종류 | 오버레이 | X축 | Y축 단위 |
|---|---|---|---|---|
| Workout Analysis | 막대+삼각형 | 점선 임계값 | (시간, 라벨 없음) | W |
| Power Curve | 라인 | 없음 | 로그스케일 시간(0:01:00~0:30:00) | W |
| Power | 영역(채움) | 회색 비교 오버레이 | km | W |
| Heart Rate | 영역(채움) | 회색 비교 오버레이 | km | bpm |
| Speed | 영역(채움) | 회색 비교 오버레이 | km | km/h |
| Cadence | 영역(채움) | 회색 비교 오버레이 | km | rpm |
| Elevation | 영역(채움) | 없음 | km | m |
| Fitness Increased | 미니 스파크라인 | 없음 | (날짜, 라벨 없음) | 없음(추세만) |
| Relative Effort | 3단 가로 컬러바 | 흰 점 마커 | 없음(범주형) | 없음 |

## 반복되는 구조 패턴

1. **"카드 제목 + (선택적 info 아이콘) → 차트/막대 → (선택적 Athlete Intelligence) → 통계 목록 또는 'View X' 링크"**가 8번(Workout Analysis)부터 21번(Elevation)까지 거의 모든 섹션에서 반복되는 기본 골격.
2. **Athlete Intelligence는 전역에 한 번이 아니라 섹션마다 그 섹션 전용 문구로 반복** — 7(종합)/16(파워)/17(심박)/21(고도)에 등장, Workout Analysis/Power Curve/Speed/Cadence/Power Zones 중 Zones만 있고 Power Curve/Speed/Cadence/Workout Analysis엔 없음(=raw 차트 섹션엔 없고, "Zones"나 종합형 섹션에만 붙음).
3. **"View ~" 링크가 거의 모든 섹션 우측 하단에 붙음** — Workout/Power Curve/Weekly Effort/All Results/aggregate Power Zones/aggregate Heart Rate Zones, 6개 링크가 전부 그 섹션의 "더 깊은 버전"(별도 화면)으로 연결.
4. **차트 X축은 두 종류로 나뉨**: 시간 기반(Workout Analysis, Power Curve)과 거리 기반(Power/Heart Rate/Speed/Cadence/Elevation, 전부 동일하게 5/10/15km 눈금) — 후자 5개는 사실상 같은 차트 컴포넌트의 색상/데이터만 다른 재사용.
