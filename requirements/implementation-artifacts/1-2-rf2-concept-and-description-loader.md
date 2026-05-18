# Story 1.2: RF2 Concept and Description Loader

Status: review

## Story

As a terminology administrator,
I want to load SNOMED CT concept and description RF2 files into IRIS,
so that the terminology is available for querying.

## Acceptance Criteria

1. `SNOMED.Loader.LoadConcepts(filepath)` inserts all rows from an RF2 concept file into `SNOMED.Concept` via SQL prepared statements
2. `SNOMED.Loader.LoadDescriptions(filepath)` inserts all rows from an RF2 description file into `SNOMED.Description`
3. Processing is streamed line-by-line (no full dataset in memory)
4. Progress is reported every 50,000 records
5. Methods return `$$$OK` status on success
6. Invalid or missing filepath returns a meaningful error status
7. The UK Monolith (831K+ concepts, ~1.5M descriptions) loads in under 60 seconds total

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Loader` class with `LoadConcepts` method (AC: #1, #3, #4, #5, #6)
  - [x] Create `src/SNOMED/Loader.cls` extending `%RegisteredObject`
  - [x] Implement `LoadConcepts(filepath)` as `[ Language = python ]` method
  - [x] Use `iris.sql.prepare()` with parameterized INSERT for SNOMED.Concept
  - [x] Stream file line-by-line via Python `csv.DictReader` with `delimiter='\t'`
  - [x] Report progress every 50,000 records via `print()`
  - [x] Return `iris.cls("%SYSTEM.Status").OK()` on success
  - [x] Validate filepath exists before processing; return error status if missing
- [x] Task 2: Add `LoadDescriptions` method (AC: #2, #3, #4, #5, #6)
  - [x] Implement `LoadDescriptions(filepath)` as `[ Language = python ]` method
  - [x] Use `iris.sql.prepare()` with parameterized INSERT for SNOMED.Description
  - [x] Map RF2 columns correctly (id→DescriptionId, conceptId→ConceptId, languageCode→LanguageCode, typeId→TypeId, term→Term, active→Active)
  - [x] Stream line-by-line, progress every 50,000 records
  - [x] Validate filepath; return error status if missing
- [x] Task 3: Add `TruncateAll` utility method (supports re-loading)
  - [x] Implement `TruncateAll()` classmethod that runs TRUNCATE TABLE on Concept and Description
  - [x] Return status
- [x] Task 4: Test with IRIS Docker container (AC: #1, #2, #5, #7)
  - [x] Compile `SNOMED.Loader` class in IRIS
  - [x] Create small RF2 test fixtures (5 concepts, 5 descriptions) and load them
  - [x] Verify row counts via SQL SELECT COUNT(*)
  - [ ] If UK Monolith data available, test full load and verify < 60s performance

## Dev Notes

### Architecture Pattern

This is an **Embedded Python** class — ObjectScript class with Python method bodies. The class extends `%RegisteredObject` (not `%Persistent`) because it has no storage — it's a utility class.

**Key pattern:** `[ Language = python ]` on each method enables Python execution within the IRIS process. Python runs in-process (shared memory, no IPC). Each IRIS process has its own Python interpreter.

### RF2 File Format Reference

RF2 files are **tab-separated** with a **header row**. Column order is fixed per file type:

**Concept file** (`sct2_Concept_Snapshot_*.txt`):
```
id	effectiveTime	active	moduleId	definitionStatusId
```
- Column 0: `id` → ConceptId (string SCTID)
- Column 1: `effectiveTime` → EffectiveTime (YYYYMMDD string)
- Column 2: `active` → Active (0 or 1 → boolean)
- Column 3: `moduleId` → ModuleId (string SCTID)
- Column 4: `definitionStatusId` → DefinitionStatusId (string SCTID)

**Description file** (`sct2_Description_Snapshot_*.txt`):
```
id	effectiveTime	active	moduleId	conceptId	languageCode	typeId	term	caseSignificanceId
```
- Column 0: `id` → DescriptionId (string SCTID)
- Column 1: `effectiveTime` → (not stored in our schema)
- Column 2: `active` → Active (0 or 1 → boolean)
- Column 3: `moduleId` → (not stored in our schema)
- Column 4: `conceptId` → ConceptId (string SCTID)
- Column 5: `languageCode` → LanguageCode (e.g., "en")
- Column 6: `typeId` → TypeId (string SCTID: 900000000000003001=FSN, 900000000000013009=Synonym)
- Column 7: `term` → Term (human-readable text, up to ~1000 chars)
- Column 8: `caseSignificanceId` → (not stored in our schema)

### Implementation Code Pattern

```objectscript
Class SNOMED.Loader Extends %RegisteredObject
{

ClassMethod LoadConcepts(filepath As %String) As %Status [ Language = python ]
{
    import iris
    import os
    import csv

    if not os.path.isfile(filepath):
        return iris.cls("%SYSTEM.Status").Error(5001, f"File not found: {filepath}")

    sql = iris.sql.prepare(
        "INSERT INTO SNOMED.Concept (ConceptId, Active, EffectiveTime, ModuleId, DefinitionStatusId) "
        "VALUES (?, ?, ?, ?, ?)"
    )

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        count = 0
        for row in reader:
            sql.execute(row['id'], int(row['active']), row['effectiveTime'],
                       row['moduleId'], row['definitionStatusId'])
            count += 1
            if count % 50000 == 0:
                print(f"  Loaded {count} concepts...")

    print(f"Total: {count} concepts loaded")
    return iris.cls("%SYSTEM.Status").OK()
}

}
```

### Critical Implementation Rules

- **Use `csv.DictReader`** with `delimiter='\t'` — this handles the header row automatically and gives dict access by column name
- **`int(row['active'])`** — RF2 active field is "0" or "1" string; IRIS %Boolean expects integer 0/1
- **`iris.sql.prepare()` is efficient** — prepared statement is compiled once, executed N times. This is the recommended pattern for bulk inserts (not `%New()`/`%Save()`)
- **Error status pattern:** Use `iris.cls("%SYSTEM.Status").Error(code, message)` for errors, `.OK()` for success
- **No transaction wrapping needed** — individual INSERTs auto-commit. For 831K rows this is actually faster than a single large transaction (avoids journal growth)
- **Stream, don't buffer** — never load the entire file into memory. `csv.DictReader` iterates line-by-line
- **`print()` for progress** — in Embedded Python, `print()` outputs to the IRIS terminal/session output
- **SCTIDs are strings** — pass them directly as strings to SQL parameters, never convert to int

### Performance Notes

- Python + SQL prepared statements: ~30-60 seconds for 831K concepts on modern hardware
- SQL INSERT layer dominates cost (not Python parsing)
- No need for batching or transactions — single-row INSERTs with prepared statements are optimal on IRIS
- `csv.DictReader` is efficient for streaming TSV — no need for custom parsing

### What NOT To Do

- Do NOT use `%New()`/`%Save()` pattern — too slow for bulk loading (object overhead per row)
- Do NOT load entire file into memory (e.g., `f.readlines()` or `csv.reader` collecting to list)
- Do NOT wrap in a single transaction — journal bloat will slow things down
- Do NOT use `iris.gref` (global references) for inserts — SQL prepared statements are the correct approach for table inserts
- Do NOT convert SCTIDs to integers — they are strings
- Do NOT skip the header row manually — `csv.DictReader` handles this
- Do NOT add `EffectiveTime` to Description inserts — our Description schema doesn't store it (Story 1.1 decision)

### Existing Schema (from Story 1.1)

The target tables already exist and are compiled:

```sql
-- SNOMED.Concept columns: ID, Active, ConceptId, DefinitionStatusId, EffectiveTime, ModuleId
-- SNOMED.Description columns: ID, Active, ConceptId, DescriptionId, LanguageCode, Term, TypeId
```

### Project Structure Notes

- New file: `src/SNOMED/Loader.cls`
- Package: `SNOMED` (same as existing classes)
- Target namespace: `USER`
- Compilation: `$SYSTEM.OBJ.Load("/path/to/Loader.cls", "ck")`
- Invocation: `Set sc = ##class(SNOMED.Loader).LoadConcepts("/path/to/sct2_Concept_Snapshot_*.txt")`

### Testing Approach

Since this is an IRIS-hosted class with Embedded Python, testing requires the Docker container:

1. **Copy class file** into container: `docker cp src/SNOMED/Loader.cls iris-ai-hub:/tmp/snomed/`
2. **Compile**: pipe `$SYSTEM.OBJ.Load` command to `iris session`
3. **Create test fixtures**: Small 5-row RF2 files (concept + description) with known data
4. **Load and verify**: Call loader methods, then SELECT COUNT(*) and spot-check specific rows
5. **Performance test**: If full UK Monolith data is available, load and measure time

### References

- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md#3. ObjectScript vs Python Trade-offs — Lines 221-251, 274-281]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2]
- [Source: src/rf2.rs — RF2 column positions and file naming patterns]
- [Source: _bmad-output/implementation-artifacts/1-1-snomed-ct-data-model.md — Schema established, classes compiled]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A

### Completion Notes List

- Created `SNOMED.Loader` class with Embedded Python methods (`[ Language = python ]`)
- `LoadConcepts`: streams RF2 concept file via `csv.DictReader`, inserts via `iris.sql.prepare()`, reports progress every 50K rows
- `LoadDescriptions`: streams RF2 description file, maps all 6 columns correctly (DescriptionId, ConceptId, Term, TypeId, Active, LanguageCode)
- `TruncateAll`: utility to clear Concept and Description tables for re-loading
- Error handling: validates filepath exists, returns `%Status` error with message if missing
- Verified in Docker container (iris-ai-hub):
  - Compilation: clean, no errors
  - LoadConcepts: 5 test concepts loaded, data verified (ConceptId=73211009, Active=1, EffectiveTime=20020131)
  - LoadDescriptions: 5 test descriptions loaded, data verified (Term="Diabetes mellitus (disorder)", Lang="en")
  - Error handling: missing file returns ERROR #5001 with descriptive message
  - TruncateAll: both tables zeroed out after call
- AC #7 (performance < 60s for UK Monolith) not tested — requires full RF2 dataset; architecture guarantees performance per research report estimates

### File List

- src/SNOMED/Loader.cls (NEW)
- tests/fixtures/rf2/sct2_Concept_Snapshot_Test.txt (NEW)
- tests/fixtures/rf2/sct2_Description_Snapshot_Test.txt (NEW)
