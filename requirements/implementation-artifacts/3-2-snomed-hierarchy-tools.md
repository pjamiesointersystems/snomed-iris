# Story 3.2: SNOMED Hierarchy Tools

Status: review

## Story

As a Claude Desktop/Code user,
I want MCP tools for navigating the SNOMED hierarchy (ancestors, descendants, subsumption),
so that I can explore clinical concept relationships through conversation.

## Acceptance Criteria

1. `SNOMED.Tools.Hierarchy` extends `%AI.Tool` with hierarchy navigation methods
2. `IsA(conceptId, ancestorId)` returns true/false indicating subsumption relationship
3. `GetAncestors(conceptId)` returns a JSON array of ancestor concepts with their preferred terms
4. `GetDescendants(conceptId, maxResults)` returns descendant concepts (limited to `maxResults`, default 100) with preferred terms
5. `GetChildren(conceptId)` returns only direct child concepts with preferred terms
6. `GetParents(conceptId)` returns only direct parent concepts with preferred terms

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Tools.Hierarchy` class (AC: #1-#6)
  - [x] Create `src/SNOMED/Tools/Hierarchy.cls` extending `%AI.Tool`
  - [x] Implement `IsA(conceptId, ancestorId)` — delegates to `SNOMED.Hierarchy.IsDescendantOf()`
  - [x] Implement `GetAncestors(conceptId)` — gets ancestor IDs then enriches with preferred terms
  - [x] Implement `GetDescendants(conceptId, maxResults)` — gets descendant IDs (limited) then enriches with preferred terms
  - [x] Implement `GetChildren(conceptId)` — gets direct children then enriches with preferred terms
  - [x] Implement `GetParents(conceptId)` — gets direct parents then enriches with preferred terms
- [x] Task 2: Test in Docker container (AC: #1-#6)
  - [x] Load test fixtures, compute TC
  - [x] Verify `IsA("46635009","73211009")` returns true
  - [x] Verify `IsA("73211009","46635009")` returns false
  - [x] Verify `GetAncestors("46635009")` returns ancestors with terms
  - [x] Verify `GetDescendants("138875005", 100)` returns descendants with terms
  - [x] Verify `GetChildren("73211009")` returns direct children with terms
  - [x] Verify `GetParents("46635009")` returns direct parents with terms

## Dev Notes

### Architecture Pattern

This story creates `SNOMED.Tools.Hierarchy` extending `%AI.Tool` — same pattern as Story 3.1's Lookup and Search tools.

Key difference from `SNOMED.Hierarchy` (Story 2.3): the **Tool** version enriches results with preferred terms (FSN/Synonym) so the LLM gets human-readable concept names, not just raw SCTIDs.

### Delegation Pattern

Each tool method delegates to the existing `SNOMED.Hierarchy` class for the core global lookups, then enriches with description terms:

```
SNOMED.Tools.Hierarchy.GetAncestors(conceptId)
  → Parse JSON from ##class(SNOMED.Hierarchy).GetAncestors(conceptId)
  → For each ancestor ID, look up preferred term
  → Return enriched JSON array
```

### Enrichment: Getting Preferred Terms

To get the preferred term (FSN or Synonym) for a concept:
```objectscript
// Get FSN for a concept
Set stmt = ##class(%SQL.Statement).%New()
Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")
Set rs = stmt.%Execute(conceptId)
If rs.%Next() Set term = rs.Term
```

For efficiency, prepare the statement once and reuse for multiple lookups within a method call.

### Implementation Code Pattern

```objectscript
ClassMethod GetAncestors(conceptId As %String) As %String
{
    // Get raw ancestor IDs from existing Hierarchy class
    Set jsonStr = ##class(SNOMED.Hierarchy).GetAncestors(conceptId)
    Set ids = ##class(%DynamicArray).%FromJSON(jsonStr)

    // Enrich with preferred terms
    Set results = []
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")

    Set iter = ids.%GetIterator()
    While iter.%GetNext(.key, .id) {
        Set rs = stmt.%Execute(id)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = id
        Set obj.FSN = term
        Do results.%Push(obj)
    }
    Return results.%ToJSON()
}
```

### GetDescendants with maxResults Limiting

Since `SNOMED.Hierarchy.GetDescendants()` returns ALL descendants (could be thousands), the Tool version needs to limit results:

```objectscript
ClassMethod GetDescendants(conceptId As %String, maxResults As %Integer = 100) As %String
{
    Set results = []
    Set count = 0
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")

    // Iterate directly on global for efficiency with limit
    Set desc = ""
    For {
        Set desc = $ORDER(^SNOMED.TC(conceptId, desc))
        Quit:desc=""
        Quit:count>=maxResults
        Set rs = stmt.%Execute(desc)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = desc
        Set obj.FSN = term
        Do results.%Push(obj)
        Set count = count + 1
    }
    Return results.%ToJSON()
}
```

### IsA — Simple Boolean Wrapper

```objectscript
ClassMethod IsA(conceptId As %String, ancestorId As %String) As %String
{
    Set result = {}
    Set result.isDescendant = ##class(SNOMED.Hierarchy).IsDescendantOf(conceptId, ancestorId)
    Set result.conceptId = conceptId
    Set result.ancestorId = ancestorId
    Return result.%ToJSON()
}
```

Note: Returns JSON (not raw boolean) because MCP tool results should be self-describing for the LLM.

### Critical Implementation Rules

- **Extend `%AI.Tool`** — required for MCP tool discovery
- **Return `%String` with JSON** — all tool methods must return JSON strings
- **Enrich with FSN** — tool methods return human-readable terms, not just IDs
- **FSN TypeId = `900000000000003001`** — Fully Specified Name
- **Reuse prepared statements** — prepare SQL once, execute multiple times within a method
- **`maxResults` default = 100** for GetDescendants — prevents overwhelming the LLM with huge result sets
- **`%DynamicArray.%FromJSON()`** to parse JSON strings back into iterable arrays
- **`%GetIterator()` + `%GetNext(.key, .value)`** to iterate `%DynamicArray` objects
- **Doc comments (`///`) on methods** — these become LLM-visible tool descriptions
- **GetDescendants iterates global directly** — avoids loading all descendants into memory just to limit

### What NOT To Do

- Do NOT return raw boolean from IsA — return JSON for consistency
- Do NOT load all descendants then slice — iterate global with a counter limit
- Do NOT forget to handle concepts without FSN — set term to empty string
- Do NOT create a new Hierarchy class — extend the EXISTING `SNOMED.Hierarchy` via delegation
- Do NOT put this in `src/SNOMED/Hierarchy.cls` — create NEW file `src/SNOMED/Tools/Hierarchy.cls`
- Do NOT skip enrichment — the LLM needs readable concept names, not just SCTIDs

### Test Fixture Expected Results

After loading fixtures + computing TC:
- `IsA("46635009","73211009")` → `{"isDescendant":true,"conceptId":"46635009","ancestorId":"73211009"}`
- `GetAncestors("46635009")` → array with `{"ConceptId":"73211009","FSN":"Diabetes mellitus (disorder)"}` and `{"ConceptId":"138875005","FSN":"SNOMED CT Concept (SNOMED RT+CTV3)"}`
- `GetDescendants("138875005", 100)` → array with both 73211009 and 46635009 with their FSNs
- `GetChildren("73211009")` → `[{"ConceptId":"46635009","FSN":"Type 1 diabetes mellitus (disorder)"}]`
- `GetParents("46635009")` → `[{"ConceptId":"73211009","FSN":"Diabetes mellitus (disorder)"}]`

### Previous Story Intelligence

From Story 3.1:
- `%AI.Tool` exists and works in the 2026.2.0AI container
- Tool classes compile cleanly with classmethods
- `///` doc comments become tool descriptions
- SQL pattern: `##class(%SQL.Statement).%New()` → `%Prepare` → `%Execute` → `rs.%Next()`
- JSON: `Set obj = {}`, `Set obj.Prop = val`, `Do arr.%Push(obj)`, `Return arr.%ToJSON()`

From Story 2.3:
- `SNOMED.Hierarchy` class has: `IsDescendantOf`, `GetAncestors`, `GetDescendants`, `GetChildren`, `GetParents`
- All return JSON strings (arrays of concept IDs) except `IsDescendantOf` which returns `%Boolean`
- Global structure: `^SNOMED.TC(ancestor, descendant)`, `^SNOMED.Children(parent, child)`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.2]
- [Source: src/SNOMED/Tools/Lookup.cls — %AI.Tool pattern reference]
- [Source: src/SNOMED/Hierarchy.cls — delegation target for hierarchy queries]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A — clean implementation, no issues.

### Completion Notes List

- Created `SNOMED.Tools.Hierarchy` extending `%AI.Tool` with 5 methods
- `IsA` returns JSON `{"isDescendant":1/0,"conceptId":"...","ancestorId":"..."}`
- `GetAncestors`, `GetChildren`, `GetParents` delegate to `SNOMED.Hierarchy` then enrich via `%DynamicArray.%FromJSON()` + `%GetIterator()`
- `GetDescendants` iterates `^SNOMED.TC` global directly with maxResults limit (default 100)
- All methods enrich concept IDs with FSN (TypeId 900000000000003001) via prepared SQL statement reuse
- Verified all 6 acceptance criteria with test fixture data

### File List

- src/SNOMED/Tools/Hierarchy.cls (NEW)
