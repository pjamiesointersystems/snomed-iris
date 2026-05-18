---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: ['_bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md', '_bmad-output/project-context.md']
---

# snomed-iris - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for snomed-iris, decomposing the requirements from the technical research report and architecture decisions into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: Load SNOMED CT RF2 release files (Concepts, Descriptions, Relationships) into IRIS persistent storage
FR2: Store and query SNOMED CT concepts, descriptions, and relationships via SQL
FR3: Perform full-text lexical search across concept descriptions
FR4: Compute and store transitive closure for the SNOMED hierarchy with O(1) subsumption checking
FR5: Expose SNOMED operations (lookup, search, hierarchy) as MCP tools for Claude Desktop/Code
FR6: Generate vector embeddings for concept descriptions and perform semantic similarity search
FR7: Package the solution as an IPM module distributable via Docker container

### NonFunctional Requirements

NFR1: Must handle 831K+ concepts (UK SNOMED Monolith) — stream processing, no full dataset in memory
NFR2: RF2 bulk load should complete in under 60 seconds on modern hardware
NFR3: Concept lookup and subsumption checks must be O(1) via global-based transitive closure
NFR4: Vector search must use ANN indexing for sub-second semantic queries across 831K embeddings
NFR5: EAP API dependencies must be isolated via adapter pattern to mitigate pre-GA API changes

### Additional Requirements

- Hybrid ObjectScript/Python: Python for ETL/compute, ObjectScript for runtime tools and MCP
- %Persistent classes for SQL-accessible data + globals (^SNOMED.TC) for hierarchy
- IRIS VECTOR(DOUBLE, 384) type with HNSW ANN index for embeddings
- %AI.Tool/%AI.ToolSet/%AI.MCP.Service pattern for tool exposure
- iris-mcp-server with config.toml for Claude Desktop/Code connectivity
- IPM module.xml with Python requirements.txt installer hook
- Docker container based on irishealth-community:2026.2.0AI
- Ollama integration via OpenAI-compatible provider for embedding generation

### UX Design Requirements

N/A - No UI; this is a CLI/MCP tool

### FR Coverage Map

FR1: Epic 1 - RF2 ingestion into IRIS persistent storage
FR2: Epic 1 - SQL-queryable concept/description/relationship tables
FR3: Epic 2 - Full-text lexical search across descriptions
FR4: Epic 2 - Transitive closure computation and O(1) hierarchy queries
FR5: Epic 3 - MCP tool exposure for Claude Desktop/Code
FR6: Epic 4 - Vector embeddings and semantic similarity search
FR7: Epic 5 - IPM packaging and Docker distribution

## Epic List

### Epic 1: SNOMED CT Data Foundation
Users can load a SNOMED CT RF2 release into IRIS and query concepts, descriptions, and relationships via SQL.
**FRs covered:** FR1, FR2
**NFRs:** NFR1, NFR2, NFR5

### Epic 2: Terminology Search & Navigation
Users can find SNOMED concepts via full-text lexical search and navigate the hierarchy (ancestors, descendants, subsumption checking).
**FRs covered:** FR3, FR4
**NFRs:** NFR3, NFR5

### Epic 3: MCP Tool Exposure
Claude Desktop/Code users can look up concepts, search terminology, and navigate the SNOMED hierarchy via natural language through MCP tools.
**FRs covered:** FR5
**NFRs:** NFR5

### Epic 4: Semantic Search
Users can find SNOMED concepts by meaning (not just text match) using vector embeddings and similarity search, exposed as an MCP tool.
**FRs covered:** FR6
**NFRs:** NFR4, NFR5

### Epic 5: Packaging & Distribution
Teams can install the SNOMED tool via IPM or deploy as a Docker container with a single command.
**FRs covered:** FR7
**NFRs:** NFR5

---

## Epic 1: SNOMED CT Data Foundation

Users can load a SNOMED CT RF2 release into IRIS and query concepts, descriptions, and relationships via SQL.

### Story 1.1: SNOMED CT Data Model

As a developer,
I want persistent classes for SNOMED CT concepts, descriptions, and relationships with appropriate indexes,
So that RF2 data can be stored and queried via SQL.

**Acceptance Criteria:**

**Given** the IRIS namespace is configured
**When** the classes are compiled
**Then** SQL tables `SNOMED.Concept`, `SNOMED.Description`, and `SNOMED.Relationship` exist
**And** `SNOMED.Concept` has properties: ConceptId (string, unique indexed), Active (boolean), EffectiveTime, ModuleId, DefinitionStatusId
**And** `SNOMED.Description` has properties: DescriptionId (string, unique indexed), ConceptId (indexed), Term (string, max 1024), TypeId, Active, LanguageCode
**And** `SNOMED.Relationship` has properties: RelationshipId (string, unique indexed), SourceId (indexed), DestinationId (indexed), TypeId (indexed), Active
**And** all ConceptId/SourceId/DestinationId fields are stored as strings (SCTIDs can be very large)

### Story 1.2: RF2 Concept and Description Loader

As a terminology administrator,
I want to load SNOMED CT concept and description RF2 files into IRIS,
So that the terminology is available for querying.

**Acceptance Criteria:**

**Given** valid RF2 concept file (tab-separated, header row) and description file exist on the filesystem
**When** the loader method `SNOMED.Loader.LoadConcepts(filepath)` is called
**Then** all rows are inserted into `SNOMED.Concept` via SQL prepared statements
**And** processing is streamed line-by-line (no full dataset in memory)
**And** progress is reported every 50,000 records
**And** the method returns `$$$OK` status on success

**Given** valid RF2 description file exists
**When** `SNOMED.Loader.LoadDescriptions(filepath)` is called
**Then** all rows are inserted into `SNOMED.Description`
**And** the UK Monolith (831K+ concepts, ~1.5M descriptions) loads in under 60 seconds total

**Given** an invalid or missing filepath
**When** the loader is called
**Then** a meaningful error status is returned

### Story 1.3: RF2 Relationship Loader

As a terminology administrator,
I want to load SNOMED CT relationship RF2 files into IRIS,
So that hierarchical and associative relationships are available for querying.

**Acceptance Criteria:**

**Given** valid RF2 relationship file (tab-separated, header row) exists
**When** `SNOMED.Loader.LoadRelationships(filepath)` is called
**Then** all rows are inserted into `SNOMED.Relationship`
**And** processing is streamed line-by-line
**And** only active IS-A relationships (typeId = 116680003) are flagged for hierarchy use
**And** progress is reported every 50,000 records

**Given** relationships reference concept IDs
**When** querying `SNOMED.Relationship` by SourceId or DestinationId
**Then** results are returned efficiently via indexed lookups

---

## Epic 2: Terminology Search & Navigation

Users can find SNOMED concepts via full-text lexical search and navigate the hierarchy (ancestors, descendants, subsumption checking).

### Story 2.1: Full-Text Lexical Search

As a terminology user,
I want to search for SNOMED concepts by keyword or phrase across description terms,
So that I can find relevant concepts without knowing their exact identifiers.

**Acceptance Criteria:**

**Given** SNOMED descriptions are loaded into `SNOMED.Description`
**When** a text index is created on the Term property
**Then** SQL queries using the text search capability return matching descriptions

**Given** a search term like "diabetes"
**When** the search method `SNOMED.Search.Lexical(term)` is called
**Then** all active descriptions containing the term are returned with ConceptId, Term, and TypeId
**And** results are ordered by relevance
**And** results include only active concepts (joined to SNOMED.Concept.Active = 1)
**And** search performs efficiently against 1.5M+ descriptions

### Story 2.2: Transitive Closure Computation

As a terminology administrator,
I want to compute and store the transitive closure of SNOMED's IS-A hierarchy,
So that ancestor/descendant queries and subsumption checks are instantaneous.

**Acceptance Criteria:**

**Given** SNOMED relationships are loaded with active IS-A relationships (typeId = 116680003)
**When** `SNOMED.TransitiveClosure.Compute()` is called
**Then** the global `^SNOMED.TC(ancestorId, descendantId)` is populated for all transitive IS-A paths
**And** the computation handles the full SNOMED hierarchy (~831K concepts) without running out of memory
**And** a direct parent-child global `^SNOMED.Children(parentId, childId)` is also populated
**And** progress is reported during computation

**Given** the transitive closure is computed
**When** checking `$DATA(^SNOMED.TC("73211009", "46635009"))` (Diabetes mellitus -> Type 1 diabetes)
**Then** the result confirms the IS-A relationship exists (returns true)

### Story 2.3: Hierarchy Navigation Methods

As a terminology user,
I want to query ancestors, descendants, and check subsumption for any SNOMED concept,
So that I can navigate the terminology hierarchy programmatically.

**Acceptance Criteria:**

**Given** transitive closure is computed and stored in `^SNOMED.TC`
**When** `SNOMED.Hierarchy.IsDescendantOf(conceptId, ancestorId)` is called
**Then** it returns true/false in O(1) time via global lookup

**Given** a valid concept ID
**When** `SNOMED.Hierarchy.GetAncestors(conceptId)` is called
**Then** all ancestor concept IDs are returned as a JSON array

**Given** a valid concept ID
**When** `SNOMED.Hierarchy.GetDescendants(conceptId)` is called
**Then** all descendant concept IDs are returned as a JSON array

**Given** a valid concept ID
**When** `SNOMED.Hierarchy.GetChildren(conceptId)` is called
**Then** only direct children are returned (from `^SNOMED.Children` global)

**Given** a valid concept ID
**When** `SNOMED.Hierarchy.GetParents(conceptId)` is called
**Then** only direct parents are returned

---

## Epic 3: MCP Tool Exposure

Claude Desktop/Code users can look up concepts, search terminology, and navigate the SNOMED hierarchy via natural language through MCP tools.

### Story 3.1: SNOMED Lookup and Search Tools

As a Claude Desktop/Code user,
I want MCP tools that let me look up SNOMED concepts by ID and search by term,
So that I can query terminology through natural language conversation.

**Acceptance Criteria:**

**Given** the `SNOMED.Tools.Lookup` class extends `%AI.Tool`
**When** the tool `GetConcept(sctid)` is called with a valid SNOMED concept ID
**Then** it returns JSON with concept details (ConceptId, FSN, Active, descriptions list)

**Given** the `SNOMED.Tools.Search` class extends `%AI.Tool`
**When** the tool `LexicalSearch(term, maxResults)` is called
**Then** it returns a JSON array of matching concepts with their preferred terms
**And** results are limited to `maxResults` (default 20)
**And** only active concepts are returned

**Given** a Query-as-Tool `SearchByPattern` is defined as a class query
**When** the LLM invokes it with a SQL LIKE pattern
**Then** matching concepts are returned in the standard `{rows, row_count, truncated}` envelope

### Story 3.2: SNOMED Hierarchy Tools

As a Claude Desktop/Code user,
I want MCP tools for navigating the SNOMED hierarchy (ancestors, descendants, subsumption),
So that I can explore clinical concept relationships through conversation.

**Acceptance Criteria:**

**Given** the `SNOMED.Tools.Hierarchy` class extends `%AI.Tool`
**When** `IsA(conceptId, ancestorId)` is called
**Then** it returns true/false indicating subsumption relationship

**When** `GetAncestors(conceptId)` is called
**Then** it returns a JSON array of ancestor concepts with their preferred terms

**When** `GetDescendants(conceptId, maxResults)` is called
**Then** it returns descendant concepts (limited to `maxResults`, default 100) with preferred terms

**When** `GetChildren(conceptId)` is called
**Then** it returns only direct child concepts with preferred terms

**When** `GetParents(conceptId)` is called
**Then** it returns only direct parent concepts with preferred terms

### Story 3.3: MCP Service and Server Configuration

As a Claude Desktop/Code user,
I want the SNOMED tools registered as an MCP service accessible via `iris-mcp-server`,
So that I can use SNOMED tools directly from my AI assistant.

**Acceptance Criteria:**

**Given** `SNOMED.ToolSet` extends `%AI.ToolSet` with XData Definition including all tool classes
**When** the ToolSet is compiled
**Then** it composes Lookup, Search, and Hierarchy tools into a single discoverable set

**Given** `SNOMED.MCP.Service` extends `%AI.MCP.Service` with `Parameter SPECIFICATION = "SNOMED.ToolSet"`
**When** registered as an MCP Server at path `/mcp/snomed` in Management Portal
**Then** `iris-mcp-server` discovers and exposes all SNOMED tools to connected clients

**Given** a `config.toml` template with stdio transport pointing to `/mcp/snomed`
**When** configured in Claude Desktop's `claude_desktop_config.json`
**Then** Claude Desktop shows the SNOMED tools as available
**And** tool calls execute successfully and return results

---

## Epic 4: Semantic Search

Users can find SNOMED concepts by meaning (not just text match) using vector embeddings and similarity search, exposed as an MCP tool.

### Story 4.1: Embedding Storage and Vector Schema

As a developer,
I want a persistent class with a VECTOR column to store concept description embeddings,
So that semantic similarity search can be performed via SQL.

**Acceptance Criteria:**

**Given** the IRIS namespace is configured
**When** `SNOMED.ConceptEmbedding` class is compiled
**Then** a SQL table exists with ConceptId (string, indexed), Term (string), and Embedding (VECTOR(DOUBLE, 384))
**And** an ANN index (HNSW) is defined on the Embedding column for efficient similarity search

**Given** the table exists
**When** an embedding vector is inserted via SQL `INSERT INTO SNOMED.ConceptEmbedding (ConceptId, Term, Embedding) VALUES (?, ?, TO_VECTOR(?))`
**Then** the vector is stored and queryable via `VECTOR_COSINE()` similarity function

### Story 4.2: Embedding Generation Pipeline

As a terminology administrator,
I want to generate vector embeddings for all active SNOMED concept descriptions using Ollama,
So that the terminology is searchable by semantic meaning.

**Acceptance Criteria:**

**Given** Ollama is running with an embedding model (e.g., `all-minilm` or `nomic-embed-text`)
**When** `SNOMED.Embeddings.Generate(modelName, batchSize)` is called
**Then** embeddings are generated for all active Fully Specified Names
**And** processing is batched (default batch size 100) to manage memory
**And** progress is reported (count and percentage)
**And** embeddings are inserted into `SNOMED.ConceptEmbedding` via SQL prepared statements
**And** the process can be resumed (skips concepts that already have embeddings)

**Given** Ollama is unreachable or returns an error
**When** the generation method is called
**Then** a meaningful error is returned and partial progress is preserved

### Story 4.3: Semantic Search Method and MCP Tool

As a Claude Desktop/Code user,
I want to search for SNOMED concepts by semantic meaning through an MCP tool,
So that I can find relevant concepts even when I don't know the exact clinical terminology.

**Acceptance Criteria:**

**Given** embeddings are stored in `SNOMED.ConceptEmbedding`
**When** `SNOMED.Search.Semantic(query, maxResults)` is called with a natural language query
**Then** the query is embedded via Ollama
**And** `VECTOR_COSINE()` similarity search returns the top N matching concepts
**And** results include ConceptId, Term, and similarity score
**And** only results above a minimum threshold (default 0.5) are returned
**And** search completes in under 1 second for 831K embeddings (via ANN index)

**Given** the `SNOMED.Tools.Semantic` class extends `%AI.Tool`
**When** the tool `SemanticSearch(query, maxResults)` is registered in the ToolSet
**Then** it is discoverable and callable via the MCP service
**And** the ToolSet XData is updated to include the Semantic tool class

---

## Epic 5: Packaging & Distribution

Teams can install the SNOMED tool via IPM or deploy as a Docker container with a single command.

### Story 5.1: IPM Package Structure

As a developer,
I want the project structured as an IPM module with `module.xml`,
So that it can be installed into any IRIS for Health instance via `zpm "install snomed-iris"`.

**Acceptance Criteria:**

**Given** the project has a `module.xml` at its root
**When** IPM reads the module definition
**Then** it identifies the package name (`snomed-iris`), version, description, and keywords
**And** `SourcesRoot` points to the `src/` directory containing all `.cls` files
**And** a `requirements.txt` is included listing Python dependencies (e.g., `requests`)
**And** an installer class `SNOMED.Installer` is invoked during the Configure phase

**Given** the installer class is invoked
**When** `SNOMED.Installer.Setup()` executes
**Then** Python dependencies are installed via pip
**And** the MCP Server application `/mcp/snomed` is registered programmatically
**And** a success message confirms installation

### Story 5.2: Docker Container Image

As a DevOps engineer,
I want a Dockerfile that builds a ready-to-run IRIS for Health container with SNOMED tools pre-installed,
So that teams can deploy with `docker run` without manual setup.

**Acceptance Criteria:**

**Given** a `Dockerfile` based on `irishealth-community:2026.2.0AI`
**When** `docker build` is executed
**Then** the image installs the IPM package, compiles all classes, and configures the MCP server application
**And** the `iris-mcp-server` binary and `config.toml` template are included
**And** ports 1972 (SuperServer) and 52773 (Web Portal) are exposed

**Given** the built image
**When** `docker run` is executed
**Then** IRIS starts with the SNOMED namespace ready
**And** the MCP server endpoint `/mcp/snomed` is accessible
**And** a `docker-compose.yml` is provided showing Ollama sidecar configuration for embeddings

### Story 5.3: Documentation and Getting Started Guide

As a new user,
I want clear documentation on how to install, load data, and connect to Claude Desktop,
So that I can get the SNOMED MCP tools working quickly.

**Acceptance Criteria:**

**Given** a `README.md` exists in the project root
**When** a user reads it
**Then** it explains: prerequisites (IRIS 2026.2.0AI, Ollama optional), installation (IPM or Docker), RF2 data loading steps, MCP configuration for Claude Desktop/Code
**And** includes a quick-start section with copy-paste commands
**And** documents all available MCP tools with example queries

**Given** a `config/mcp-config.toml` template exists
**When** a user copies it and adjusts host/credentials
**Then** it works with `iris-mcp-server` out of the box for local development
