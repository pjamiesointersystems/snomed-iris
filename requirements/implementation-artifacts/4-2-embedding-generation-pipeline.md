# Story 4.2: Embedding Generation Pipeline

Status: review

## Story

As a terminology administrator,
I want to generate vector embeddings for all active SNOMED concept descriptions using Ollama,
so that the terminology is searchable by semantic meaning.

## Acceptance Criteria

1. `SNOMED.Embeddings.Generate(modelName, batchSize)` generates embeddings for all active Fully Specified Names
2. Processing is batched (default batch size 100) to manage memory
3. Progress is reported (count and percentage)
4. Embeddings are inserted into `SNOMED.ConceptEmbedding` via SQL prepared statements
5. The process can be resumed (skips concepts that already have embeddings)
6. If Ollama is unreachable or returns an error, a meaningful error is returned and partial progress is preserved

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Embeddings` class with `Generate` method (AC: #1, #2, #3, #4, #5)
  - [x] Create `src/SNOMED/Embeddings.cls` extending `%RegisteredObject`
  - [x] Implement `Generate(modelName, batchSize)` as Python class method
  - [x] Query active FSN descriptions not yet in ConceptEmbedding (resume support)
  - [x] Call Ollama `/api/embed` endpoint in batches
  - [x] Insert embeddings via prepared SQL statement with `TO_VECTOR(?, DOUBLE)`
  - [x] Report progress every batch (count processed, percentage, rate)
- [x] Task 2: Implement error handling and resilience (AC: #6)
  - [x] Handle Ollama connection errors with meaningful message
  - [x] Handle Ollama API errors (bad model name, etc.)
  - [x] Preserve partial progress on failure (already inserted embeddings remain)
  - [x] Return error status with details on failure
- [x] Task 3: Test in Docker container (AC: #1-#6)
  - [x] Compile class and verify no errors
  - [x] Test with Ollama running (if available) or verify logic with mock
  - [x] Verify resume behavior (running twice doesn't duplicate)
  - [x] Verify error handling when Ollama is unreachable

## Dev Notes

### Architecture Pattern

This story creates `SNOMED.Embeddings` — a utility class with a Python `Generate` method that orchestrates embedding generation. It follows the same pattern as `SNOMED.Loader` (Python class methods for bulk operations) and `SNOMED.TransitiveClosure` (long-running computation with progress reporting).

The method:
1. Queries all active FSN descriptions NOT already embedded (resume support)
2. Batches them into groups of `batchSize`
3. Calls Ollama's embedding API for each batch
4. Inserts results into `SNOMED.ConceptEmbedding`

### Ollama Embedding API

Ollama exposes an embedding endpoint at `http://localhost:11434/api/embed`:

```python
import requests

response = requests.post("http://localhost:11434/api/embed", json={
    "model": "all-minilm",       # or "nomic-embed-text"
    "input": ["text1", "text2", "text3"]  # batch of texts
})
data = response.json()
# data["embeddings"] = [[0.1, 0.2, ...], [0.3, 0.4, ...], ...]
```

Key facts:
- The `/api/embed` endpoint accepts a list of inputs (batch embedding)
- Response: `{"embeddings": [[float, ...], ...]}` — one vector per input
- Model `all-minilm` outputs 384 dimensions (matches our VECTOR column)
- Model `nomic-embed-text` also outputs 384 dimensions
- Default Ollama port: 11434
- If Ollama is not running, `requests.post()` raises `ConnectionError`

### Implementation Code Pattern

```python
ClassMethod Generate(modelName As %String = "all-minilm", batchSize As %Integer = 100, ollamaUrl As %String = "http://localhost:11434") As %Status [ Language = python ]
{
    import iris
    import requests

    # Find FSNs not yet embedded (resume support)
    find_sql = iris.sql.prepare(
        "SELECT d.ConceptId, d.Term "
        "FROM SNOMED.Description d "
        "JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId "
        "WHERE d.TypeId = '900000000000003001' "
        "AND d.Active = 1 AND c.Active = 1 "
        "AND d.ConceptId NOT IN (SELECT ConceptId FROM SNOMED.ConceptEmbedding)"
    )
    rs = find_sql.execute()

    # Collect all rows (can't iterate twice)
    pending = []
    for row in rs:
        pending.append((row[0], row[1]))

    total = len(pending)
    if total == 0:
        print("All concepts already have embeddings. Nothing to do.")
        return iris.cls("%SYSTEM.Status").OK()

    print(f"Generating embeddings for {total} concepts using model '{modelName}'...")

    # Prepared insert statement
    insert_sql = iris.sql.prepare(
        "INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding) "
        "VALUES (?, ?, TO_VECTOR(?, DOUBLE))"
    )

    embed_url = f"{ollamaUrl}/api/embed"
    processed = 0

    # Process in batches
    for i in range(0, total, batchSize):
        batch = pending[i:i + batchSize]
        texts = [term for _, term in batch]

        try:
            resp = requests.post(embed_url, json={
                "model": modelName,
                "input": texts
            }, timeout=120)
            resp.raise_for_status()
        except requests.ConnectionError:
            msg = f"Cannot connect to Ollama at {ollamaUrl}. Is Ollama running?"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)
        except requests.HTTPError as e:
            msg = f"Ollama API error: {e}"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)

        data = resp.json()
        embeddings = data.get("embeddings", [])

        for j, (concept_id, term) in enumerate(batch):
            if j < len(embeddings):
                vec_str = ",".join(str(f) for f in embeddings[j])
                insert_sql.execute(concept_id, term, vec_str)

        processed += len(batch)
        pct = (processed / total) * 100
        print(f"  Processed {processed}/{total} ({pct:.1f}%)")

    print(f"Embedding generation complete: {processed} concepts embedded")
    return iris.cls("%SYSTEM.Status").OK()
}
```

### Resume Support Design

The key to resume is the SQL `NOT IN` subquery:
```sql
WHERE d.ConceptId NOT IN (SELECT ConceptId FROM SNOMED.ConceptEmbedding)
```

This means:
- If the process fails halfway, already-inserted embeddings persist (no transactions to roll back)
- Re-running `Generate()` only processes concepts that don't yet have embeddings
- This is safe because ConceptId has a unique index — no duplicates possible

### Python Dependencies

The method uses `requests` for HTTP calls to Ollama. Check if `requests` is available in the IRIS container:
```
docker exec iris-ai-hub python3 -c "import requests; print(requests.__version__)"
```

If not available, alternatives:
1. Use `urllib.request` (stdlib) — more verbose but no dependencies
2. Install via `pip` in the container

**Preference: Use `urllib.request` as fallback** if `requests` is not available, to avoid adding dependencies.

### urllib.request Fallback Pattern

```python
import urllib.request
import json

data = json.dumps({"model": modelName, "input": texts}).encode('utf-8')
req = urllib.request.Request(embed_url, data=data, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
except urllib.error.URLError as e:
    # Connection refused or timeout
    msg = f"Cannot connect to Ollama: {e}"
    ...
```

### Critical Implementation Rules

- **Model default = "all-minilm"** — 384 dimensions, matches VECTOR column
- **Batch size default = 100** — balance between speed and memory
- **FSN TypeId = '900000000000003001'** — only embed Fully Specified Names
- **Only active concepts/descriptions** — filter on `Active = 1` for both
- **TO_VECTOR(?, DOUBLE)** — the DOUBLE qualifier is REQUIRED (confirmed in Story 4.1)
- **Vector as comma-separated string** — join floats with comma for `TO_VECTOR()`
- **Progress reporting every batch** — print count, total, percentage
- **Partial progress preserved** — no transaction wrapping; each INSERT commits immediately
- **File location**: `src/SNOMED/Embeddings.cls`
- **Class extends `%RegisteredObject`** — not `%Persistent`; it's a utility class

### What NOT To Do

- Do NOT use `sentence_transformers` or local model loading — use Ollama HTTP API
- Do NOT wrap the entire operation in a transaction — partial progress must persist
- Do NOT modify `SNOMED.ConceptEmbedding` class — it's complete from Story 4.1
- Do NOT implement semantic search — that's Story 4.3
- Do NOT hardcode Ollama URL — accept as parameter with default
- Do NOT embed Synonyms — only FSN (one embedding per concept)
- Do NOT assume `requests` is installed — check and fallback to `urllib`
- Do NOT add a `Clear()` method that would delete all embeddings — too dangerous for accidental calls

### Testing Strategy

Since Ollama may not be running in the Docker container:

1. **Compile test**: Verify class compiles without errors
2. **Resume logic test**: Insert a few fake embeddings, run Generate, verify it skips those
3. **Connection error test**: Call with bad URL, verify error message and status
4. **If Ollama available**: Test with 2-3 real concepts and verify embeddings stored

For the resume test, pre-insert a test embedding:
```python
insert = iris.sql.prepare(
    "INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding) "
    "VALUES (?, ?, TO_VECTOR(?, DOUBLE))"
)
fake_vec = ",".join(["0.1"] * 384)
insert.execute("TEST_ID", "Test term", fake_vec)
# Then run Generate — it should skip TEST_ID
```

### Previous Story Intelligence

From Story 4.1:
- `SNOMED.ConceptEmbedding` has: ConceptId (unique indexed), Term, Embedding (VECTOR DOUBLE 384)
- Insert syntax: `INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding) VALUES (?, ?, TO_VECTOR(?, DOUBLE))`
- The DOUBLE qualifier in TO_VECTOR is required
- HNSW index: `As %SQL.Index.HNSW`
- Table is accessible as `SNOMED.ConceptEmbedding` (schema.table) in SQL

From Story 1.2 (Loader pattern):
- Python class methods with `[ Language = python ]`
- `iris.sql.prepare(sql).execute(params)` for parameterized SQL
- Progress reporting every N records with `print()`
- Return `iris.cls("%SYSTEM.Status").OK()` or `.Error(5001, msg)`
- File validation with `os.path.isfile()` before processing

From Story 2.2 (TransitiveClosure pattern):
- Long-running computation with progress percentage
- `iris.sql.prepare().execute()` returns iterable — `for row in rs:` with `row[0]`, `row[1]`
- Cannot iterate result set twice — must collect to list first if needed

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 4.2]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 352-370: Embedding Generation Strategy]
- [Source: src/SNOMED/Loader.cls — Python bulk operation pattern]
- [Source: src/SNOMED/ConceptEmbedding.cls — target table schema]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `requests` 2.33.1 is available in the IRIS 2026.2.0AI container (no fallback to urllib needed)
- `iris.sql.exec("DELETE ...")` throws SQLError when no rows match (SQLCODE 100) — use `try/except` or `iris.sql.prepare().execute()` with exception handling
- `iris.sql.prepare("DELETE ...").execute()` also throws on empty table — same SQLCODE 100 behavior
- Ollama `/api/embed` accepts `{"model": "...", "input": ["text1", "text2"]}` and returns `{"embeddings": [[...], [...]]}`
- `requests.post` to port >65535 throws `InvalidURL` (not `ConnectionError`) — must catch both
- Vector string format for TO_VECTOR: comma-separated floats as a single string parameter

### Completion Notes List

- Created `SNOMED.Embeddings` with `Generate(modelName, batchSize, ollamaUrl)` Python class method
- Resume support via `NOT IN (SELECT ConceptId FROM SNOMED.ConceptEmbedding)` subquery
- Batched processing with progress reporting (count/total/percentage per batch)
- Comprehensive error handling: ConnectionError, InvalidURL, Timeout, HTTPError, RequestException, mismatched embedding count
- Partial progress preserved on failure (no transaction wrapping)
- Verified: resume logic (1 pre-embedded, 3 remaining = correct), nothing-to-do path, connection error returns error status

### File List

- src/SNOMED/Embeddings.cls (NEW)
