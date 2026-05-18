Class SNOMED.Search Extends %RegisteredObject
{

/// Search SNOMED descriptions by keyword/phrase using full-text index.
/// Returns JSON array of matching active descriptions with ConceptId, Term, TypeId.
/// term: search keyword or phrase
/// maxResults: maximum results to return (default 25)
ClassMethod Lexical(term As %String, maxResults As %Integer = 25) As %String
{
    Set results = []
    Set sql = "SELECT TOP ? d.ConceptId, d.Term, d.TypeId "
             _"FROM SNOMED.Description d "
             _"JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId "
             _"WHERE d.%ID %FIND search_index(TermIdx, ?, 0, '*') "
             _"AND d.Active = 1 AND c.Active = 1 "
             _"ORDER BY CASE WHEN d.Term = ? THEN 0 ELSE 1 END, d.Term"
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $$$ISERR(sc) {
        Set errObj = {}
        Set errObj.error = $System.Status.GetErrorText(sc)
        Return errObj.%ToJSON()
    }
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

/// Search SNOMED concepts by semantic meaning using vector similarity.
/// Embeds the query via Ollama, then finds closest concept embeddings using VECTOR_COSINE.
/// query: natural language description of the clinical concept to find
/// maxResults: maximum number of results (default 10)
/// minScore: minimum cosine similarity threshold (default 0.5)
/// ollamaUrl: Ollama server URL (default "http://localhost:11434")
/// modelName: embedding model name (default "all-minilm", must match generation model)
ClassMethod Semantic(query As %String, maxResults As %Integer = 10, minScore As %Numeric = 0.5, ollamaUrl As %String = "http://localhost:11434", modelName As %String = "all-minilm") As %String [ Language = python ]
{
    import iris
    import json
    import os
    import requests

    # Allow override via environment variable for container networking
    ollamaUrl = os.environ.get("OLLAMA_URL", ollamaUrl)

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
        "SELECT TOP ? ConceptId, Term, "
        "VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE)) AS Score "
        "FROM SNOMED.ConceptEmbedding "
        "ORDER BY Score DESC"
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

}
