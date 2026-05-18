# Story 5.3: Documentation and Getting Started Guide

Status: review

## Story

As a new user,
I want clear documentation on how to install, load data, and connect to Claude Desktop,
so that I can get the SNOMED MCP tools working quickly.

## Acceptance Criteria

1. A `README.md` exists in the project root explaining prerequisites, installation, RF2 data loading, and MCP configuration
2. A quick-start section with copy-paste commands is included
3. All available MCP tools are documented with example queries
4. The `config/mcp-config.toml` template works with `iris-mcp-server` out of the box for local development

## Tasks / Subtasks

- [x] Task 1: Create `README.md` (AC: #1, #2)
  - [x] Add project title, description, and badges
  - [x] Document prerequisites (IRIS 2026.2.0AI, Docker, Ollama optional)
  - [x] Write Quick Start section with Docker-based installation commands
  - [x] Document IPM-based installation alternative
  - [x] Document RF2 data loading steps (download, copy to container, call Loader)
  - [x] Document MCP configuration for Claude Desktop/Code
- [x] Task 2: Document MCP Tools (AC: #3)
  - [x] List all 9 MCP tools with descriptions and parameters
  - [x] Provide example natural language queries for each tool
  - [x] Document expected response formats
- [x] Task 3: Verify `config/mcp-config.toml` template (AC: #4)
  - [x] Confirm existing config works for local development defaults
  - [x] Add inline comments explaining each section
  - [x] Document Claude Desktop configuration snippet in README
- [x] Task 4: Validate documentation (AC: #1-#4)
  - [x] Verify all code examples are syntactically correct
  - [x] Verify file paths match actual project structure
  - [x] Verify tool list matches actual ToolSet (9 tools)

## Dev Notes

### Architecture Pattern

This is a documentation-only story. No source code changes. The README serves as the primary entry point for new users and should guide them from zero to a working SNOMED MCP setup.

### MCP Tools Reference (from ToolSet — 9 tools total)

| Tool | Class | Method | Parameters |
|------|-------|--------|------------|
| GetConcept | SNOMED.Tools.Lookup | GetConcept | conceptId |
| LexicalSearch | SNOMED.Tools.Search | LexicalSearch | searchTerm, maxResults |
| SearchByPattern | SNOMED.Tools.Search | SearchByPattern | pattern, maxResults |
| GetAncestors | SNOMED.Tools.Hierarchy | GetAncestors | conceptId |
| GetDescendants | SNOMED.Tools.Hierarchy | GetDescendants | conceptId, maxResults |
| GetChildren | SNOMED.Tools.Hierarchy | GetChildren | conceptId |
| GetParents | SNOMED.Tools.Hierarchy | GetParents | conceptId |
| IsA | SNOMED.Tools.Hierarchy | IsA | conceptId, ancestorId |
| SemanticSearch | SNOMED.Tools.Semantic | SemanticSearch | query, maxResults |

### RF2 Loading Commands

```objectscript
// In IRIS terminal (USER namespace):
Do ##class(SNOMED.Loader).LoadConcepts("/path/to/sct2_Concept_Full_*.txt")
Do ##class(SNOMED.Loader).LoadDescriptions("/path/to/sct2_Description_Full_*.txt")
Do ##class(SNOMED.Loader).LoadRelationships("/path/to/sct2_Relationship_Full_*.txt")
Do ##class(SNOMED.TransitiveClosure).Compute()
```

### Claude Desktop Configuration

```json
{
  "mcpServers": {
    "snomed": {
      "command": "/path/to/iris-mcp-server",
      "args": ["--config=/path/to/config.toml", "run"]
    }
  }
}
```

### Docker Quick Start Pattern

```bash
# Build and start
docker compose up -d

# Copy RF2 files into container
docker cp /path/to/SnomedCT_Release/ iris-snomed-iris-1:/tmp/snomed/

# Load data via IRIS session
docker exec -i iris-snomed-iris-1 iris session IRIS -U USER <<'EOF'
Do ##class(SNOMED.Loader).LoadConcepts("/tmp/snomed/Snapshot/Terminology/sct2_Concept_Snapshot_*.txt")
Do ##class(SNOMED.Loader).LoadDescriptions("/tmp/snomed/Snapshot/Terminology/sct2_Description_Snapshot_*.txt")
Do ##class(SNOMED.Loader).LoadRelationships("/tmp/snomed/Snapshot/Terminology/sct2_Relationship_Snapshot_*.txt")
Do ##class(SNOMED.TransitiveClosure).Compute()
Halt
EOF
```

### Existing config/mcp-config.toml (from Story 3.3)

Already exists at `config/mcp-config.toml` with:
- Transport: stdio
- Server: localhost:1972 (CSPSystem/SYS)
- Endpoint: /mcp/snomed
- Logging: info level to file

This file needs only minor comment improvements — no structural changes.

### Critical Implementation Rules

- **Create `README.md` at project root** — this is a NEW file
- **Do NOT modify any `.cls` source files** — documentation only
- **Do NOT modify `module.xml`, `Dockerfile`, `docker-compose.yml`** — only reference them
- **Tool list MUST match actual ToolSet** — exactly 9 tools as listed above
- **config/mcp-config.toml already exists** — only add/improve inline comments if needed
- **Use GitHub-flavored markdown** — tables, code blocks, headings
- **Include BOTH Docker and IPM installation paths** — Docker for quick start, IPM for existing IRIS instances
- **Ollama is OPTIONAL** — only needed for embedding generation and semantic search
- **Do NOT include actual RF2 data or download links** — users must obtain their own SNOMED license

### What NOT To Do

- Do NOT create any new source code files
- Do NOT modify existing code
- Do NOT include copyrighted SNOMED data
- Do NOT add external badges that require service registration
- Do NOT write a CONTRIBUTING.md or LICENSE file (out of scope)
- Do NOT document internal implementation details (globals, SQL schema)
- Do NOT change `config/mcp-config.toml` structure — only add comments

### Testing Strategy

1. **Verify README renders** — valid markdown with no broken links
2. **Verify tool count** — exactly 9 tools documented
3. **Verify file paths** — all referenced files exist in the project
4. **Verify config template** — `config/mcp-config.toml` has appropriate comments

### Previous Story Intelligence

From Story 5.2:
- `Dockerfile` exists at project root
- `docker-compose.yml` exists with iris + ollama services
- `iris-init.script` used for build-time class loading
- Container name pattern: service name from compose (e.g., `iris`)
- Ports: 1972 (SuperServer), 52773 (Web Portal), 11434 (Ollama)

From Story 5.1:
- `module.xml` at project root (snomed-iris v0.4.0)
- `requirements.txt` at project root (just `requests`)
- IPM install via `zpm "install snomed-iris"`

From Story 3.3:
- `config/mcp-config.toml` already exists
- `SNOMED.MCP.Service` with `SPECIFICATION = "SNOMED.ToolSet"`
- `iris-mcp-server` is an external binary (not part of this repo)

### Project File Structure (for README reference)

```
snomed-iris/
├── module.xml              # IPM package definition
├── requirements.txt        # Python dependencies
├── Dockerfile              # Docker build
├── docker-compose.yml      # Docker Compose with Ollama
├── iris-init.script        # Build-time class loader
├── config/
│   └── mcp-config.toml    # iris-mcp-server configuration
└── src/SNOMED/
    ├── Concept.cls         # Data model
    ├── ConceptEmbedding.cls
    ├── Description.cls
    ├── Embeddings.cls      # Embedding generation
    ├── Hierarchy.cls       # Hierarchy navigation
    ├── Installer.cls       # Post-install setup
    ├── Loader.cls          # RF2 data loading
    ├── Relationship.cls
    ├── Search.cls          # Lexical + Semantic search
    ├── ToolSet.cls         # MCP tool registry
    ├── TransitiveClosure.cls
    ├── MCP/Service.cls     # MCP service endpoint
    └── Tools/
        ├── Hierarchy.cls   # Hierarchy MCP tools
        ├── Lookup.cls      # Lookup MCP tools
        ├── Search.cls      # Search MCP tools
        └── Semantic.cls    # Semantic search MCP tool
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.3]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 136-154: config.toml]
- [Source: config/mcp-config.toml — existing MCP configuration template]
- [Source: _bmad-output/implementation-artifacts/5-2-docker-container-image.md — Docker context]
- [Source: _bmad-output/implementation-artifacts/5-1-ipm-package-structure.md — IPM context]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- README.md already existed with Rust CLI docs — added "IRIS for Health AI Hub Edition" section rather than replacing
- config/mcp-config.toml improved with inline comments explaining each section (transport, server, pool, endpoints, logging)
- Added Claude Code settings path alongside Claude Desktop path in config comments
- All 10 referenced files verified to exist in project structure
- Tool count verified: 4 Include classes in ToolSet → 9 methods documented

### Completion Notes List

- Added comprehensive "IRIS for Health AI Hub Edition" section to existing README.md
- Documents: prerequisites, Docker quick start, IPM install, RF2 loading, embedding generation, MCP configuration
- All 9 MCP tools documented in tables with parameters and example queries
- Updated config/mcp-config.toml with descriptive inline comments for all sections
- All acceptance criteria satisfied: README exists, quick-start included, tools documented, config template works

### File List

- README.md (MODIFIED — added IRIS AI Hub section)
- config/mcp-config.toml (MODIFIED — added inline comments)
