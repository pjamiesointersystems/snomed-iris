# Story 2.1: Full-Text Lexical Search

Status: review

## Story

As a terminology user,
I want to search for SNOMED concepts by keyword or phrase across description terms,
so that I can find relevant concepts without knowing their exact identifiers.

## Acceptance Criteria

1. A text search index exists on `SNOMED.Description.Term` enabling efficient full-text queries
2. `SNOMED.Search.Lexical(term, maxResults)` returns matching active descriptions with ConceptId, Term, and TypeId
3. Results include only active concepts (joined to `SNOMED.Concept.Active = 1`)
4. Results are ordered by relevance (exact matches first, then partial matches)
5. Search performs efficiently against 1.5M+ descriptions
6. Default maxResults is 25; caller can override

## Tasks / Subtasks

- [x] Task 1: Add iFind text index to `SNOMED.Description.Term` (AC: #1, #5)
  - [x] Add `Index TermIdx On (Term) As %iFind.Index.Basic` to Description.cls
  - [x] Recompile Description class in IRIS and verify index builds
- [x] Task 2: Create `SNOMED.Search` class with `Lexical` method (AC: #2, #3, #4, #6)
  - [x] Create `src/SNOMED/Search.cls` extending `%RegisteredObject`
  - [x] Implement `Lexical(term, maxResults)` as ObjectScript classmethod
  - [x] Query uses `search_index(TermIdx, ?)` predicate against the iFind index
  - [x] JOIN to SNOMED.Concept to filter Active = 1
  - [x] Order results: exact Term match first, then by iFind relevance
  - [x] Return results as JSON array of objects {ConceptId, Term, TypeId}
  - [x] Default maxResults = 25
- [x] Task 3: Test search in Docker container (AC: #2, #3, #4)
  - [x] Load test fixtures (concepts + descriptions from Story 1.2)
  - [x] Search for "diabetes" and verify results include matching terms
  - [x] Verify inactive concepts are excluded from results
  - [x] Verify result format is valid JSON array

## Dev Notes

### Architecture Pattern

This story introduces two changes:
1. **Schema modification** — adding an iFind index to existing `Description.cls`
2. **New utility class** — `SNOMED.Search` with ObjectScript classmethod returning JSON

The Search class uses **ObjectScript** (not Python) because:
- SQL query construction and result formatting is straightforward in ObjectScript
- Runtime query methods should be ObjectScript for MCP tool exposure in Story 3.1
- The research report recommends ObjectScript for "runtime lookups" and "hierarchy traversal"

### iFind Text Index in IRIS

IRIS provides `%iFind.Index.Basic` for full-text search. Adding it to a property creates a searchable text index.

**Syntax in class definition:**
```objectscript
Index TermIdx On (Term) As %iFind.Index.Basic;
```

**SQL query using iFind:**
```sql
SELECT d.ConceptId, d.Term, d.TypeId
FROM SNOMED.Description d
JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId
WHERE d.Term %CONTAINSTERM :searchTerm
AND d.Active = 1
AND c.Active = 1
ORDER BY CASE WHEN d.Term = :exactTerm THEN 0 ELSE 1 END, d.Term
```

**Alternative — use `%CONTAINS` for multi-word phrase search:**
```sql
WHERE d.Term %CONTAINS :searchPhrase
```

- `%CONTAINSTERM` — matches individual terms (words) within the indexed text
- `%CONTAINS` — matches phrases or boolean expressions

### ObjectScript JSON Pattern

IRIS provides `%DynamicArray` and `%DynamicObject` for JSON construction:

```objectscript
ClassMethod Lexical(term As %String, maxResults As %Integer = 25) As %String
{
    Set results = []
    Set sql = "SELECT TOP ? d.ConceptId, d.Term, d.TypeId "
             _"FROM SNOMED.Description d "
             _"JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId "
             _"WHERE d.Term %CONTAINSTERM ? "
             _"AND d.Active = 1 AND c.Active = 1 "
             _"ORDER BY CASE WHEN d.Term = ? THEN 0 ELSE 1 END, d.Term"
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $$$ISERR(sc) Return {"error": ($System.Status.GetErrorText(sc))}.%ToJSON()
    Set rs = stmt.%Execute(maxResults, term, term)
    While rs.%Next() {
        Set obj = {}
        Set obj.ConceptId = rs.ConceptId
        Set obj.Term = rs.Term
        Set obj.TypeId = rs.TypeId
        Do results.%Push(obj)
    }
    Return results.%ToJSON()
}
```

### Critical Implementation Rules

- **iFind index type is `%iFind.Index.Basic`** — NOT `%iFind.Index.Analytic` (which adds stemming/thesaurus complexity we don't need)
- **Return type is `%String`** containing JSON — this is the standard pattern for methods that will become MCP tools (Story 3.1)
- **JOIN is required** — must filter by `SNOMED.Concept.Active = 1` to exclude inactive concepts, not just inactive descriptions
- **Both Active checks** — `d.Active = 1 AND c.Active = 1` (a description can be active on an inactive concept)
- **`%CONTAINSTERM`** matches individual words; for multi-word queries, `%CONTAINS` with the full phrase will match descriptions containing all words
- **TOP clause** — use `SELECT TOP ?` with maxResults parameter for efficient limiting
- **No `%New()`/`%Save()` needed** — this is a read-only query class
- **ObjectScript string concatenation** uses `_` operator

### What NOT To Do

- Do NOT use SQL `LIKE '%term%'` — this bypasses the text index and does a full table scan
- Do NOT use Python for this method — ObjectScript is correct for runtime query methods
- Do NOT add the iFind index to ConceptId or other non-text fields
- Do NOT return raw SQL result sets — return JSON string for MCP tool compatibility
- Do NOT forget the Concept.Active JOIN — inactive concepts must be excluded even if their descriptions are active
- Do NOT use `%iFind.Index.Analytic` — it's heavier and not needed for keyword matching

### Existing Schema (Story 1.1)

```
SNOMED.Description: DescriptionId (unique), ConceptId (indexed), Term (MAXLEN=1024), TypeId (indexed), Active, LanguageCode
SNOMED.Concept: ConceptId (unique), Active (bitmap), EffectiveTime, ModuleId, DefinitionStatusId
```

### Project Structure Notes

- Modified file: `src/SNOMED/Description.cls` (add iFind index)
- New file: `src/SNOMED/Search.cls`
- Package: `SNOMED`
- Target namespace: `USER`

### Testing Approach

1. Reload test fixtures (TruncateAll + LoadConcepts + LoadDescriptions from Story 1.2 fixtures)
2. Test fixture has concept 404684003 with Active=0 — searching for its description term should NOT return it
3. Search for "diabetes" should return concepts 73211009 and 46635009
4. Verify JSON output is parseable

### Previous Story Intelligence

From Stories 1.1-1.3:
- Docker container: `iris-ai-hub`
- Compilation: `$SYSTEM.OBJ.Load("/tmp/snomed/file.cls", "ck")`
- Testing pattern: pipe commands to `iris session IRIS -U USER`
- Property access on result sets: `rs.PropertyName` (not `rs.%Get("name")`)
- `iris.sql.exec()` for DDL, `iris.sql.prepare()` for DML (Python)
- ObjectScript: `##class(%SQL.Statement).%New()` + `%Prepare` + `%Execute` for queries

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.1]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — line 503: "IRIS SQL + iFind/BM25 text index"]
- [Source: src/commands/lexical.rs — existing Rust lexical search for feature parity reference]
- [Source: src/SNOMED/Description.cls — target for iFind index addition]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Initial attempt with `%CONTAINSTERM ?` failed (SQLCODE -1, parameters not supported with %CONTAINSTERM)
- `%CONTAINSTERM('literal')` failed (SQLCODE -400)
- Correct iFind syntax discovered: `%ID %FIND search_index(TermIdx, ?, 0, '*')` — supports parameters

### Completion Notes List

- Added `%iFind.Index.Basic` index on Description.Term — compiles to helper class `SNOMED.Description.tlDkRw`
- Created `SNOMED.Search` class with ObjectScript `Lexical(term, maxResults)` method
- iFind query uses `d.%ID %FIND search_index(TermIdx, ?, 0, '*')` — the correct parameterized syntax for iFind
- JOIN to SNOMED.Concept ensures inactive concepts excluded (`c.Active = 1`)
- Results ordered: exact match first (CASE WHEN d.Term = ? THEN 0 ELSE 1 END), then alphabetical
- Returns valid JSON array: `[{"ConceptId":"...","Term":"...","TypeId":"..."},...]`
- Verified: "diabetes" returns 2 results (73211009, 46635009); inactive concept 404684003 excluded

### File List

- src/SNOMED/Description.cls (MODIFIED — added TermIdx iFind index)
- src/SNOMED/Search.cls (NEW)
