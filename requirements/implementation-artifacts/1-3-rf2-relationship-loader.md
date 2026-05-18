# Story 1.3: RF2 Relationship Loader

Status: review

## Story

As a terminology administrator,
I want to load SNOMED CT relationship RF2 files into IRIS,
so that hierarchical and associative relationships are available for querying.

## Acceptance Criteria

1. `SNOMED.Loader.LoadRelationships(filepath)` inserts all rows from an RF2 relationship file into `SNOMED.Relationship` via SQL prepared statements
2. Processing is streamed line-by-line (no full dataset in memory)
3. Progress is reported every 50,000 records
4. Only active IS-A relationships (typeId = `116680003`) are flagged for hierarchy use (printed in summary)
5. Querying `SNOMED.Relationship` by SourceId or DestinationId returns results efficiently via indexed lookups
6. Invalid or missing filepath returns a meaningful error status
7. `TruncateAll` is updated to also truncate the Relationship table

## Tasks / Subtasks

- [x] Task 1: Add `LoadRelationships` method to `SNOMED.Loader` (AC: #1, #2, #3, #4, #6)
  - [x] Implement `LoadRelationships(filepath)` as `[ Language = python ]` method
  - [x] Use `iris.sql.prepare()` with parameterized INSERT for SNOMED.Relationship
  - [x] Map RF2 columns: id→RelationshipId, sourceId→SourceId, destinationId→DestinationId, typeId→TypeId, active→Active, relationshipGroup→RelationshipGroup
  - [x] Stream line-by-line, progress every 50,000 records
  - [x] Track IS-A count (rows where typeId == "116680003" and active == "1") and print in summary
  - [x] Validate filepath exists; return error status if missing
- [x] Task 2: Update `TruncateAll` to include Relationship table (AC: #7)
  - [x] Add `TRUNCATE TABLE SNOMED.Relationship` to TruncateAll method
- [x] Task 3: Create test fixture and verify in Docker (AC: #1, #5)
  - [x] Create `tests/fixtures/rf2/sct2_Relationship_Snapshot_Test.txt` with 5 rows (mix of IS-A and non-IS-A)
  - [x] Compile updated Loader.cls in IRIS container
  - [x] Load test fixture and verify row count
  - [x] Verify indexed lookup by SourceId returns correct results
  - [x] Verify IS-A count reported correctly

## Dev Notes

### Architecture Pattern

This adds a method to the **existing** `src/SNOMED/Loader.cls` class (created in Story 1.2). Same Embedded Python pattern — `[ Language = python ]` classmethod using `iris.sql.prepare()`.

### RF2 Relationship File Format

**File:** `sct2_Relationship_Snapshot_*.txt` (or `sct2_StatedRelationship_Snapshot_*.txt`)

```
id	effectiveTime	active	moduleId	sourceId	destinationId	relationshipGroup	typeId	characteristicTypeId	modifierId
```

Column mapping to our schema:
- Column 0: `id` → RelationshipId (string SCTID)
- Column 1: `effectiveTime` → (not stored)
- Column 2: `active` → Active (0/1 → integer)
- Column 3: `moduleId` → (not stored)
- Column 4: `sourceId` → SourceId (string SCTID)
- Column 5: `destinationId` → DestinationId (string SCTID)
- Column 6: `relationshipGroup` → RelationshipGroup (integer)
- Column 7: `typeId` → TypeId (string SCTID)
- Column 8: `characteristicTypeId` → (not stored)
- Column 9: `modifierId` → (not stored)

### Key Constants

- IS-A type: `116680003` — identifies parent-child hierarchy relationships
- The AC says "flagged for hierarchy use" — this means tracking the count in the summary output, NOT creating a separate flag column

### Implementation Code Pattern

```python
ClassMethod LoadRelationships(filepath As %String) As %Status [ Language = python ]
{
    import iris
    import os
    import csv

    if not os.path.isfile(filepath):
        return iris.cls("%SYSTEM.Status").Error(5001, f"File not found: {filepath}")

    sql = iris.sql.prepare(
        "INSERT INTO SNOMED.Relationship (RelationshipId, SourceId, DestinationId, TypeId, Active, RelationshipGroup) "
        "VALUES (?, ?, ?, ?, ?, ?)"
    )

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        count = 0
        isa_count = 0
        for row in reader:
            active = int(row['active'])
            type_id = row['typeId']
            sql.execute(row['id'], row['sourceId'], row['destinationId'],
                       type_id, active, int(row['relationshipGroup']))
            count += 1
            if active == 1 and type_id == "116680003":
                isa_count += 1
            if count % 50000 == 0:
                print(f"  Loaded {count} relationships...")

    print(f"Total: {count} relationships loaded ({isa_count} active IS-A)")
    return iris.cls("%SYSTEM.Status").OK()
}
```

### Critical Rules

- **ALL relationships are loaded** (not just IS-A) — the full relationship table is needed for non-hierarchical queries too
- **IS-A tracking is informational** — print the count in summary, used by Story 2.2 (Transitive Closure) to know how many hierarchy edges exist
- **`relationshipGroup` is an integer** — convert with `int()` before passing to SQL
- **Same patterns as Story 1.2** — streaming, prepared statements, error handling, progress reporting
- **Update TruncateAll** — must include Relationship table so full re-loads work cleanly

### Existing Code to Modify

File: `src/SNOMED/Loader.cls`
- Add `LoadRelationships` method after `LoadDescriptions`
- Update `TruncateAll` to add `TRUNCATE TABLE SNOMED.Relationship`

### Target Table Schema (from Story 1.1)

```sql
-- SNOMED.Relationship columns: ID, Active, DestinationId, RelationshipGroup, RelationshipId, SourceId, TypeId
-- Indexes: RelationshipIdIdx (unique), SourceIdIdx, DestinationIdIdx, TypeIdIdx
```

### Testing Approach

Same as Story 1.2: copy to Docker, compile, load fixture, verify via SQL.

Test fixture should include:
- 3 IS-A relationships (typeId=116680003), 2 active + 1 inactive
- 2 non-IS-A relationships (e.g., finding site typeId=363698007)
- This tests that all are loaded but only active IS-A are counted

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3]
- [Source: src/rf2.rs lines 232-249 — RF2 relationship column positions]
- [Source: src/SNOMED/Loader.cls — existing class to modify]
- [Source: src/SNOMED/Relationship.cls — target table schema]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A

### Completion Notes List

- Added `LoadRelationships` method to existing `SNOMED.Loader` class
- Maps 6 RF2 columns (RelationshipId, SourceId, DestinationId, TypeId, Active, RelationshipGroup)
- Tracks active IS-A relationships (typeId=116680003) and reports count in summary
- Updated `TruncateAll` to include SNOMED.Relationship table
- Verified in Docker:
  - 5 rows loaded (3 IS-A: 2 active + 1 inactive, 2 non-IS-A)
  - IS-A count correctly reported as 2 (only active ones)
  - SourceId indexed lookup returns correct results (46635009 → 2 relationships)
  - TruncateAll clears all 3 tables

### File List

- src/SNOMED/Loader.cls (MODIFIED — added LoadRelationships, updated TruncateAll)
- tests/fixtures/rf2/sct2_Relationship_Snapshot_Test.txt (NEW)
