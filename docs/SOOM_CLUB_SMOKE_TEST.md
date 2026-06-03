# SOOM Club Smoke Test

Purpose: validate the Club Supabase foundation in staging before TestFlight users see it. This is a manual smoke plan, not an automated migration runner.

## Test Personas

- Owner: creates and manages a club.
- Member: joins, reads, and leaves a club.
- Non-member: can browse open club metadata only.
- Admin: reserved role; write privileges are intentionally limited in v1.

## A. Open Club

Expected:

- Authenticated users can read open club metadata.
- Authenticated users can join.
- Joined members can read detail, ranking foundation, challenges, badges, and member preview.
- Non-members do not get full member-list visibility just because the club is open.
- Joined members can leave if their role is not owner.

Steps:

1. Create an open club as Owner.
2. Sign in as Non-member and confirm directory visibility.
3. Join as Member.
4. Open detail and verify member-scoped content loads.
5. Leave and confirm membership state returns to not joined.

## B. Private Club

Expected:

- Non-members cannot read private club detail.
- Private club join is restricted in v1.
- Members/owners can read private club detail.

Steps:

1. Create a private club as Owner.
2. Sign in as Non-member and attempt detail read.
3. Confirm the response is denied or not visible.
4. Confirm Owner can still read detail.

## C. Owner

Expected:

- Owner can update club fields.
- Owner can delete club.
- Delete cascades members, challenges, and badges.

Steps:

1. Create a club.
2. Update `intro` or `purpose`.
3. Add a challenge and badge.
4. Delete the club in staging.
5. Confirm child rows are removed.

## D. Member

Expected:

- Member can read joined club detail.
- Member can leave.
- Member cannot update club core fields.
- Member cannot write challenge or badge rows.

Steps:

1. Join an open club.
2. Attempt club update as Member.
3. Attempt challenge insert as Member.
4. Attempt badge insert as Member.
5. Leave the club.

## E. Challenge / Badge

Expected:

- Owner can write challenge rows.
- Owner can write club badge rows.
- Member write is denied.
- Global badges with `club_id is null` are readable only as catalog rows and are not client-writeable in v1.

Steps:

1. Insert challenge as Owner.
2. Update challenge as Owner.
3. Delete challenge as Owner.
4. Repeat insert/update/delete attempts as Member and verify denial.
5. Repeat badge write attempts.

## Smoke Test Result Format

Use this format for each run:

- Date:
- Staging project:
- Build number:
- Tester:
- Passed:
- Failed:
- Notes:
- Rollback needed:
