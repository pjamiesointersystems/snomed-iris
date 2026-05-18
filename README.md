# snomed-iris

A SNOMED CT Terminology Server built on InterSystems IRIS for Health with MCP (Model Context Protocol) integration. Enables AI assistants like Claude Desktop and Claude Code to look up concepts, search terminology, navigate the SNOMED hierarchy, and perform semantic similarity search — all through natural language.

---

## Features

- **RF2 Ingestion** — Stream-load SNOMED CT RF2 Snapshot files (Concepts, Descriptions, Relationships) into IRIS persistent storage
- **Full-Text Lexical Search** — Keyword search across 1.5M+ descriptions using IRIS text indexing
- **Hierarchy Navigation** — O(1) subsumption checking via precomputed transitive closure; instant ancestor/descendant/parent/child queries
- **Semantic Search** — Vector similarity search using 384-dimensional embeddings (Ollama + HNSW ANN index)
- **MCP Tool Exposure** — All operations available as MCP tools for Claude Desktop, Claude Code, or any MCP-compatible client

## Architecture

```
┌─────────────────────────────────────────────────┐
│  LLM Client (Claude Desktop / Claude Code)      │
└──────────────────────┬──────────────────────────┘
                       │ MCP (stdio or HTTP)
                       ▼
┌─────────────────────────────────────────────────┐
│  iris-mcp-server                                │
│  config/mcp-config.toml                         │
└──────────────────────┬──────────────────────────┘
                       │ SuperServer :1972
                       ▼
┌─────────────────────────────────────────────────┐
│  IRIS for Health                                │
│                                                 │
│  SNOMED.MCP.Service  ─▶  SNOMED.ToolSet        │
│    ├── Tools.Lookup    (GetConcept)             │
│    ├── Tools.Search    (LexicalSearch, Pattern) │
│    ├── Tools.Hierarchy (Parents, Children, ...)│
│    └── Tools.Semantic  (SemanticSearch)         │
│                                                 │
│  Data Layer:                                    │
│    SNOMED.Concept / Description / Relationship  │
│    ^SNOMED.TC (transitive closure)              │
│    ^SNOMED.Children (direct hierarchy)          │
│    SNOMED.ConceptEmbedding (VECTOR + HNSW)      │
└──────────────────────┬──────────────────────────┘
                       │ HTTP :11434
                       ▼
┌─────────────────────────────────────────────────┐
│  Ollama (embedding model: all-minilm)           │
└─────────────────────────────────────────────────┘
```

## MCP Tools

| Tool | Description |
|------|-------------|
| `GetConcept(sctid)` | Look up a concept by SNOMED CT identifier |
| `LexicalSearch(term, maxResults)` | Full-text keyword search across descriptions |
| `SearchByPattern(pattern, maxResults)` | SQL LIKE pattern search (use `%` wildcards) |
| `SemanticSearch(query, maxResults)` | Find concepts by meaning using vector similarity |
| `GetParents(conceptId)` | Get direct parent concepts |
| `GetChildren(conceptId)` | Get direct child concepts |
| `GetAncestors(conceptId)` | Get all ancestor concepts |
| `GetDescendants(conceptId, maxResults)` | Get all descendant concepts |
| `IsA(conceptId, ancestorId)` | Check subsumption (is concept a descendant of ancestor?) |

## Quick Start

The fastest way to get running is with the pre-built full image which includes the US Edition with all data, vectors, and indexes pre-loaded:

```bash
# Load the Docker image
docker load -i docker-images/snomed-iris-us-edition-2026.03.tar

# Start IRIS and Ollama
docker run -d --name ollama -p 11434:11434 ollama/ollama:latest
docker run -d --name snomed-iris -p 1972:1972 -p 52773:52773 \
  -e OLLAMA_URL=http://host.docker.internal:11434 \
  snomed-iris:us-edition-2026.03

# Pull the embedding model for semantic search
docker exec ollama ollama pull all-minilm
```

Then configure your LLM client to connect via `iris-mcp-server` — see the [Installation Guide](docs/INSTALLATION.md) for full details.

## Documentation

- **[Installation Guide](docs/INSTALLATION.md)** — Full and base image deployment, data loading, MCP client configuration
- **[IRIS + MCP Guide](docs/Using-SNOMED-CT-with-IRIS-for-Health-and-MCP.md)** — Background on the IRIS for Health and MCP approach
- **[Development Handoff](docs/snomed_iris_mcp_development_handoff.pdf)** — Technical context for developers

## Project Structure

```
snomed-iris/
├── src/SNOMED/              ObjectScript classes
│   ├── Concept.cls          Persistent data model
│   ├── Description.cls
│   ├── Relationship.cls
│   ├── ConceptEmbedding.cls Vector storage (HNSW indexed)
│   ├── Loader.cls           RF2 file ingestion
│   ├── TransitiveClosure.cls Hierarchy computation
│   ├── Hierarchy.cls        Navigation methods
│   ├── Search.cls           Lexical + semantic search
│   ├── Embeddings.cls       Ollama embedding pipeline
│   ├── Installer.cls        IPM setup
│   ├── ToolSet.cls          MCP tool registry
│   ├── MCP/Service.cls      MCP service endpoint
│   └── Tools/               MCP tool implementations
├── config/mcp-config.toml   iris-mcp-server config template
├── docker-compose.yml       IRIS + Ollama composition
├── Dockerfile               Container build
├── iris-init.script         Class loading script
├── module.xml               IPM package definition
├── requirements.txt         Python dependencies
├── requirements/            Planning & implementation specs
├── tests/fixtures/rf2/      Sample RF2 test data
└── docs/                    Documentation
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [iris-mcp-server](https://github.com/intersystems/iris-mcp-server/releases) (for LLM client connectivity)
- A SNOMED CT RF2 release (only if building from the base image)

## Getting SNOMED CT

SNOMED CT is licensed. Download the RF2 Snapshot for your region:

- **US:** [NLM UMLS](https://www.nlm.nih.gov/healthit/snomedct/us_edition.html)
- **UK:** [NHS Digital TRUD](https://isd.digital.nhs.uk/) — SNOMED CT Monolith Edition, RF2: Snapshot
- **International:** [MLDS](https://mlds.ihtsdotools.org/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](LICENSE).

## Trademarks

SNOMED CT® is a registered trademark of SNOMED International. This project is an independent implementation and is not affiliated with SNOMED International.
