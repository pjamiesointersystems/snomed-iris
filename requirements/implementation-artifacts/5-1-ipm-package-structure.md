# Story 5.1: IPM Package Structure

Status: review

## Story

As a developer,
I want the project structured as an IPM module with `module.xml`,
so that it can be installed into any IRIS for Health instance via `zpm "install snomed-iris"`.

## Acceptance Criteria

1. A `module.xml` at the project root identifies package name (`snomed-iris`), version, description, and keywords
2. `SourcesRoot` points to the `src/` directory containing all `.cls` files
3. A `requirements.txt` is included listing Python dependencies (e.g., `requests`)
4. An installer class `SNOMED.Installer` is invoked during the Configure phase
5. `SNOMED.Installer.Setup()` installs Python dependencies via pip
6. `SNOMED.Installer.Setup()` registers the MCP Server application `/mcp/snomed` programmatically
7. A success message confirms installation

## Tasks / Subtasks

- [x] Task 1: Create `module.xml` (AC: #1, #2)
  - [x] Create `module.xml` at project root with package name, version, description, keywords
  - [x] Set `<SourcesRoot>src</SourcesRoot>`
  - [x] Include `<Invoke Class="SNOMED.Installer" Method="Setup" Phase="Configure"/>` for post-install hook
- [x] Task 2: Create `requirements.txt` (AC: #3)
  - [x] Create `requirements.txt` at project root listing `requests` dependency
- [x] Task 3: Create `SNOMED.Installer` class (AC: #4, #5, #6, #7)
  - [x] Create `src/SNOMED/Installer.cls` extending `%RegisteredObject`
  - [x] Implement `Setup()` classmethod that installs pip dependencies
  - [x] Implement web application registration for `/mcp/snomed` pointing to `SNOMED.MCP.Service`
  - [x] Print success message on completion
- [x] Task 4: Test compilation and verify (AC: #1-#7)
  - [x] Compile `SNOMED.Installer` in Docker container
  - [x] Verify `Setup()` runs without error (pip install + web app registration)
  - [x] Verify `module.xml` is well-formed XML

## Dev Notes

### Architecture Pattern

IPM (InterSystems Package Manager) is the standard distribution mechanism for IRIS applications. The `module.xml` defines the package metadata and the `Invoke` element triggers the installer after all classes are compiled.

### module.xml Structure (from research)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Export generator="IRIS" version="26">
  <Module>
    <Name>snomed-iris</Name>
    <Version>0.4.0</Version>
    <Description>SNOMED CT Terminology Services with MCP Tools for IRIS AI Hub</Description>
    <Keywords>snomed,terminology,mcp,ai-hub,vector-search</Keywords>
    <SourcesRoot>src</SourcesRoot>
    <Resource Name="SNOMED.PKG"/>
    <Invoke Class="SNOMED.Installer" Method="Setup" Phase="Configure"/>
  </Module>
</Export>
```

Key elements:
- `<Name>`: Package identifier used in `zpm "install snomed-iris"`
- `<Version>`: Semantic version — use 0.4.0 to match current project maturity
- `<SourcesRoot>src</SourcesRoot>`: IPM loads all `.cls` files from this directory recursively
- `<Resource Name="SNOMED.PKG"/>`: Tells IPM to include the entire SNOMED package
- `<Invoke>`: Post-compile hook — runs after all classes are loaded

### SNOMED.Installer Implementation

The installer needs to:
1. Install Python pip dependencies from `requirements.txt`
2. Register `/mcp/snomed` web application programmatically

```objectscript
Class SNOMED.Installer Extends %RegisteredObject
{

ClassMethod Setup() As %Status
{
    Set sc = $$$OK

    // Step 1: Install Python dependencies
    Set sc = ..InstallPythonDeps()
    If $$$ISERR(sc) Return sc

    // Step 2: Register MCP web application
    Set sc = ..RegisterMCPApp()
    If $$$ISERR(sc) Return sc

    Write "SNOMED CT MCP Tools installation complete.",!
    Return $$$OK
}

ClassMethod InstallPythonDeps() As %Status [ Language = python ]
{
    import iris
    import subprocess
    import os

    # Find requirements.txt relative to the module install location
    # During IPM install, the working directory may vary
    req_file = os.path.join(os.environ.get("IRISLIB", "/usr/irissys/lib"), "..", "mgr", "snomed-iris", "requirements.txt")

    # Fallback: try common locations
    candidates = [
        "/opt/irissys/mgr/snomed-iris/requirements.txt",
        "/usr/irissys/mgr/snomed-iris/requirements.txt",
        "requirements.txt"
    ]

    found = None
    for path in candidates:
        if os.path.isfile(path):
            found = path
            break

    if found is None:
        print("Warning: requirements.txt not found, skipping pip install")
        return iris.cls("%SYSTEM.Status").OK()

    print(f"Installing Python dependencies from {found}...")
    result = subprocess.run(
        ["pip", "install", "-r", found, "--quiet"],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"Warning: pip install returned non-zero: {result.stderr}")
    else:
        print("Python dependencies installed successfully")

    return iris.cls("%SYSTEM.Status").OK()
}

ClassMethod RegisterMCPApp() As %Status
{
    // Create /mcp/snomed web application
    New $Namespace
    Set $Namespace = "%SYS"

    Set props("DispatchClass") = "SNOMED.MCP.Service"
    Set props("NameSpace") = "USER"
    Set props("Description") = "SNOMED CT MCP Service"
    Set props("Enabled") = 1
    Set props("AutheEnabled") = 64  // Unauthenticated
    Set props("Resource") = ""

    Set sc = ##class(Security.Applications).Create("/mcp/snomed", .props)
    If $$$ISERR(sc) {
        // If already exists, try to modify instead
        If ##class(Security.Applications).Exists("/mcp/snomed") {
            Write "Web application /mcp/snomed already exists, updating...",!
            Set sc = ##class(Security.Applications).Modify("/mcp/snomed", .props)
        }
    }

    If $$$ISERR(sc) {
        Write "Warning: Could not register /mcp/snomed: ",$System.Status.GetErrorText(sc),!
        // Don't fail installation for this — it may need manual portal setup
        Return $$$OK
    }

    Write "Registered web application /mcp/snomed",!
    Return $$$OK
}

}
```

### Web Application Registration

The `Security.Applications` class in `%SYS` namespace handles web app registration:
- Must switch to `%SYS` namespace temporarily
- `Create()` takes path and properties array
- `AutheEnabled = 64` means unauthenticated access (suitable for local dev)
- If it already exists, modify instead of failing
- The installer should NOT fail the entire installation if web app registration fails (deployment-specific)

### requirements.txt

Simple file listing Python dependencies:
```
requests
```

Only `requests` is needed — it's used by `SNOMED.Embeddings.Generate()` and `SNOMED.Search.Semantic()`.

### Critical Implementation Rules

- **`module.xml` at project ROOT** — not in `src/` or `config/`
- **`requirements.txt` at project ROOT** — next to module.xml
- **Version = "0.4.0"** — matches project status (Epics 1-4 complete)
- **`<SourcesRoot>src</SourcesRoot>`** — IPM loads all .cls files recursively from src/
- **`<Resource Name="SNOMED.PKG"/>`** — includes all classes in the SNOMED package
- **Installer class at `src/SNOMED/Installer.cls`** — so it gets compiled by IPM before invocation
- **Do NOT fail on web app registration error** — return OK with warning; deployment may need different auth
- **Do NOT fail on pip install error** — `requests` may already be installed; just warn
- **`New $Namespace` before switching** — preserve caller's namespace
- **`Set $Namespace = "%SYS"`** — required for Security.Applications access

### What NOT To Do

- Do NOT create a Dockerfile — that's Story 5.2
- Do NOT create a README — that's Story 5.3
- Do NOT modify any existing source classes
- Do NOT add dependencies beyond `requests` — it's the only external Python package used
- Do NOT make the installer fail hard on non-critical errors (web app, pip)
- Do NOT include `config/mcp-config.toml` in module.xml — it's a template, not installable code
- Do NOT try to run `zpm "install"` — just verify module.xml is valid and Installer compiles/runs

### Testing Strategy

1. **Verify module.xml is well-formed** — parse as XML
2. **Compile Installer.cls** — must compile without errors
3. **Run Setup()** — should complete without throwing
4. **Verify web app exists** — check `Security.Applications.Exists("/mcp/snomed")` after Setup

### Previous Story Intelligence

From Story 4.3 (most recent):
- Docker container: `iris-ai-hub`
- All SNOMED.* classes compile cleanly
- 9 MCP tools discoverable via ToolSet
- `SNOMED.MCP.Service` with `SPECIFICATION = "SNOMED.ToolSet"` ready

### Existing Source Files (for module.xml reference)

```
src/SNOMED/
  Concept.cls
  ConceptEmbedding.cls
  Description.cls
  Embeddings.cls
  Hierarchy.cls
  Loader.cls
  Relationship.cls
  Search.cls
  ToolSet.cls
  TransitiveClosure.cls
  MCP/
    Service.cls
  Tools/
    Hierarchy.cls
    Lookup.cls
    Search.cls
    Semantic.cls
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.1]
- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md — lines 373-434: IPM Packaging]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- `module.xml` validated as well-formed XML using `python3 -c "import xml.etree.ElementTree as ET; ET.parse('module.xml')"`
- `SNOMED.Installer` compiles cleanly in Docker container `iris-ai-hub`
- `Setup()` runs successfully: installs pip deps (requests already present), registers `/mcp/snomed` web app
- Idempotent: second `Setup()` call detects existing web app and updates it without error
- `InstallPythonDeps()` finds `requirements.txt` via `os.path.join(os.getcwd(), "requirements.txt")` candidate path
- `RegisterMCPApp()` switches to `%SYS` namespace, creates/modifies Security.Applications entry with AutheEnabled=64

### Completion Notes List

- Created `module.xml` at project root with IPM package metadata (name, version 0.4.0, description, keywords, SourcesRoot, Resource, Invoke)
- Created `requirements.txt` with single `requests` dependency
- Created `src/SNOMED/Installer.cls` with `Setup()`, `InstallPythonDeps()` (Python), and `RegisterMCPApp()` (ObjectScript)
- Installer gracefully handles missing requirements.txt, pip failures, and web app registration errors (warnings only, never fails install)
- All 7 acceptance criteria satisfied: module.xml identifies package, SourcesRoot points to src/, requirements.txt included, Installer invoked at Configure phase, pip install works, web app registered, success message printed

### File List

- module.xml (NEW)
- requirements.txt (NEW)
- src/SNOMED/Installer.cls (NEW)
