# Story 4.1: Embedding Storage and Vector Schema

Status: review

## Story

As a developer,
I want a persistent class with a VECTOR column to store concept description embeddings,
so that semantic similarity search can be performed via SQL.

## Acceptance Criteria

1. `SNOMED.ConceptEmbedding` class extends `%Persistent` with properties: ConceptId (string, indexed), Term (string), and Embedding (VECTOR(DOUBLE, 384))
2. An ANN index (HNSW) is defined on the Embedding column for efficient similarity search
3. The class compiles successfully in the IRIS container
4. An embedding vector can be inserted via SQL `INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding) VALUES (?, ?, TO_VECTOR(?))`
5. Inserted vectors are queryable via `VECTOR_COSINE()` similarity function

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.ConceptEmbedding` persistent class (AC: #1, #2, #3)
  - [x] Create `src/SNOMED/ConceptEmbedding.cls` extending `%Persistent`
  - [x] Add `ConceptId` property as `%String(MAXLEN = 20)` with unique index
  - [x] Add `Term` property as `%String(MAXLEN = 1024)` to store the description text that was embedded
  - [x] Add `Embedding` property as `%Library.Vector(DATATYPE = "DOUBLE", LEN = 384)`
  - [x] Add ANN index on Embedding column with HNSW type
  - [x] Compile class in Docker container and verify no errors
- [x] Task 2: Test vector insert and query (AC: #4, #5)
  - [x] Insert a test embedding via SQL with `TO_VECTOR(?, DOUBLE)`
  - [x] Query using `VECTOR_COSINE()` and verify result is returned with similarity score
  - [x] Verify ConceptId index works for lookup by concept

## Dev Notes

### Architecture Pattern

This story creates a simple `%Persistent` class for storing precomputed vector embeddings. It follows the same pattern as `SNOMED.Concept` and `SNOMED.Description` — a persistent storage class with appropriate indexes.

The class stores ONE embedding per row, where each row represents a concept description's FSN or preferred term. A concept may have multiple descriptions, but for Story 4.2 (the generation pipeline), only the FSN will be embedded initially.

### IRIS VECTOR Type

IRIS 2026.2.0AI provides a native `VECTOR` SQL data type with:
- **SIMD-accelerated** similarity functions
- **ANN indexing** (HNSW) for datasets >100K vectors
- **Hybrid search**: combine vector similarity with standard SQL WHERE clauses

The dimension (384) matches the output of `all-MiniLM-L6-v2` / `nomic-embed-text` models commonly used with Ollama.

### %Persistent Class with VECTOR Property

```objectscript
Class SNOMED.ConceptEmbedding Extends %Persistent
{

/// SNOMED CT Concept Identifier
Property ConceptId As %String(MAXLEN = 20) [ Required ];

/// The description term that was embedded
Property Term As %String(MAXLEN = 1024);

/// Vector embedding of the term (384 dimensions for MiniLM)
Property Embedding As %Vector(DATATYPE = "DOUBLE", LEN = 384);

/// Unique lookup by concept ID
Index ConceptIdIdx On ConceptId [ Unique ];

/// ANN index for fast approximate nearest neighbor search
Index EmbeddingIdx On (Embedding) As %Library.VectorIndex [ Type = BitwiseIndex ];

}
```

### IMPORTANT: VECTOR Property and Index Syntax

The exact syntax for VECTOR properties and ANN indexes in IRIS 2026.2.0AI persistent classes needs verification. Two possible patterns:

**Pattern A (SQL DDL style — from research docs):**
```sql
CREATE TABLE SNOMED.ConceptEmbedding (
    ConceptId VARCHAR(20) NOT NULL,
    Term VARCHAR(1024),
    Embedding VECTOR(DOUBLE, 384)
)
CREATE INDEX IX_Embedding ON SNOMED.ConceptEmbedding(Embedding)
  TYPE VECTOR WITH OPTIONS '{"type": "HNSW", "m": 16, "efConstruction": 200}'
```

**Pattern B (%Persistent class definition):**
```objectscript
Property Embedding As %Vector(DATATYPE = "DOUBLE", LEN = 384);
```

The research document shows SQL DDL syntax. The `%Persistent` class approach may differ. Key uncertainties:
1. Is the property type `%Vector` or something else (e.g., `%Library.Vector`)?
2. How is the ANN/HNSW index declared in a class definition vs DDL?
3. Does `TO_VECTOR()` accept a comma-separated string of doubles?

### EAP API Discovery Strategy

Since this is EAP (Early Access Program) and vector support is new:

1. **First try**: Define class with `%Vector(DATATYPE = "DOUBLE", LEN = 384)` property
2. **If that fails**: Try `%Library.Vector` or just `VECTOR` as the type
3. **For the index**: Try standard IRIS index syntax first, then DDL-based `CREATE INDEX` if class-based doesn't work
4. **Inspect container**: Check what vector-related classes exist:
   ```
   SELECT Name FROM %Dictionary.ClassDefinition WHERE Name LIKE '%Vector%'
   ```

### SQL Operations (from research)

```sql
-- Insert embedding
INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding)
VALUES (?, ?, TO_VECTOR(?))

-- The TO_VECTOR() argument is a comma-separated string of doubles:
-- "0.123,0.456,0.789,..."

-- Semantic search using cosine similarity
SELECT TOP 10 ConceptId, Term,
       VECTOR_COSINE(Embedding, TO_VECTOR(?)) AS Score
FROM SNOMED.ConceptEmbedding
ORDER BY Score DESC
```

### Testing Strategy

For Task 2, generate a fake 384-dimension vector (all zeros or simple pattern) to verify storage/retrieval works:

```python
import iris

# Create a fake 384-dim vector as comma-separated string
fake_vec = ",".join(["0.1"] * 384)

stmt = iris.sql.prepare(
    "INSERT INTO SNOMED_ConceptEmbedding (ConceptId, Term, Embedding) "
    "VALUES (?, ?, TO_VECTOR(?))"
)
stmt.execute("12345678", "Test concept (finding)", fake_vec)

# Query it back
query = iris.sql.prepare(
    "SELECT ConceptId, Term, VECTOR_COSINE(Embedding, TO_VECTOR(?)) AS Score "
    "FROM SNOMED_ConceptEmbedding "
    "ORDER BY Score DESC"
)
rs = query.execute(fake_vec)
for row in rs:
    print(f"ConceptId={row[0]}, Term={row[1]}, Score={row[2]}")
```

Note: SQL table names use underscore (`SNOMED_ConceptEmbedding`) not dot when used from SQL in the container. Check which format works.

### Critical Implementation Rules

- **Dimension = 384** — matches MiniLM/nomic-embed-text output size
- **DOUBLE datatype** — not FLOAT; research docs specify DOUBLE
- **ConceptId is unique indexed** — one embedding per concept (FSN only)
- **Term stores the text that was embedded** — so search results can show the original text
- **ANN index is HNSW** — required for performance at 831K+ vectors
- **HNSW parameters**: m=16, efConstruction=200 (standard defaults for quality/speed balance)
- **File location**: `src/SNOMED/ConceptEmbedding.cls`
- **Test with fake vectors** — don't need real embeddings to verify schema works

### What NOT To Do

- Do NOT implement embedding generation — that's Story 4.2
- Do NOT implement the semantic search method — that's Story 4.3
- Do NOT add Python dependencies (ollama, sentence-transformers) — not needed for schema
- Do NOT modify existing classes (Concept, Description, etc.)
- Do NOT add the ConceptEmbedding to the ToolSet — it's storage only, not a tool
- Do NOT try to create a foreign key to SNOMED.Concept — keep it simple; just indexed ConceptId string

### Previous Story Intelligence

From Story 3.3 (most recent):
- Docker container: `iris-ai-hub`
- Compile: `docker cp file iris-ai-hub:/tmp/snomed/ && echo 'Do $SYSTEM.OBJ.Load("/tmp/snomed/File.cls", "ck")' | docker exec -i iris-ai-hub iris session IRIS -U USER`
- `iris.sql.prepare(sql).execute(params)` for Python SQL — iterate with `for row in rs:`
- The 2026.2.0AI container has vector support (AI Hub EAP feature)

From Story 1.1 (Schema pattern):
- `SNOMED.Concept` uses `%Persistent` with `%String(MAXLEN = 20)`, `[ Required ]`, `[ Unique ]` index
- Properties use `///` doc comments
- Bitmap indexes for boolean fields, standard indexes for lookups

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 4.1]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 285-370: Vector/Embedding Support]
- [Source: src/SNOMED/Concept.cls — %Persistent class pattern reference]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `%Library.Vector` confirmed as correct type class (extends `%DataType`, params: DATATYPE, LEN, STORAGEDEFAULT)
- Vector index class is `%SQL.Index.HNSW` (NOT `%SQL.VectorIndex.HNSWIndexer` which also exists but is different)
- UDL syntax for functional index: `Index Name On (Property) As ClassName;` (same pattern as iFind)
- `Type = classname` syntax causes parse error (#5559) when classname contains `%`; must use `As` keyword
- `TO_VECTOR(?, DOUBLE)` syntax required — the DOUBLE type qualifier is needed in the function call
- `VECTOR_COSINE()` returns 1.0 for identical vectors, 0 for orthogonal, works correctly for similarity ranking

### Completion Notes List

- Created `SNOMED.ConceptEmbedding` extending `%Persistent` with ConceptId, Term, and Embedding (VECTOR DOUBLE 384) properties
- ConceptId has unique index for fast lookup
- HNSW ANN index defined using `As %SQL.Index.HNSW` syntax
- Verified INSERT with `TO_VECTOR(?, DOUBLE)` works
- Verified `VECTOR_COSINE()` returns correct similarity scores (1.0 same, 0 orthogonal)
- Verified ConceptId index lookup works
- All 5 acceptance criteria satisfied

### File List

- src/SNOMED/ConceptEmbedding.cls (NEW)
