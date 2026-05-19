# SOOM Check-in Persistence Plan

## A. Purpose

Subjective Check-in은 사용자가 직접 느끼는 피로감, 수면감, 근육통, 기분을 짧게 기록하는 데이터다. 현재 MVP에서는 mock/in-memory store로 동작하지만, 실제 사용자 경험에서는 앱을 재실행해도 기록이 유지되어야 한다.

Check-in persistence가 필요한 이유:

- Recovery 화면에서 최신 컨디션 기록을 계속 보여준다.
- coach message와 insight 개인화를 앱 재실행 후에도 유지한다.
- 주간 컨디션 추세를 만들 수 있다.
- AI 코치 문장을 사용자의 실제 체감 데이터에 맞게 개선할 수 있다.
- v2 이후 HealthKit, 운동 기록, 수면, HRV와 결합할 주관 데이터 기반을 만든다.

## B. Data to Persist

v1에서 저장해야 할 최소 데이터:

- `id`: 로컬 식별자, UUID 권장
- `date`: 사용자가 기록한 기준 날짜
- `fatigueLevel`: 피로감, 1...5
- `sleepQuality`: 수면감, 1...5
- `muscleSoreness`: 근육통, 1...5
- `moodLevel`: 기분/컨디션, 1...5
- `note`: 선택 메모

확장 후보:

- `createdAt`: 최초 생성 시각
- `updatedAt`: 수정 시각
- `source`: manual, imported, migrated 등
- `schemaVersion`: 향후 마이그레이션 대비

## C. Storage Options

### In-memory Mock

장점:

- 구현이 가장 단순하다.
- Preview와 Unit Test에서 빠르게 사용할 수 있다.
- 저장소 protocol 설계를 검증하기 좋다.

단점:

- 앱 재실행 후 데이터가 사라진다.
- 실제 사용자 경험을 검증할 수 없다.
- 주간 추세나 장기 개인화에 사용할 수 없다.

SOOM v1 적합도: 테스트/프리뷰 전용으로 적합하다. 실제 v1 저장 방식으로는 부적합하다.

마이그레이션 난이도: 낮음. `RecoveryCheckInStore` 구현체만 교체하면 된다.

### UserDefaults

장점:

- 구현이 쉽고 의존성이 적다.
- 소량의 단순 데이터 저장에 빠르게 적용할 수 있다.
- 별도 schema 설계 부담이 작다.

단점:

- 사용자 건강 관련 기록을 장기적으로 보관하기에는 구조가 약하다.
- 쿼리, 정렬, 수정, 삭제, 마이그레이션이 복잡해질 수 있다.
- check-in이 누적되면 관리가 어려워진다.

SOOM v1 적합도: 아주 빠른 MVP에는 가능하지만, Recovery가 핵심 기능으로 성장할 앱에는 권장하지 않는다.

마이그레이션 난이도: 중간. JSON 배열을 SwiftData 모델로 옮기는 one-time migration이 필요할 수 있다.

### JSON File Storage

장점:

- 로컬 우선 저장을 명확하게 구현할 수 있다.
- 데이터 구조가 투명하고 디버깅이 쉽다.
- 서버/DB 없이도 앱 재실행 후 persistence를 제공할 수 있다.
- Codable 기반 테스트가 쉽다.

단점:

- 동시성, 파일 손상, partial write 방어를 직접 설계해야 한다.
- 쿼리/정렬/수정/삭제가 늘어나면 저장소 코드가 커진다.
- iCloud/Server sync로 확장할 때 별도 migration이 필요하다.

SOOM v1 적합도: 작고 빠른 로컬 MVP에는 적합하다. 다만 장기적으로 iOS Native 데이터 모델을 키울 계획이라면 SwiftData보다 과도기 성격이 강하다.

마이그레이션 난이도: 중간. JSON schema version을 두면 SwiftData 또는 서버 동기화로 옮기기 쉽다.

### SwiftData

장점:

- iOS Native 앱 방향과 잘 맞는다.
- 모델, 쿼리, 정렬, 수정, 삭제를 구조적으로 관리할 수 있다.
- Workout, Recovery, Check-in 같은 앱 내부 데이터 모델이 늘어날 때 확장성이 좋다.
- 향후 iCloud/CloudKit 기반 확장을 검토하기 쉽다.

단점:

- 초기 schema와 migration 정책을 더 신중히 잡아야 한다.
- 테스트 환경 구성이 JSON/UserDefaults보다 조금 복잡하다.
- 최소 지원 OS와 SwiftData 안정성 정책을 확인해야 한다.

SOOM v1 적합도: 높음. SOOM이 Native iOS/SwiftUI 앱이고 Recovery 데이터가 장기적으로 커질 가능성이 높기 때문에 v1의 우선 후보로 적합하다.

마이그레이션 난이도: 낮음에서 중간. 처음부터 SwiftData로 시작하면 이후 모델 변경 관리가 비교적 명확하다.

### Cloud / Server

장점:

- 기기 간 동기화가 가능하다.
- AI 코칭, 장기 분석, 백업, 계정 기반 경험으로 확장하기 쉽다.
- 서버 계산 모델과 결합할 수 있다.

단점:

- 개인정보/건강 관련 데이터 동의와 보안 설계가 필요하다.
- 인증, 네트워크 실패, 충돌 해결, 삭제 요청 처리가 필요하다.
- v1 초기 MVP에는 구현 범위가 크다.

SOOM v1 적합도: 낮음. v1에서는 로컬 우선 저장을 먼저 완성하고, 동기화는 v2/v3에서 검토한다.

마이그레이션 난이도: 높음. 로컬 데이터와 서버 데이터의 병합/충돌 정책이 필요하다.

## D. Recommendation

SOOM v1의 추천 방향은 SwiftData 우선 검토다.

이유:

- SOOM은 Native iOS 앱이며 SwiftUI 기반으로 개발한다.
- Check-in은 단순 설정값이 아니라 사용자의 컨디션 기록이다.
- Recovery, Workout, AI Coach가 확장될수록 로컬 데이터 모델이 중요해진다.
- 수정/삭제/주간 추세/향후 iCloud 확장까지 고려하면 SwiftData가 더 자연스럽다.

대안:

- SwiftData 도입 일정이 부담되면 JSON file storage를 v1 임시 persistence로 사용할 수 있다.
- 단, JSON file storage를 선택하더라도 `RecoveryCheckInStore` protocol 뒤에 숨기고, SwiftData migration을 염두에 둔다.

권장 결론:

- v1 production 후보: `SwiftDataCheckInStore`
- v1 빠른 검증 후보: `LocalPersistentCheckInStore` using JSON file storage
- 계속 유지: `MockRecoveryCheckInStore` for tests/previews

앱 전역 SwiftData 연결 순서와 ViewModel 주입 전략은 [SOOM_SWIFTDATA_INTEGRATION_PLAN.md](SOOM_SWIFTDATA_INTEGRATION_PLAN.md)를 기준으로 진행한다.

## E. Repository / Store Strategy

현재 유지할 원칙:

- `RecoveryCheckInStore` protocol은 유지한다.
- `RecoveryCheckInWritableStore` protocol은 저장 액션을 추상화한다.
- `MockRecoveryCheckInStore`는 테스트와 Preview 전용으로 둔다.
- `RecoveryViewModel`과 `CheckInViewModel`은 concrete storage를 직접 알지 않는다.
- ViewModel은 store protocol에만 의존한다.

v1 구현 후보:

- `SwiftDataCheckInStore`
  - SwiftData model을 사용해 check-in을 저장/조회/삭제한다.
  - `RecoveryCheckInStore`, `RecoveryCheckInWritableStore`를 채택한다.

- `LocalPersistentCheckInStore`
  - JSON file storage 기반 임시 구현체다.
  - SwiftData 도입 전 앱 재실행 persistence 검증에 사용할 수 있다.

Store 책임:

- 최근 check-in 조회
- 새 check-in 저장
- 향후 수정/삭제
- 1...5 범위 보정은 domain model에서 유지
- 저장 실패를 ViewModel이 사용자 친화 메시지로 바꿀 수 있게 error를 전달

수정/삭제 정책:

- 사용자는 자신이 입력한 check-in 기록을 삭제할 수 있어야 한다.
- v1 수정 기능은 최신 기록 중심으로 우선 제공한다. 과거 기록 전체 편집은 사용 빈도와 UX 복잡도를 확인한 뒤 확장한다.
- 전체 삭제는 설정/개인정보 메뉴의 후보 기능으로 둔다.
- 서버 동기화 전에는 로컬 SwiftData 저장소가 source of truth다. 로컬에서 삭제된 기록은 Recovery 화면, coach message, insight 개인화 입력에서도 제거된 것으로 본다.
- 삭제는 사용자가 부담 없이 할 수 있어야 하지만, 전체 삭제처럼 되돌리기 어려운 동작에는 짧은 확인 문구가 필요하다.

## F. Migration Path

1. Mock to Local Persistent Store
   - `MockRecoveryCheckInStore.shared`를 production flow에서 제거한다.
   - `CheckInViewModel`과 `RecoveryViewModel`에 같은 local store 구현체를 주입한다.
   - 앱 재실행 후 최신 check-in summary가 유지되는지 확인한다.

2. Local Persistent Store to iCloud/Server Sync
   - 로컬 데이터를 source of truth로 유지한다.
   - 명확한 동의 후 서버/클라우드 동기화를 추가한다.
   - 충돌 해결 기준은 `updatedAt`과 device/source metadata를 사용한다.

3. v2/v3 Data Merge
   - Check-in 데이터를 HealthKit, Workout, sleep, HRV와 결합한다.
   - `RecoveryInputContext` 또는 별도 input builder에서 병합한다.
   - score formula에 반영하기 전 Unit Test를 먼저 추가한다.

## G. Privacy / Trust

Check-in은 사용자가 직접 입력한 주관 컨디션 데이터이며, 건강 관련 민감 데이터처럼 다뤄야 한다.

원칙:

- 로컬 우선 저장을 기본으로 한다.
- 서버 동기화는 명확한 사용자 동의 후에만 진행한다.
- 사용자는 check-in 기록을 삭제할 수 있어야 한다.
- 의료 진단처럼 표현하지 않는다.
- 데이터 사용 목적을 “회복 추천 개인화”로 명확히 설명한다.
- note에는 민감한 자유 입력이 들어갈 수 있으므로 향후 서버 전송 시 별도 동의와 보호 정책이 필요하다.

사용자 신뢰 카피 후보:

- “컨디션 기록은 회복 추천을 더 개인화하는 데 사용됩니다.”
- “기록은 우선 기기 안에 저장됩니다.”
- “언제든 기록을 삭제할 수 있어야 합니다.”
- “의료 진단이 아닌 운동 컨디션 참고용입니다.”

## H. Implementation Plan

### Phase 1: Documentation

- Persistence 옵션과 추천 방향을 문서화한다.
- Data Contract와 UX Spec에서 이 문서를 참조한다.

### Phase 2: SwiftData Model Design

- `CheckInRecord` SwiftData model 초안을 만든다.
- `RecoveryCheckIn` domain model과 SwiftData model의 mapper를 설계한다.
- schema version, createdAt, updatedAt 필드를 검토한다.

구현 상태:

- `CheckInRecord` 초안 구현 완료.
- `RecoveryCheckInPersistenceMapper` 초안 구현 완료.
- `RecoveryCheckIn` domain model과 SwiftData persistence model은 분리되어 있다.

### Phase 3: SwiftDataCheckInStore Implementation

- `RecoveryCheckInStore`와 `RecoveryCheckInWritableStore`를 채택한다.
- 최근 check-in 조회와 append 저장을 구현한다.
- 테스트에서는 in-memory SwiftData container를 사용한다.

구현 상태:

- `SwiftDataCheckInStore` 초안 구현 완료.
- `ModelContext` 주입 기반으로 설계했다.
- 앱 전역 `ModelContainer`는 `SOOMApp.swift`에 `.modelContainer(for: CheckInRecord.self)`로 연결했다.
- 아직 `CheckInViewModel` 기본 store로 교체하지 않았다.
- production 화면에서는 `CheckInViewContainer`와 `RecoveryViewContainer`를 통해 저장/읽기 모두 SwiftData store를 사용할 수 있다.
- `CheckInViewModel`과 `RecoveryViewModel`의 기본 store는 Preview/Test/rollback을 위해 아직 mock 기반으로 유지한다.

### Phase 4: CheckInViewModel Integration

- `CheckInViewModel`이 production flow에서 SwiftData store를 사용하도록 연결한다.
- `RecoveryViewModel`과 같은 store 원천을 보도록 구성한다.
- 실제 앱 연결은 [SOOM_SWIFTDATA_INTEGRATION_PLAN.md](SOOM_SWIFTDATA_INTEGRATION_PLAN.md)의 단계형 rollout을 따른다.

준비 상태:

- `CheckInViewModelFactory`를 추가해 ViewModel 생성 지점을 분리했다.
- 현재 factory는 mock store를 사용하므로 기존 UX와 저장 흐름은 유지된다.
- Phase 4에서는 이 factory 또는 production entry point에서 `SwiftDataCheckInStore`를 명시 주입하는 방식으로 전환한다.

구현 상태:

- `CheckInViewContainer`를 통해 production Check-in 저장 흐름은 `SwiftDataCheckInStore`를 사용한다.
- `CheckInView()` 기본 흐름, Preview, 테스트는 mock store를 계속 사용할 수 있다.
- `RecoveryViewContainer`를 통해 production Recovery latest check-in 읽기/표시 흐름도 `SwiftDataCheckInStore`를 사용한다.
- Check-in 저장과 Recovery 표시가 같은 앱 전역 SwiftData source of truth를 공유한다.
- Check-in 데이터는 score/status/recommendation에는 반영하지 않고, 최신 요약 표시와 coach message/insight 개인화에만 사용한다.

### Phase 5: Recovery Latest Check-in Read Integration

- `RecoveryViewContainer`에서 `@Environment(\.modelContext)`를 읽어 `SwiftDataCheckInStore`를 만든다.
- `RecoveryViewModel`에는 `checkInStore`로 SwiftData store를 주입한다.
- Home의 회복 진입은 container를 통해 들어간다.
- 기본 mock init은 rollback, Preview, Unit Test 안정성을 위해 유지한다.

구현 상태:

- 완료.

### Phase 6: Tests

- 저장 후 fetch 테스트
- 앱 재실행에 가까운 store 재생성 테스트
- 빈 데이터 처리 테스트
- 저장 실패 처리 테스트
- note 포함/미포함 테스트

### Phase 7: Delete / Edit Support

- 최신 기록 수정
- 특정 날짜 기록 삭제
- 전체 check-in 데이터 삭제
- 향후 계정 삭제/데이터 export 정책과 연결

준비 상태:

- `RecoveryCheckInEditableStore` 계약을 추가했다.
- `SwiftDataCheckInStore`와 `MockRecoveryCheckInStore`는 `updateCheckIn(_:)`, `deleteCheckIn(id:)`, `deleteAllCheckIns()`를 지원한다.
- 아직 수정/삭제 UI는 만들지 않는다.
- Recovery score/status/recommendation 계산에는 영향을 주지 않는다.

### Phase 8: Check-in History MVP

- 저장된 check-in 기록을 목록으로 확인하는 조회 전용 화면을 추가한다.
- production 흐름에서는 `SwiftDataCheckInStore`에서 최근 기록을 읽는다.
- 기록 목록은 날짜, 피로감, 수면감, 근육통, 기분, 선택 메모만 표시한다.
- 수정/삭제 UI는 아직 연결하지 않는다.
- Recovery score/status/recommendation 계산에는 영향을 주지 않는다.

구현 상태:

- `CheckInHistoryView`, `CheckInHistoryViewModel`, `CheckInHistoryViewContainer` 추가 완료.
- Recovery 화면에서 “컨디션 기록 보기” 진입을 제공한다.
- ViewModel 로딩/빈 상태/오류 상태 테스트를 추가했다.

### Phase 9: Check-in Detail MVP

- History 목록에서 개별 기록을 눌러 상세 내용을 확인할 수 있게 한다.
- 상세 화면은 날짜, 피로감, 수면감, 근육통, 기분, 전체 메모, 코칭 개인화 안내를 표시한다.
- 메모가 없으면 부드러운 빈 상태를 표시한다.
- 이 단계는 조회 전용이며 수정/삭제 버튼은 연결하지 않는다.

구현 상태:

- `CheckInDetailView` 추가 완료.
- `CheckInHistoryView`의 각 기록을 `NavigationLink`로 상세 화면에 연결했다.

### Phase 10: Check-in Edit MVP

- Detail 화면 우측 상단에서 기존 check-in을 수정할 수 있다.
- 수정 가능 필드는 피로감, 수면감, 근육통, 기분, 메모다.
- SwiftData `updateCheckIn(_:)` 흐름을 사용해 기존 기록의 `id`와 `date`를 유지하고 값만 갱신한다.
- 수정 후 Detail 화면은 갱신된 값을 즉시 표시한다.
- Recovery score/status/recommendation은 수정된 check-in에 의해 변경되지 않는다.
- coach message와 insight 개인화 문구는 Recovery 화면 재로드 시 최신 check-in 기준으로 업데이트될 수 있다.
- 삭제 UI는 아직 제공하지 않는다.

구현 상태:

- `CheckInEditView`, `CheckInEditViewModel`, `CheckInEditViewContainer` 추가 완료.
- 신규 기록과 수정 화면이 같은 5단계 선택 패턴을 쓰도록 `CheckInScaleSelector`를 공통화했다.
- `CheckInDetailView`에서 “수정하기” 진입을 제공한다.
- 수정 완료 시 Detail 화면과 History 목록 row가 같은 `RecoveryCheckIn` 값으로 갱신된다.

### Phase 11: Check-in Delete MVP

- Detail 화면의 관리 메뉴에서 개별 check-in을 삭제할 수 있다.
- 삭제 전 `confirmationDialog`로 “이 기록을 삭제할까요?”를 확인한다.
- 안내 문구는 “삭제해도 회복 점수는 다시 계산되지 않아요.”처럼 v1 score 정책을 부드럽게 설명한다.
- 삭제 성공 시 History 화면으로 돌아가고, 목록에서 해당 기록을 제거한다.
- SwiftData `deleteCheckIn(id:)` 흐름을 사용하며, 존재하지 않는 id 삭제는 안전하게 no-op 처리한다.
- 전체 삭제 UI는 아직 제공하지 않는다.
- Recovery score/status/recommendation은 삭제에 의해 즉시 재계산하지 않는다.

구현 상태:

- `CheckInDetailView` 관리 메뉴에 “삭제하기” 추가 완료.
- 삭제 상태와 오류 처리는 `CheckInDetailViewModel`이 담당하고, `CheckInDetailView`는 confirmation dialog와 화면 표시만 맡는다.
- `CheckInHistoryViewModel.removeCheckIn(id:)`로 삭제 후 목록을 즉시 갱신한다.
- 개별 삭제 및 존재하지 않는 id 삭제 안전성 테스트를 추가했다.

### Phase 12: Recovery Refresh after Check-in Changes

- Check-in 저장/수정/삭제 후 Recovery 화면으로 돌아오면 `RecoveryViewModel.refreshCheckInPersonalization()`을 통해 SwiftData source of truth에서 latest check-in을 다시 읽는다.
- 이 refresh는 loading card를 다시 띄우는 전체 reload가 아니라 latest check-in, coach message, insight 개인화만 조용히 갱신하는 흐름이다.
- latest check-in이 수정되면 새 값 기준으로 coach message와 insight가 다시 구성될 수 있다.
- latest check-in이 삭제되면 다음 최신 기록을 사용하고, 남은 기록이 없으면 latest check-in 요약과 check-in 기반 개인화를 제거한다.
- Recovery score/status/recommendation은 수정/삭제 후에도 변경하지 않는다.

구현 상태:

- `RecoveryView.onAppear`에서 `refreshCheckInPersonalization()`을 호출한다.
- `RecoveryViewModel`은 `baseSummary`를 유지한 상태에서 latest check-in만 다시 fetch하고 `RecoverySummaryComposer`를 재적용한다.
- 수정/삭제 후 refresh 테스트를 추가했다.

## Decision Summary

SOOM v1은 SwiftData 기반 로컬 저장을 우선 검토한다. JSON file storage는 SwiftData 도입 전 빠른 persistence 검증용 대안으로만 둔다. 어떤 방식을 선택하더라도 ViewModel은 store protocol에만 의존하며, Check-in 데이터는 v1.5에서 score/status/recommendation을 바꾸지 않고 coach message와 insights 개인화에만 사용한다.
