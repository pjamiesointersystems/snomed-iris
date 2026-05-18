# Story 2.3: Hierarchy Navigation Methods

Status: review

## Story

As a terminology user,
I want to query ancestors, descendants, and check subsumption for any SNOMED concept,
so that I can navigate the terminology hierarchy programmatically.

## Acceptance Criteria

1. `SNOMED.Hierarchy.IsDescendantOf(conceptId, ancestorId)` returns true/false in O(1) via global lookup
2. `SNOMED.Hierarchy.GetAncestors(conceptId)` returns all ancestor concept IDs as a JSON array
3. `SNOMED.Hierarchy.GetDescendants(conceptId)` returns all descendant concept IDs as a JSON array
4. `SNOMED.Hierarchy.GetChildren(conceptId)` returns only direct children (from `^SNOMED.Children`)
5. `SNOMED.Hierarchy.GetParents(conceptId)` returns only direct parents

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Hierarchy` class with all navigation methods (AC: #1-#5)
  - [x] Create `src/SNOMED/Hierarchy.cls` extending `%RegisteredObject`
  - [x] Implement `IsDescendantOf(conceptId, ancestorId)` — O(1) `$DATA` check on `^SNOMED.TC`
  - [x] Implement `GetAncestors(conceptId)` — `$ORDER` iteration over `^SNOMED.TC` second subscript
  - [x] Implement `GetDescendants(conceptId)` — `$ORDER` over `^SNOMED.TC(conceptId, "")`
  - [x] Implement `GetChildren(conceptId)` — `$ORDER` over `^SNOMED.Children(conceptId, "")`
  - [x] Implement `GetParents(conceptId)` — `$ORDER` over `^SNOMED.Children` finding entries where concept is child
- [x] Task 2: Test in Docker container (AC: #1-#5)
  - [x] Load relationship test fixture and run `SNOMED.TransitiveClosure.Compute()`
  - [x] Verify `IsDescendantOf("46635009","73211009")` returns 1 (Type 1 DM is descendant of DM)
  - [x] Verify `IsDescendantOf("73211009","46635009")` returns 0 (wrong direction)
  - [x] Verify `GetDescendants("138875005")` returns JSON array containing "73211009" and "46635009"
  - [x] Verify `GetAncestors("46635009")` returns JSON array containing "73211009" and "138875005"
  - [x] Verify `GetChildren("73211009")` returns JSON array containing "46635009"
  - [x] Verify `GetParents("46635009")` returns JSON array containing "73211009"

## Dev Notes

### Architecture Pattern

This story creates a new **ObjectScript** utility class. ObjectScript (not Python) because:
- The research report explicitly recommends ObjectScript for "hierarchy traversal" and "runtime lookups"
- `$DATA` and `$ORDER` are native ObjectScript global operations — fastest possible
- These methods will be wrapped as MCP tools in Story 3.2 — ObjectScript is the natural fit
- Pattern matches `SNOMED.Search` (Story 2.1) which is also ObjectScript returning JSON

### Global Structure (from Story 2.2)

```
^SNOMED.TC(ancestorId, descendantId) = ""
  - $DATA(^SNOMED.TC(ancestor, descendant)) → O(1) subsumption check
  - $ORDER(^SNOMED.TC(conceptId, "")) iterates all descendants of conceptId

^SNOMED.Children(parentId, childId) = ""
  - $ORDER(^SNOMED.Children(parentId, "")) iterates direct children of parentId
```

### Implementation Code Patterns

**IsDescendantOf — O(1) subsumption check:**
```objectscript
ClassMethod IsDescendantOf(conceptId As %String, ancestorId As %String) As %Boolean
{
    Quit $DATA(^SNOMED.TC(ancestorId, conceptId))#2
}
```

**GetDescendants — iterate all descendants:**
```objectscript
ClassMethod GetDescendants(conceptId As %String) As %String
{
    Set results = []
    Set desc = ""
    For {
        Set desc = $ORDER(^SNOMED.TC(conceptId, desc))
        Quit:desc=""
        Do results.%Push(desc)
    }
    Return results.%ToJSON()
}
```

**GetAncestors — need reverse lookup:**
The `^SNOMED.TC` global is structured as `(ancestor, descendant)`. To find ancestors of a concept, we need to scan all first-subscript entries and check if our concept appears as a descendant. This is expensive for large datasets.

**Better approach for GetAncestors:** Iterate `$ORDER` on first subscript of `^SNOMED.TC`, checking `$DATA(^SNOMED.TC(candidate, conceptId))`. However, this is a full scan.

**Optimal approach:** Since `^SNOMED.TC` has subscript order `(ancestor, descendant)`, we cannot directly iterate "all ancestors of X" without a reverse index. Two options:
1. Scan all first-level subscripts (works but O(n) where n = total concepts with descendants)
2. Use a reverse query from the `^SNOMED.Children` global — BFS upward through parents

**Recommended: BFS upward from Children global** for GetAncestors (same pattern as TC computation but returns the list):
```objectscript
ClassMethod GetAncestors(conceptId As %String) As %String
{
    Set results = []
    // BFS upward through parent chain
    Set queue = $LISTBUILD(conceptId)
    Set visited(conceptId) = ""
    While $LISTLENGTH(queue) > 0 {
        Set node = $LIST(queue, 1)
        Set queue = $LIST(queue, 2, *)
        // Iterate parents of node (node is child in ^SNOMED.Children)
        Set parent = ""
        For {
            Set parent = $ORDER(^SNOMED.Children(parent))
            Quit:parent=""
            If $DATA(^SNOMED.Children(parent, node)) {
                If '$DATA(visited(parent)) {
                    Set visited(parent) = ""
                    Do results.%Push(parent)
                    Set queue = queue_$LISTBUILD(parent)
                }
            }
        }
    }
    Return results.%ToJSON()
}
```

**WAIT — Better approach:** Actually, we CAN use `^SNOMED.TC` for GetAncestors. We just need to iterate all first subscripts and check if our concept is a second subscript:
```objectscript
Set ancestor = ""
For {
    Set ancestor = $ORDER(^SNOMED.TC(ancestor))
    Quit:ancestor=""
    If $DATA(^SNOMED.TC(ancestor, conceptId)) Do results.%Push(ancestor)
}
```
This works but is O(number of ancestors in entire tree). For 831K concepts this could be slow.

**BEST approach for GetAncestors:** Use the `^SNOMED.Children` global to BFS upward (only visits actual ancestors, not all concepts):

```objectscript
ClassMethod GetAncestors(conceptId As %String) As %String
{
    // Use TC global - find all entries where conceptId appears as descendant
    // Since ^SNOMED.TC(ancestor, descendant), we need to check each ancestor
    // More efficient: BFS up through Children
    Set results = []
    Set visited(conceptId) = ""
    Set queue($INCREMENT(queue)) = conceptId
    Set ptr = 1
    While ptr '> $ORDER(queue(""),-1) {
        Set node = queue(ptr)
        Kill queue(ptr)
        Set ptr = ptr + 1
        // Find parents: iterate ^SNOMED.Children where node is a child
        Set parent = ""
        For {
            Set parent = $ORDER(^SNOMED.Children(parent))
            Quit:parent=""
            If $DATA(^SNOMED.Children(parent, node))#2 {
                If '$DATA(visited(parent)) {
                    Set visited(parent) = ""
                    Do results.%Push(parent)
                    Set $INCREMENT(queue) = parent
                    Set queue($ORDER(queue(""),-1)) = parent
                }
            }
        }
    }
    Return results.%ToJSON()
}
```

**Actually — SIMPLEST correct approach for GetAncestors:** The `^SNOMED.TC` global has ALL ancestor-descendant pairs. To find all ancestors of concept X, scan the first subscript and check `$DATA(^SNOMED.TC(candidate, X))`. While this iterates all first-level subscripts, it's still very fast due to global b-tree structure:

```objectscript
ClassMethod GetAncestors(conceptId As %String) As %String
{
    Set results = []
    Set ancestor = ""
    For {
        Set ancestor = $ORDER(^SNOMED.TC(ancestor))
        Quit:ancestor=""
        If $DATA(^SNOMED.TC(ancestor, conceptId))#2 {
            Do results.%Push(ancestor)
        }
    }
    Return results.%ToJSON()
}
```

**For GetParents — need reverse of Children:**
`^SNOMED.Children(parent, child)` — to find parents of a child, must scan first subscripts:
```objectscript
ClassMethod GetParents(conceptId As %String) As %String
{
    Set results = []
    Set parent = ""
    For {
        Set parent = $ORDER(^SNOMED.Children(parent))
        Quit:parent=""
        If $DATA(^SNOMED.Children(parent, conceptId))#2 {
            Do results.%Push(parent)
        }
    }
    Return results.%ToJSON()
}
```

### Critical Implementation Rules

- **Return type is `%String` containing JSON** — matches the pattern from `SNOMED.Search.Lexical()` for MCP tool compatibility (Story 3.2)
- **`IsDescendantOf` returns `%Boolean`** — the only method that returns a scalar (not JSON)
- **`$DATA(...)#2`** — the `#2` ensures we get 1 only if the node itself has data (not just child nodes)
- **`$ORDER(^Global(subscript))` pattern** — iterates next subscript at that level; returns "" when exhausted
- **ObjectScript string concatenation** uses `_` operator
- **`%DynamicArray` literal `[]`** creates a JSON array; `.%Push()` appends, `.%ToJSON()` serializes
- **No Python** — all methods are pure ObjectScript for performance
- **All methods handle missing concept gracefully** — if concept not in globals, returns empty array or 0

### What NOT To Do

- Do NOT use Python for these methods — ObjectScript `$ORDER`/`$DATA` is native and fastest
- Do NOT create a reverse index global — the scan approach is acceptable for these utility methods
- Do NOT return `%DynamicArray` objects — return JSON strings for MCP compatibility
- Do NOT forget `#2` on `$DATA` checks — without it, nodes with children but no data return non-zero
- Do NOT add error handling for missing globals — empty iteration naturally returns empty results
- Do NOT store results in a SQL table — these are runtime query methods against globals

### ObjectScript Queue Pattern for BFS

If BFS is needed in ObjectScript (not needed for current implementation but for reference):
```objectscript
// Simple queue using $LIST
Set queue = $LISTBUILD(startNode)
While $LISTLENGTH(queue) > 0 {
    Set current = $LIST(queue, 1)
    Set queue = $LIST(queue, 2, *)  // dequeue first element
    // ... process current ...
    Set queue = queue _ $LISTBUILD(newNode)  // enqueue
}
```

### Performance Notes

- `GetDescendants` and `GetChildren` are O(k) where k = number of results (direct subscript iteration)
- `GetAncestors` and `GetParents` are O(n) where n = number of first-level subscripts in global (must scan all ancestors/parents to find matching ones)
- For the full SNOMED CT (~831K concepts), `GetAncestors` scans up to ~400K distinct ancestor entries — this is acceptable for interactive use but could be slow for batch operations
- `IsDescendantOf` is always O(1) — single `$DATA` lookup

### Test Fixture Data (from Stories 1.3 / 2.2)

After loading relationships and computing TC:
- `^SNOMED.TC("73211009","46635009")` = "" (DM ancestor of Type 1 DM)
- `^SNOMED.TC("138875005","73211009")` = "" (root ancestor of DM)
- `^SNOMED.TC("138875005","46635009")` = "" (root ancestor of Type 1 DM — transitive)
- `^SNOMED.Children("73211009","46635009")` = "" (DM direct parent of Type 1 DM)
- `^SNOMED.Children("138875005","73211009")` = "" (root direct parent of DM)

Expected results:
- `IsDescendantOf("46635009","73211009")` = 1
- `IsDescendantOf("73211009","46635009")` = 0
- `GetDescendants("138875005")` = `["46635009","73211009"]` (order may vary)
- `GetAncestors("46635009")` = `["73211009","138875005"]` (order may vary)
- `GetChildren("73211009")` = `["46635009"]`
- `GetParents("46635009")` = `["73211009"]`

### Project Structure Notes

- New file: `src/SNOMED/Hierarchy.cls`
- Package: `SNOMED`
- Dependencies: `^SNOMED.TC` and `^SNOMED.Children` globals (from Story 2.2)

### Previous Story Intelligence

From Story 2.2:
- `iris.sql.prepare().execute()` returns iterable result set (`for row in rs:` with list rows)
- `gref.kill([])` to kill entire global (NOT `gref.kill()`)
- Docker container: `iris-ai-hub`
- Compilation: `$SYSTEM.OBJ.Load("/tmp/snomed/file.cls", "ck")`
- Testing: pipe commands to `iris session IRIS -U USER`
- ObjectScript `$DATA` returns 1 if data at exact node, 10 if subnodes exist, 11 if both — use `#2` to test bit 1

From Story 2.1 (SNOMED.Search pattern):
- ObjectScript class returning JSON string via `%DynamicArray.%ToJSON()`
- `Set results = []` creates empty array
- `Do results.%Push(value)` appends
- `Return results.%ToJSON()` returns serialized JSON
- This is the standard pattern for methods becoming MCP tools

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.3]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 253-271: ObjectScript hierarchy traversal patterns]
- [Source: src/SNOMED/TransitiveClosure.cls — global structure this story queries]
- [Source: src/SNOMED/Search.cls — ObjectScript JSON return pattern to follow]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A — clean implementation, no issues encountered.

### Completion Notes List

- Created `SNOMED.Hierarchy` class with 5 ObjectScript classmethods
- `IsDescendantOf` — O(1) via `$DATA(^SNOMED.TC(ancestorId, conceptId))#2`
- `GetDescendants` — `$ORDER` iteration over `^SNOMED.TC(conceptId, desc)`
- `GetAncestors` — scans all first-level subscripts of `^SNOMED.TC`, checks `$DATA` for conceptId as descendant
- `GetChildren` — `$ORDER` over `^SNOMED.Children(conceptId, child)`
- `GetParents` — scans first-level subscripts of `^SNOMED.Children`, checks `$DATA` for conceptId as child
- All methods return JSON strings (via `%DynamicArray.%ToJSON()`) except IsDescendantOf which returns `%Boolean`
- All acceptance criteria verified in Docker with test fixture data

### File List

- src/SNOMED/Hierarchy.cls (NEW)
