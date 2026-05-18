# Story 4.3: Semantic Search Method and MCP Tool

Status: review

## Story

As a Claude Desktop/Code user,
I want to search for SNOMED concepts by semantic meaning through an MCP tool,
so that I can find relevant concepts even when I don't know the exact clinical terminology.

## Acceptance Criteria

1. `SNOMED.Search.Semantic(query, maxResults)` embeds the query via Ollama, then uses `VECTOR_COSINE()` to return the top N matching concepts
2. Results include ConceptId, Term, and similarity score
3. Only results above a minimum threshold (default 0.5) are returned
4. `SNOMED.Tools.Semantic` extends `%AI.Tool` with a `SemanticSearch(query, maxResults)` method
5. The ToolSet XData is updated to include the Semantic tool class
6. The tool is discoverable and callable via the MCP service

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Search.Semantic` method (AC: #1, #2, #3)
  - [x] Add `Semantic` classmethod to `src/SNOMED/Search.cls` (Python, calls Ollama then VECTOR_COSINE)
  - [x] Embed the query string using Ollama `/api/embed` endpoint
  - [x] Execute SQL with `VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE))` ordering by score DESC
  - [x] Filter results by minimum threshold (default 0.5)
  - [x] Return JSON array with ConceptId, Term, Score for each match
  - [x] Handle Ollama connection errors gracefully (return error JSON)
- [x] Task 2: Create `SNOMED.Tools.Semantic` MCP tool class (AC: #4)
  - [x] Create `src/SNOMED/Tools/Semantic.cls` extending `%AI.Tool`
  - [x] Implement `SemanticSearch(query, maxResults)` classmethod delegating to `SNOMED.Search.Semantic()`
  - [x] Add `///` doc comments for LLM-visible tool description
- [x] Task 3: Update ToolSet to include Semantic tool (AC: #5, #6)
  - [x] Add `<Include Class="SNOMED.Tools.Semantic"/>` to `src/SNOMED/ToolSet.cls` XData
  - [x] Recompile ToolSet and verify `%Discover()` now shows SemanticSearch tool
- [x] Task 4: Test compilation and integration (AC: #1-#6)
  - [x] Compile all new/modified classes
  - [x] Verify SemanticSearch appears in ToolSet discovery (9 tools total)
  - [x] Test error handling when Ollama is unreachable
  - [x] Test with fake embeddings — vector similarity scoring and threshold filtering work correctly

## Dev Notes

### Architecture Pattern

This story has three components:
1. **Search method** (`SNOMED.Search.Semantic`) — Python method that calls Ollama then queries VECTOR_COSINE
2. **MCP Tool wrapper** (`SNOMED.Tools.Semantic`) — ObjectScript %AI.Tool that delegates to the search method
3. **ToolSet update** (`SNOMED.ToolSet`) — add `<Include>` for the new tool class

This follows the same delegation pattern as Story 3.1/3.2: Tool class (ObjectScript) → Core method (Python/ObjectScript).

### SNOMED.Search Class (EXISTING — being modified)

The `SNOMED.Search` class already exists with a `Lexical` method. This story ADDS a `Semantic` classmethod to the same class.

Current state of `src/SNOMED/Search.cls`:
```objectscript
Class SNOMED.Search Extends %RegisteredObject
{
ClassMethod Lexical(searchTerm As %String, maxResults As %Integer = 20) As %String [ Language = python ]
{
    // ... existing lexical search implementation
}
}
```

### Semantic Search Implementation

```python
ClassMethod Semantic(query As %String, maxResults As %Integer = 10, minScore As %Numeric = 0.5, ollamaUrl As %String = "http://localhost:11434", modelName As %String = "all-minilm") As %String [ Language = python ]
{
    import iris
    import json
    import requests

    # Step 1: Embed the query using Ollama
    try:
        resp = requests.post(f"{ollamaUrl}/api/embed", json={
            "model": modelName,
            "input": [query]
        }, timeout=30)
        resp.raise_for_status()
    except (requests.ConnectionError, requests.exceptions.InvalidURL,
            requests.exceptions.Timeout, requests.RequestException) as e:
        return json.dumps({"error": f"Cannot connect to Ollama: {e}"})
    except requests.HTTPError as e:
        return json.dumps({"error": f"Ollama API error: {e}"})

    data = resp.json()
    embeddings = data.get("embeddings", [])
    if not embeddings:
        return json.dumps({"error": "Ollama returned no embeddings"})

    query_vec = ",".join(str(f) for f in embeddings[0])

    # Step 2: Query VECTOR_COSINE for similar concepts
    sql = iris.sql.prepare(
        f"SELECT TOP ? ConceptId, Term, "
        f"VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE)) AS Score "
        f"FROM SNOMED.ConceptEmbedding "
        f"ORDER BY Score DESC"
    )
    rs = sql.execute(maxResults, query_vec)

    results = []
    for row in rs:
        score = row[2]
        if score is not None and float(score) >= minScore:
            results.append({
                "ConceptId": row[0],
                "Term": row[1],
                "Score": round(float(score), 4)
            })

    return json.dumps(results)
}
```

### MCP Tool Wrapper Pattern

```objectscript
Class SNOMED.Tools.Semantic Extends %AI.Tool
{

/// Search for SNOMED CT concepts by semantic meaning using vector similarity.
/// Returns concepts whose embeddings are most similar to the query text.
/// query: Natural language description of the clinical concept to find
/// maxResults: Maximum number of results to return (default 10)
ClassMethod SemanticSearch(query As %String, maxResults As %Integer = 10) As %String
{
    Return ##class(SNOMED.Search).Semantic(query, maxResults)
}

}
```

### ToolSet Update

Add to `src/SNOMED/ToolSet.cls`:
```xml
<Include Class="SNOMED.Tools.Semantic"/>
```

After the existing `<Include Class="SNOMED.Tools.Hierarchy"/>` line.

### SQL Query Details

The VECTOR_COSINE query:
```sql
SELECT TOP ? ConceptId, Term,
       VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE)) AS Score
FROM SNOMED.ConceptEmbedding
ORDER BY Score DESC
```

Key facts (from Story 4.1):
- `TO_VECTOR(?, DOUBLE)` — DOUBLE qualifier is REQUIRED
- `VECTOR_COSINE()` returns 0-1 (1 = identical direction)
- The HNSW ANN index (`%SQL.Index.HNSW`) automatically accelerates nearest-neighbor queries
- Table name in SQL: `SNOMED.ConceptEmbedding`

### Error Handling

The Semantic method returns JSON in ALL cases:
- **Success**: `[{"ConceptId": "...", "Term": "...", "Score": 0.85}, ...]`
- **Ollama error**: `{"error": "Cannot connect to Ollama: ..."}`
- **No results above threshold**: `[]` (empty array)

This is consistent with other Tool methods that always return JSON strings.

### Critical Implementation Rules

- **Add `Semantic` to EXISTING `SNOMED.Search` class** — do NOT create a new class for the search method
- **`SNOMED.Tools.Semantic` is a NEW file** at `src/SNOMED/Tools/Semantic.cls`
- **Tool delegates to Search** — `SNOMED.Tools.Semantic.SemanticSearch()` calls `##class(SNOMED.Search).Semantic()`
- **Default minScore = 0.5** — filter out low-quality matches
- **Default maxResults = 10** — keep result sets manageable for LLM
- **Default model = "all-minilm"** — must match the model used for embedding generation (Story 4.2)
- **`requests` is available** in the container (confirmed in Story 4.2, version 2.33.1)
- **Return JSON string from ALL tool methods** — never raw values
- **`///` doc comments become tool descriptions** — write them clearly for the LLM
- **ToolSet uses `<Include Class="SNOMED.Tools.Semantic"/>` XML** — add after Hierarchy

### What NOT To Do

- Do NOT create a separate `SNOMED.Search.Semantic` class — add method to existing `SNOMED.Search`
- Do NOT use `sentence_transformers` — use Ollama HTTP API (same as Story 4.2)
- Do NOT return results below minScore threshold — filter them out
- Do NOT hardcode the Ollama URL in the Tool class — pass through parameters
- Do NOT modify the MCP.Service class — it auto-discovers from ToolSet
- Do NOT change how existing tools work — only ADD new functionality
- Do NOT forget to update ToolSet XData — or the tool won't be discoverable

### Testing Strategy

1. **Compile all classes** — Search.cls (modified), Tools/Semantic.cls (new), ToolSet.cls (modified)
2. **ToolSet discovery** — call `%Discover()` and verify SemanticSearch appears
3. **Error path** — call `SNOMED.Search.Semantic("test", 10, 0.5, "http://localhost:59999")` with bad URL
4. **If Ollama available** — insert fake embeddings, embed a query, verify results with scores

### Previous Story Intelligence

From Story 4.2:
- `requests` 2.33.1 available in container
- Ollama `/api/embed` accepts `{"model": "...", "input": ["text"]}`, returns `{"embeddings": [[...]]}`
- `iris.sql.prepare().execute()` throws SQLError on DELETE with no rows (SQLCODE 100)
- `TO_VECTOR(?, DOUBLE)` syntax confirmed working

From Story 4.1:
- `SNOMED.ConceptEmbedding` table: ConceptId, Term, Embedding (VECTOR DOUBLE 384)
- `VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE))` returns similarity score (0-1)
- HNSW index: `As %SQL.Index.HNSW` — accelerates ORDER BY Score DESC queries

From Story 3.1:
- `%AI.Tool` pattern: ClassMethod with `///` doc comments, returns `%String` (JSON)
- Tool delegation: `Return ##class(ClassName).Method(args)`
- ToolSet `%Discover()` returns JSON with all tool schemas

From Story 3.3:
- ToolSet XData: `<Include Class="SNOMED.Tools.ClassName"/>` XML element
- After ToolSet recompile, `%Discover()` auto-picks up new tools

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 4.3]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 296-325: SQL Vector Syntax]
- [Source: src/SNOMED/Search.cls — existing class to modify]
- [Source: src/SNOMED/Tools/Lookup.cls — %AI.Tool pattern reference]
- [Source: src/SNOMED/ToolSet.cls — XData to update]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `%Discover()` is an instance method on ToolSet (not class method) — returns `%DynamicObject`
- VECTOR_COSINE correctly filters: identical=1.0, similar=0.86, dissimilar=0.47 (below 0.5 threshold)
- Tool wrapper delegation via `##class(SNOMED.Search).Semantic(query, maxResults)` works correctly
- Error handling returns JSON `{"error": "..."}` when Ollama unreachable — consistent with tool pattern

### Completion Notes List

- Added `Semantic()` Python classmethod to existing `SNOMED.Search` class
- Created `SNOMED.Tools.Semantic` extending `%AI.Tool` with `SemanticSearch(query, maxResults)` method
- Updated `SNOMED.ToolSet` XData to include `SNOMED.Tools.Semantic`
- ToolSet now discovers 9 tools (was 8): GetConcept, LexicalSearch, SearchByPattern, GetAncestors, GetChildren, GetDescendants, GetParents, IsA, SemanticSearch
- Verified: error JSON on Ollama connection failure, vector similarity scoring with threshold filtering, tool delegation chain

### File List

- src/SNOMED/Search.cls (MODIFIED — added Semantic method)
- src/SNOMED/Tools/Semantic.cls (NEW)
- src/SNOMED/ToolSet.cls (MODIFIED — added Include for Semantic)
