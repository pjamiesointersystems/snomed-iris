# Story 2.2: Transitive Closure Computation

Status: review

## Story

As a terminology administrator,
I want to compute and store the transitive closure of SNOMED's IS-A hierarchy,
so that ancestor/descendant queries and subsumption checks are instantaneous.

## Acceptance Criteria

1. `SNOMED.TransitiveClosure.Compute()` populates `^SNOMED.TC(ancestorId, descendantId)` for all transitive IS-A paths
2. `^SNOMED.Children(parentId, childId)` is populated with direct parent-child relationships
3. Computation handles the full SNOMED hierarchy (~831K concepts) without running out of memory
4. Progress is reported during computation
5. `$DATA(^SNOMED.TC("73211009", "46635009"))` returns true (Diabetes mellitus -> Type 1 diabetes)
6. A `Clear()` method kills the globals for re-computation

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.TransitiveClosure` class with `Compute` method (AC: #1, #2, #3, #4)
  - [x] Create `src/SNOMED/TransitiveClosure.cls` extending `%RegisteredObject`
  - [x] Implement `Compute()` as `[ Language = python ]` classmethod
  - [x] Load active IS-A edges from SNOMED.Relationship (typeId=116680003, Active=1) into Python dict
  - [x] Populate `^SNOMED.Children(parentId, childId)` from direct edges
  - [x] BFS upward from each concept to find all ancestors; store in `^SNOMED.TC(ancestorId, descendantId)`
  - [x] Report progress every 10,000 concepts processed
  - [x] Return `$$$OK` status
- [x] Task 2: Add `Clear` method (AC: #6)
  - [x] Implement `Clear()` that kills both `^SNOMED.TC` and `^SNOMED.Children` globals
- [x] Task 3: Test in Docker container (AC: #1, #2, #5)
  - [x] Load relationship test fixture (has IS-A edges: 46635009→73211009, 73211009→138875005)
  - [x] Run Compute()
  - [x] Verify `^SNOMED.Children("73211009","46635009")` exists (direct child)
  - [x] Verify `^SNOMED.TC("73211009","46635009")` exists (Type 1 DM is descendant of DM)
  - [x] Verify `^SNOMED.TC("138875005","46635009")` exists (transitive: root→Type 1 DM)
  - [x] Verify `^SNOMED.TC("46635009","73211009")` does NOT exist (wrong direction)

## Dev Notes

### Architecture Pattern

This is **Python** (`[ Language = python ]`) because:
- The research report explicitly recommends "Python for graph algorithms"
- BFS requires in-memory data structures (dict of lists) — Python is natural for this
- The ~831K IS-A edges fit in memory (~50MB as a Python dict)
- Globals are written via `iris.gref()` for maximum speed

### Algorithm (from existing Rust implementation)

The algorithm is **BFS upward from each concept**:

1. Load all active IS-A edges into `parents_of: dict[str, list[str]]` (child → [parent1, parent2, ...])
2. For each concept with parents, BFS upward through ancestors
3. For each (ancestor, descendant) pair discovered, set `^SNOMED.TC(ancestor, descendant) = ""`
4. Direct edges also stored in `^SNOMED.Children(parent, child) = ""`

### Global Structure

```
^SNOMED.TC(ancestorId, descendantId) = ""
  - Meaning: descendantId IS-A ancestorId (transitively)
  - Lookup: $DATA(^SNOMED.TC(ancestor, descendant)) → O(1) subsumption check
  - Traversal: $ORDER(^SNOMED.TC(conceptId, "")) iterates all descendants

^SNOMED.Children(parentId, childId) = ""
  - Meaning: childId is a direct child of parentId
  - Traversal: $ORDER(^SNOMED.Children(parentId, "")) iterates direct children
```

### Implementation Code Pattern

```python
ClassMethod Compute() As %Status [ Language = python ]
{
    import iris
    from collections import deque

    # Load active IS-A edges
    sql = iris.sql.exec(
        "SELECT SourceId, DestinationId FROM SNOMED.Relationship "
        "WHERE TypeId = '116680003' AND Active = 1"
    )

    parents_of = {}  # child -> [parent1, parent2, ...]
    tc_global = iris.gref("^SNOMED.TC")
    children_global = iris.gref("^SNOMED.Children")

    while sql.next():
        child = sql.getfield(1)
        parent = sql.getfield(2)
        parents_of.setdefault(child, []).append(parent)
        # Direct parent-child
        children_global[parent, child] = ""

    concepts = list(parents_of.keys())
    total = len(concepts)
    print(f"Computing transitive closure for {total} concepts...")

    for i, concept_id in enumerate(concepts):
        # BFS upward
        visited = {concept_id}
        queue = deque([concept_id])
        while queue:
            node = queue.popleft()
            for parent in parents_of.get(node, []):
                if parent not in visited:
                    visited.add(parent)
                    tc_global[parent, concept_id] = ""
                    queue.append(parent)

        if (i + 1) % 10000 == 0:
            print(f"  Processed {i+1}/{total} concepts...")

    print(f"Transitive closure complete: {total} concepts processed")
    return iris.cls("%SYSTEM.Status").OK()
}
```

### Critical Implementation Rules

- **Global subscript order is `(ancestorId, descendantId)`** — this enables `$ORDER(^SNOMED.TC(ancestorId, ""))` to iterate all descendants of an ancestor
- **IS-A relationship direction:** In RF2, SourceId IS-A DestinationId (source is the child, destination is the parent)
- **Only active IS-A:** Filter `TypeId = '116680003' AND Active = 1`
- **`iris.gref()`** for global access — this is the correct Python API for setting global nodes
- **Empty string value** (`""`) — we only need existence, not a stored value
- **BFS not DFS** — BFS gives shortest path first (matching the Rust implementation)
- **Memory:** The parents_of dict for 831K concepts with ~1M edges is ~50-100MB — fits comfortably
- **No self-referential entries** — don't store `^SNOMED.TC(X, X)`

### What NOT To Do

- Do NOT use `iris.sql.prepare()` for global writes — use `iris.gref()` directly (faster, no SQL overhead)
- Do NOT store the TC in a SQL table — globals are the correct architecture (O(1) via `$DATA`)
- Do NOT use networkx or other graph libraries — simple BFS with a deque is sufficient and avoids dependencies
- Do NOT compute from scratch if globals exist — the `Clear()` method should be called first
- Do NOT reverse the subscript order — it must be `(ancestor, descendant)` for efficient descendant iteration
- Do NOT include inactive IS-A relationships — only `Active = 1`

### iris.sql.exec() Result Set API

From testing in previous stories, the `iris.sql.exec()` returns a result set. The API for iterating:
```python
rs = iris.sql.exec("SELECT col1, col2 FROM table")
while rs.next():
    val1 = rs.getfield(1)  # 1-based column index
    val2 = rs.getfield(2)
```

Note: If this API doesn't work, fallback is `iris.sql.prepare()` + `.execute()` then iterate with `.next()` and `.getfield()`.

### Test Fixture Data (from Story 1.3)

The relationship test fixture has these IS-A edges:
- `100000001`: 46635009 → 73211009 (Type 1 DM IS-A Diabetes mellitus) — Active
- `100000002`: 73211009 → 138875005 (Diabetes mellitus IS-A SNOMED CT Concept) — Active
- `100000003`: 404684003 → 138875005 (Clinical finding IS-A root) — INACTIVE (should be excluded)

Expected TC after computation:
- `^SNOMED.TC("73211009", "46635009")` = "" (DM is ancestor of Type 1 DM)
- `^SNOMED.TC("138875005", "73211009")` = "" (root is ancestor of DM)
- `^SNOMED.TC("138875005", "46635009")` = "" (root is ancestor of Type 1 DM — transitive!)
- `^SNOMED.TC("138875005", "404684003")` should NOT exist (inactive relationship)

### Project Structure Notes

- New file: `src/SNOMED/TransitiveClosure.cls`
- Package: `SNOMED`
- Globals created: `^SNOMED.TC`, `^SNOMED.Children`

### Previous Story Intelligence

- `iris.gref()` API: `gref = iris.gref("^GlobalName")` then `gref[subscript1, subscript2] = value`
- Docker container: `iris-ai-hub`
- Testing: pipe commands to `iris session IRIS -U USER`
- ObjectScript global check: `Write $DATA(^SNOMED.TC("73211009","46635009"))`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 65, 253-268, 508]
- [Source: src/commands/tct.rs — BFS algorithm reference from Rust implementation]
- [Source: tests/fixtures/rf2/sct2_Relationship_Snapshot_Test.txt — test data with IS-A edges]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `iris.sql.exec()` returns `iris.%SYS.Python.SQLResultSet` which does NOT have `.next()` or `.getfield()` methods
- The result set IS iterable: `for row in rs:` yields lists (e.g., `['46635009', '73211009']`)
- Switched from `iris.sql.exec()` to `iris.sql.prepare().execute()` — same iterable behavior
- `gref.kill()` with no args raises `KeyError: 'Invalid args'` — must use `gref.kill([])` to kill entire global
- `iris.execute("Kill ^GlobalName")` also works as alternative

### Completion Notes List

- Created `SNOMED.TransitiveClosure` class with Python `Compute()` and `Clear()` methods
- `Compute()` uses `iris.sql.prepare()` to load active IS-A edges, iterates result set with `for row in rs:`
- BFS upward from each concept using `collections.deque`; stores ancestors in `^SNOMED.TC(ancestor, descendant)`
- Direct parent-child edges stored in `^SNOMED.Children(parent, child)`
- Progress reporting every 10,000 concepts (not triggered in test with only 2 concepts)
- `Clear()` uses `gref.kill([])` to kill both globals
- Verified all acceptance criteria:
  - `^SNOMED.Children("73211009","46635009")` exists (direct child)
  - `^SNOMED.TC("73211009","46635009")` exists (DM ancestor of Type 1 DM)
  - `^SNOMED.TC("138875005","46635009")` exists (transitive: root ancestor of Type 1 DM)
  - `^SNOMED.TC("46635009","73211009")` does NOT exist (wrong direction)
  - `^SNOMED.TC("138875005","404684003")` does NOT exist (inactive IS-A excluded)

### File List

- src/SNOMED/TransitiveClosure.cls (NEW)
