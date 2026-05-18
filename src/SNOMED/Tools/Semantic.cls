Class SNOMED.Tools.Semantic Extends %AI.Tool
{

/// Search for SNOMED CT concepts by semantic meaning using vector similarity.
/// Finds concepts whose embeddings are most similar to the natural language query.
/// Useful when you don't know the exact clinical terminology but can describe what you're looking for.
/// query: Natural language description of the clinical concept to find (e.g., "sugar disease", "broken arm bone")
/// maxResults: Maximum number of results to return (default 10)
ClassMethod SemanticSearch(query As %String, maxResults As %Integer = 10) As %String [ Language = python ]
{
    import os
    import iris
    import requests

    # Resolve Ollama URL: check env var, then probe common Docker hostnames
    ollama_url = os.environ.get("OLLAMA_URL", "")
    if not ollama_url:
        for candidate in ["http://ollama:11434", "http://host.docker.internal:11434", "http://localhost:11434"]:
            try:
                requests.get(f"{candidate}/api/tags", timeout=2)
                ollama_url = candidate
                os.environ["OLLAMA_URL"] = candidate
                break
            except Exception:
                continue
    if not ollama_url:
        ollama_url = "http://localhost:11434"

    return iris.cls("SNOMED.Search").Semantic(query, maxResults, 0.5, ollama_url)
}

}
