Class SNOMED.Embeddings Extends %RegisteredObject
{

/// Generate vector embeddings for all active SNOMED CT Fully Specified Names
/// using an Ollama embedding model. Embeddings are stored in SNOMED.ConceptEmbedding.
/// Supports resume — skips concepts that already have embeddings.
/// modelName: Ollama model name (default "all-minilm", 384 dimensions)
/// batchSize: Number of terms to embed per API call (default 100)
/// ollamaUrl: Ollama server URL (default "http://localhost:11434")
ClassMethod Generate(modelName As %String = "all-minilm", batchSize As %Integer = 100, ollamaUrl As %String = "http://localhost:11434") As %Status [ Language = python ]
{
    import iris
    import requests

    # Find active FSNs not yet embedded (resume support)
    find_sql = iris.sql.prepare(
        "SELECT d.ConceptId, d.Term "
        "FROM SNOMED.Description d "
        "JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId "
        "WHERE d.TypeId = '900000000000003001' "
        "AND d.Active = 1 AND c.Active = 1 "
        "AND d.ConceptId NOT IN (SELECT ConceptId FROM SNOMED.ConceptEmbedding)"
    )
    rs = find_sql.execute()

    # Collect all pending rows
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
        except (requests.ConnectionError, requests.exceptions.InvalidURL,
                requests.exceptions.Timeout) as e:
            msg = f"Cannot connect to Ollama at {ollamaUrl}: {e}"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)
        except requests.HTTPError as e:
            msg = f"Ollama API error: {e}"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)
        except requests.RequestException as e:
            msg = f"Request failed: {e}"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)

        data = resp.json()
        embeddings = data.get("embeddings", [])

        if len(embeddings) != len(batch):
            msg = f"Ollama returned {len(embeddings)} embeddings for {len(batch)} inputs"
            print(f"ERROR: {msg}")
            print(f"  Progress preserved: {processed}/{total} embeddings generated")
            return iris.cls("%SYSTEM.Status").Error(5001, msg)

        for j, (concept_id, term) in enumerate(batch):
            vec_str = ",".join(str(f) for f in embeddings[j])
            insert_sql.execute(concept_id, term, vec_str)

        processed += len(batch)
        pct = (processed / total) * 100
        print(f"  Processed {processed}/{total} ({pct:.1f}%)")

    print(f"Embedding generation complete: {processed} concepts embedded")
    return iris.cls("%SYSTEM.Status").OK()
}

}
