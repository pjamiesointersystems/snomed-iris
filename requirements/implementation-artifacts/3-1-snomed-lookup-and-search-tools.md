# Story 3.1: SNOMED Lookup and Search Tools

Status: review

## Story

As a Claude Desktop/Code user,
I want MCP tools that let me look up SNOMED concepts by ID and search by term,
so that I can query terminology through natural language conversation.

## Acceptance Criteria

1. `SNOMED.Tools.Lookup` extends `%AI.Tool` with a `GetConcept(sctid)` method that returns JSON with concept details (ConceptId, FSN, Active, descriptions list)
2. `SNOMED.Tools.Search` extends `%AI.Tool` with a `LexicalSearch(term, maxResults)` method that returns matching active concepts
3. Results are limited to `maxResults` (default 20) and only include active concepts
4. A Query-as-Tool `SearchByPattern` is defined as a class query returning matches in the standard `{rows, row_count, truncated}` envelope
5. Tools compile successfully and methods return correct JSON when called directly

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Tools.Lookup` class (AC: #1, #5)
  - [x] Create `src/SNOMED/Tools/Lookup.cls` extending `%AI.Tool`
  - [x] Implement `GetConcept(sctid)` classmethod returning JSON with ConceptId, FSN, Active, and descriptions array
  - [x] Query SNOMED.Concept for active status + SNOMED.Description for all active descriptions
  - [x] Return FSN (TypeId = 900000000000003001) as primary display term
  - [x] Handle concept-not-found case with meaningful JSON error
- [x] Task 2: Create `SNOMED.Tools.Search` class (AC: #2, #3, #4, #5)
  - [x] Create `src/SNOMED/Tools/Search.cls` extending `%AI.Tool`
  - [x] Implement `LexicalSearch(term, maxResults)` delegating to `##class(SNOMED.Search).Lexical()`
  - [x] Default maxResults = 20
  - [x] Add `SearchByPattern` class query using SQL LIKE pattern matching
- [x] Task 3: Test in Docker container (AC: #1-#5)
  - [x] Load test fixtures (concepts + descriptions)
  - [x] Compile both tool classes
  - [x] Verify `GetConcept("73211009")` returns correct JSON with FSN and descriptions
  - [x] Verify `GetConcept("999999999")` returns not-found error JSON
  - [x] Verify `LexicalSearch("diabetes", 20)` returns matching results
  - [x] Verify `SearchByPattern` query returns results with LIKE pattern

## Dev Notes

### Architecture Pattern

This story introduces the **`%AI.Tool`** pattern. Each tool class:
- Extends `%AI.Tool`
- Contains classmethods that become callable MCP tools
- Each method has a doc comment (`///`) that becomes the tool description for the LLM
- Returns `%String` containing JSON — the standard pattern from Stories 2.1-2.3

The tool classes delegate to existing business logic:
- `SNOMED.Tools.Lookup` → queries `SNOMED.Concept` + `SNOMED.Description` via SQL
- `SNOMED.Tools.Search` → delegates to `##class(SNOMED.Search).Lexical()`

### %AI.Tool Class Pattern

```objectscript
Class SNOMED.Tools.Lookup Extends %AI.Tool
{

/// Look up a SNOMED CT concept by its identifier (SCTID).
/// Returns concept details including the Fully Specified Name, active status, and all descriptions.
ClassMethod GetConcept(sctid As %String) As %String
{
    // Implementation
}

}
```

Key points:
- The `///` doc comment on each method becomes the tool description the LLM sees
- Method parameters become tool input parameters
- Return value is the tool result shown to the LLM
- ObjectScript methods (not Python) — required by `%AI.Tool` framework

### Query-as-Tool Pattern

Class queries defined on a `%AI.Tool` class automatically become queryable tools. The framework wraps them in the standard `{rows, row_count, truncated}` envelope:

```objectscript
Query SearchByPattern(pattern As %String, maxResults As %Integer = 50) As %SQLQuery [ SqlProc ]
{
    SELECT TOP :maxResults d.ConceptId, d.Term, d.TypeId
    FROM SNOMED.Description d
    JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId
    WHERE d.Term LIKE :pattern
    AND d.Active = 1 AND c.Active = 1
    ORDER BY d.Term
}
```

### Implementation: GetConcept

```objectscript
ClassMethod GetConcept(sctid As %String) As %String
{
    // Check concept exists
    Set sql = "SELECT ConceptId, Active, DefinitionStatusId FROM SNOMED.Concept WHERE ConceptId = ?"
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $$$ISERR(sc) Return {"error": "Prepare failed"}.%ToJSON()
    Set rs = stmt.%Execute(sctid)
    If 'rs.%Next() {
        Set err = {"error": "Concept not found", "sctid": (sctid)}
        Return err.%ToJSON()
    }

    Set result = {}
    Set result.ConceptId = rs.ConceptId
    Set result.Active = rs.Active
    Set result.DefinitionStatusId = rs.DefinitionStatusId

    // Get descriptions
    Set descSql = "SELECT Term, TypeId, Active FROM SNOMED.Description WHERE ConceptId = ? AND Active = 1 ORDER BY TypeId, Term"
    Set descStmt = ##class(%SQL.Statement).%New()
    Set sc = descStmt.%Prepare(descSql)
    Set descRs = descStmt.%Execute(sctid)
    Set descriptions = []
    Set fsn = ""
    While descRs.%Next() {
        Set desc = {}
        Set desc.Term = descRs.Term
        Set desc.TypeId = descRs.TypeId
        Set desc.Active = descRs.Active
        Do descriptions.%Push(desc)
        // FSN TypeId = 900000000000003001
        If descRs.TypeId = "900000000000003001" Set fsn = descRs.Term
    }
    Set result.FSN = fsn
    Set result.Descriptions = descriptions
    Return result.%ToJSON()
}
```

### Implementation: LexicalSearch

```objectscript
ClassMethod LexicalSearch(term As %String, maxResults As %Integer = 20) As %String
{
    // Delegate to existing SNOMED.Search.Lexical
    Return ##class(SNOMED.Search).Lexical(term, maxResults)
}
```

This is a thin wrapper. The underlying `SNOMED.Search.Lexical()` already:
- Uses iFind index for efficient full-text search
- Joins to SNOMED.Concept for Active = 1 filtering
- Returns JSON array of `{ConceptId, Term, TypeId}`
- Supports maxResults parameter

### File Structure

Per the research architecture:
```
src/SNOMED/Tools/Lookup.cls    (NEW)
src/SNOMED/Tools/Search.cls    (NEW)
```

Note the `Tools` subdirectory — this matches the planned architecture from the research doc.

### Critical Implementation Rules

- **Must extend `%AI.Tool`** — this is what makes methods discoverable as MCP tools
- **ObjectScript only** — `%AI.Tool` methods must be ObjectScript, not Python
- **Return `%String` with JSON** — tool results are serialized JSON
- **Doc comments (`///`) are tool descriptions** — write them clearly for LLM consumption
- **FSN TypeId is `900000000000003001`** — Fully Specified Name type identifier in SNOMED
- **Synonym TypeId is `900000000000013009`** — for reference
- **`SearchByPattern` uses SQL LIKE** — NOT iFind (LIKE supports wildcards the LLM can construct)
- **Query SqlProc annotation** — required for the query to be callable as a stored procedure

### What NOT To Do

- Do NOT re-implement search logic — delegate to `SNOMED.Search.Lexical()`
- Do NOT use Python for tool methods — ObjectScript is required by `%AI.Tool`
- Do NOT return raw SQL result sets — always serialize to JSON
- Do NOT forget the `///` doc comments — they ARE the tool descriptions
- Do NOT put tools in `src/SNOMED/Search.cls` or existing files — create new files in `src/SNOMED/Tools/`
- Do NOT add ToolSet or MCP Service yet — that's Story 3.3

### Test Fixture Data

From previous stories:
- Concept 73211009 (Diabetes mellitus) — Active=1
- Concept 46635009 (Type 1 diabetes) — Active=1
- Concept 138875005 (SNOMED CT Concept) — Active=1
- Concept 404684003 (Clinical finding) — Active=0 (should be excluded from searches)
- Description for 73211009: "Diabetes mellitus (disorder)" — FSN (TypeId 900000000000003001)
- Description for 73211009: "Diabetes mellitus" — Synonym (TypeId 900000000000013009)

### Previous Story Intelligence

From Story 2.3 (Hierarchy):
- ObjectScript `$DATA`/`$ORDER` patterns work perfectly
- JSON construction: `Set obj = {}`, `Set obj.Property = value`, `Do arr.%Push(obj)`, `Return arr.%ToJSON()`
- SQL statement pattern: `##class(%SQL.Statement).%New()` → `%Prepare(sql)` → `%Execute(params)` → `rs.%Next()`
- Docker testing: compile via `$SYSTEM.OBJ.Load()`, test via piped commands

From Story 2.1 (Search):
- iFind query syntax: `d.%ID %FIND search_index(TermIdx, ?, 0, '*')`
- `SNOMED.Search.Lexical(term, maxResults)` returns JSON array — can be delegated to directly

### EAP API Risk

The `%AI.Tool` and `%AI.ToolSet` classes are EAP (Early Access Program) APIs in IRIS 2026.2.0AI. If compilation fails because these classes don't exist or have different signatures, document the error and HALT — the user may need to verify the AI Hub container version.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.1]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 99-131: Tool Registration Pattern]
- [Source: src/SNOMED/Search.cls — existing lexical search to delegate to]
- [Source: src/SNOMED/Hierarchy.cls — pattern reference for ObjectScript JSON methods]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Confirmed `%AI.Tool` exists in IRIS 2026.2.0AI container (no EAP issues)
- `%AI.Tool` extends `%RegisteredObject` with `%Invoke`, `%Discover`, `%Decode`, `%Encode` methods
- SearchByPattern query compiles as `%Library.SQLQuery` — callable as stored proc `SNOMED_Tools.Search_SearchByPattern`

### Completion Notes List

- Created `SNOMED.Tools.Lookup` extending `%AI.Tool` with `GetConcept(sctid)` method
  - Queries Concept table for metadata + Description table for active descriptions
  - Identifies FSN via TypeId `900000000000003001`
  - Returns clean error JSON for not-found concepts
- Created `SNOMED.Tools.Search` extending `%AI.Tool` with:
  - `LexicalSearch(term, maxResults=20)` — thin wrapper delegating to `SNOMED.Search.Lexical()`
  - `SearchByPattern` class query — SQL LIKE pattern matching as Query-as-Tool
- Both classes compile cleanly and extend `%AI.Tool` for MCP discovery
- All acceptance criteria verified:
  - GetConcept returns FSN, Active, Descriptions array
  - Not-found returns `{"error":"Concept not found","sctid":"..."}`
  - LexicalSearch returns 2 diabetes results (excludes inactive concept)
  - SearchByPattern query exists and underlying SQL returns correct results

### File List

- src/SNOMED/Tools/Lookup.cls (NEW)
- src/SNOMED/Tools/Search.cls (NEW)
