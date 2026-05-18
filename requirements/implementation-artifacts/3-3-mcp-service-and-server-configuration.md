# Story 3.3: MCP Service and Server Configuration

Status: review

## Story

As a Claude Desktop/Code user,
I want the SNOMED tools registered as an MCP service accessible via `iris-mcp-server`,
so that I can use SNOMED tools directly from my AI assistant.

## Acceptance Criteria

1. `SNOMED.ToolSet` extends `%AI.ToolSet` with XData Definition including all tool classes (Lookup, Search, Hierarchy)
2. `SNOMED.MCP.Service` extends `%AI.MCP.Service` with `Parameter SPECIFICATION = "SNOMED.ToolSet"`
3. Both classes compile successfully in the IRIS container
4. A `config.toml` template is provided for `iris-mcp-server` stdio transport pointing to `/mcp/snomed`
5. A Claude Desktop config snippet is documented for connecting to the SNOMED MCP service

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.ToolSet` class (AC: #1, #3)
  - [x] Create `src/SNOMED/ToolSet.cls` extending `%AI.ToolSet`
  - [x] Add XData Definition block with `<ToolSet>` XML including all three tool classes
  - [x] Include `<Description>` for the tool set
- [x] Task 2: Create `SNOMED.MCP.Service` class (AC: #2, #3)
  - [x] Create `src/SNOMED/MCP/Service.cls` extending `%AI.MCP.Service`
  - [x] Set `Parameter SPECIFICATION = "SNOMED.ToolSet"`
- [x] Task 3: Create config templates (AC: #4, #5)
  - [x] Create `config/mcp-config.toml` with iris-mcp-server stdio configuration
  - [x] Include Claude Desktop config snippet as comments in the TOML file
- [x] Task 4: Test compilation in Docker (AC: #3)
  - [x] Compile ToolSet class and verify no errors
  - [x] Compile MCP.Service class and verify no errors
  - [x] Verify ToolSet discovers the included tool classes

## Dev Notes

### Architecture Pattern

This story wires up the plumbing that connects the `%AI.Tool` classes (Stories 3.1-3.2) to the `iris-mcp-server` binary. The architecture is:

```
Claude Desktop/Code → iris-mcp-server (Rust binary, stdio)
    → IRIS /mcp/snomed endpoint
    → SNOMED.MCP.Service (%AI.MCP.Service)
    → SNOMED.ToolSet (%AI.ToolSet)
    → SNOMED.Tools.Lookup, SNOMED.Tools.Search, SNOMED.Tools.Hierarchy
```

### %AI.ToolSet Pattern

```objectscript
Class SNOMED.ToolSet Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="SNOMEDTools">
    <Description>SNOMED CT terminology operations - concept lookup, lexical search, and hierarchy navigation</Description>
    <Include Class="SNOMED.Tools.Lookup"/>
    <Include Class="SNOMED.Tools.Search"/>
    <Include Class="SNOMED.Tools.Hierarchy"/>
</ToolSet>
}

}
```

### %AI.MCP.Service Pattern

```objectscript
Class SNOMED.MCP.Service Extends %AI.MCP.Service
{

Parameter SPECIFICATION = "SNOMED.ToolSet";

}
```

Key facts about `%AI.MCP.Service` (confirmed from container inspection):
- Extends `%CSP.REST, %CSP.WebSocket`
- Has `Parameter SPECIFICATION` — set to the ToolSet class name
- Has `Parameter SpecificationClass` — alternative parameter (may be needed if SPECIFICATION doesn't work)
- Version: "IRIS MCP Gateway v1.0.1"

### config.toml for iris-mcp-server

```toml
[mcp]
transport = "stdio"

[[iris]]
name = "local"

[iris.server]
host = "localhost"
port = 1972
username = "CSPSystem"
password = "SYS"

[iris.pool]
min = 2
max = 5

[[iris.endpoints]]
path = "/mcp/snomed"

[logging]
level = "info"
output = "file"
file = "iris-mcp-snomed.log"
```

### Claude Desktop Configuration

In `claude_desktop_config.json`:
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

### MCP Server Registration

After compilation, the MCP Service needs to be registered as a web application in IRIS:
- Path: `/mcp/snomed`
- Class: `SNOMED.MCP.Service`
- Namespace: `USER`

This is done via Management Portal: System Administration > Security > Applications > Web Applications > Create New.

Note: For the dev story, we only need to verify compilation. Actual registration requires Management Portal access or programmatic setup which is deployment-specific.

### Critical Implementation Rules

- **ToolSet XData MUST be `application/xml`** — the MimeType attribute is required
- **`<Include Class="..."/>` references full class names** — including package
- **SPECIFICATION parameter is a STRING** — set to the full class name of the ToolSet
- **File structure follows research architecture:**
  - `src/SNOMED/ToolSet.cls`
  - `src/SNOMED/MCP/Service.cls`
  - `config/mcp-config.toml`
- **No runtime testing of MCP server** — `iris-mcp-server` binary may not be in the container; just verify compilation

### What NOT To Do

- Do NOT try to run `iris-mcp-server` in the container — it may not be installed
- Do NOT try to register the web application programmatically — that's deployment, not development
- Do NOT include credentials in the config template that aren't clearly marked as examples
- Do NOT modify any existing Tool classes — this story only creates ToolSet, Service, and config
- Do NOT use `SpecificationClass` parameter — use `SPECIFICATION` (matches research doc pattern)

### EAP API Risk

If `%AI.ToolSet` doesn't support `XData Definition` with `<ToolSet>` XML, or if the XML schema differs from the research doc, the compilation may fail. Document the error and try alternative approaches:
1. Try without `<ToolSet Name="...">` wrapper
2. Try with just `<Include>` elements directly
3. Check if there's a different XData format expected

### Previous Story Intelligence

From Story 3.1/3.2:
- `%AI.Tool` exists and works — all three tool classes compile and function
- `%AI.ToolSet` exists and extends `%AI.Tool`
- `%AI.MCP.Service` exists, extends `%CSP.REST,%CSP.WebSocket`, has SPECIFICATION parameter
- Docker container: `iris-ai-hub`, compile via `$SYSTEM.OBJ.Load()`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.3]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 99-166: Tool Registration + config.toml]
- [Source: src/SNOMED/Tools/*.cls — tool classes to compose into ToolSet]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `%AI.ToolSet` XData Definition with `<ToolSet>` XML works exactly as documented in research
- `%Discover()` returns full JSON schema for all 8 tools with parameter types, descriptions, and metadata
- Query-as-Tool (`SearchByPattern`) automatically gets `{columns, rows, row_count, truncated, elapsed_ms}` envelope
- `%AI.MCP.Service` SPECIFICATION parameter accepts ToolSet class name string

### Completion Notes List

- Created `SNOMED.ToolSet` extending `%AI.ToolSet` with XData composing 3 tool classes
- Created `SNOMED.MCP.Service` extending `%AI.MCP.Service` with SPECIFICATION = "SNOMED.ToolSet"
- Created `config/mcp-config.toml` with stdio transport, connection pool, and `/mcp/snomed` endpoint
- ToolSet `%Discover()` returns all 8 tools: GetConcept, LexicalSearch, SearchByPattern, IsA, GetAncestors, GetDescendants, GetChildren, GetParents
- Each tool has proper JSON Schema parameters, descriptions from `///` comments, and return types
- Both classes compile cleanly in IRIS 2026.2.0AI

### File List

- src/SNOMED/ToolSet.cls (NEW)
- src/SNOMED/MCP/Service.cls (NEW)
- config/mcp-config.toml (NEW)
