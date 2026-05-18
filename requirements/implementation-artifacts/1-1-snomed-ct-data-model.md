# Story 1.1: SNOMED CT Data Model

Status: review

## Story

As a developer,
I want persistent classes for SNOMED CT concepts, descriptions, and relationships with appropriate indexes,
so that RF2 data can be stored and queried via SQL.

## Acceptance Criteria

1. SQL tables `SNOMED.Concept`, `SNOMED.Description`, and `SNOMED.Relationship` exist after class compilation
2. `SNOMED.Concept` has properties: ConceptId (string, unique indexed), Active (boolean), EffectiveTime (string), ModuleId (string), DefinitionStatusId (string)
3. `SNOMED.Description` has properties: DescriptionId (string, unique indexed), ConceptId (indexed), Term (string, max 1024), TypeId (string), Active (boolean), LanguageCode (string)
4. `SNOMED.Relationship` has properties: RelationshipId (string, unique indexed), SourceId (indexed), DestinationId (indexed), TypeId (indexed), Active (boolean), RelationshipGroup (integer)
5. All SCTID fields (ConceptId, DescriptionId, RelationshipId, SourceId, DestinationId, TypeId, ModuleId, DefinitionStatusId) are stored as `%String` — never numeric
6. Classes compile cleanly and SQL tables are queryable via `SELECT * FROM SNOMED.Concept` etc.

## Tasks / Subtasks

- [x] Task 1: Create `SNOMED.Concept` persistent class (AC: #1, #2, #5)
  - [x] Define class extending `%Persistent`
  - [x] Add all properties with correct types
  - [x] Add unique index on ConceptId
  - [x] Add bitmap index on Active for filtering
- [x] Task 2: Create `SNOMED.Description` persistent class (AC: #1, #3, #5)
  - [x] Define class extending `%Persistent`
  - [x] Add all properties with correct types (Term MAXLEN=1024)
  - [x] Add unique index on DescriptionId
  - [x] Add index on ConceptId for joins
  - [x] Add index on TypeId for filtering by FSN/Synonym/Definition
- [x] Task 3: Create `SNOMED.Relationship` persistent class (AC: #1, #4, #5)
  - [x] Define class extending `%Persistent`
  - [x] Add all properties with correct types
  - [x] Add unique index on RelationshipId
  - [x] Add indexes on SourceId, DestinationId, TypeId
- [x] Task 4: Verify compilation and SQL access (AC: #6)
  - [x] Compile all three classes
  - [x] Verify SQL tables exist via Management Portal or `iris session`
  - [x] Run sample SELECT queries against each table

## Dev Notes

### Architecture Pattern

This is a **greenfield IRIS project** (`snomed-iris`). These are the first classes being created. Follow the package structure from the research report:

```
src/
  SNOMED/
    Concept.cls
    Description.cls
    Relationship.cls
```

### Critical Implementation Rules

- **SCTIDs are STRINGS, not numbers.** SNOMED concept IDs like `138875005` look numeric but can exceed integer limits and must preserve leading zeros in some contexts. Always use `%String`.
- **EffectiveTime is a STRING** in RF2 format (`YYYYMMDD`). Store as `%String(MAXLEN=8)`, not `%Date`.
- **TypeId fields are SCTIDs** referencing other concepts (e.g., `116680003` = IS-A relationship type, `900000000000003001` = FSN type). Store as `%String`.
- **No `%New()`/`%Save()` pattern for bulk loading** — Story 1.2 will use SQL prepared statements for performance. These classes just define the schema.
- **Property MAXLEN matters** — `Term` in descriptions can be very long (up to ~1000 chars for some FSNs). Use `MAXLEN = 1024`.

### ObjectScript Class Syntax Reference

```objectscript
Class SNOMED.Concept Extends %Persistent
{

Property ConceptId As %String(MAXLEN = 20) [ Required ];

Property Active As %Boolean;

Property EffectiveTime As %String(MAXLEN = 8);

Property ModuleId As %String(MAXLEN = 20);

Property DefinitionStatusId As %String(MAXLEN = 20);

Index ConceptIdIdx On ConceptId [ Unique ];

Index ActiveIdx On Active [ Type = bitmap ];

}
```

### Index Strategy

| Table | Index | Type | Purpose |
|-------|-------|------|---------|
| Concept | ConceptIdIdx | Unique | O(1) lookup by SCTID |
| Concept | ActiveIdx | Bitmap | Fast filtering of active concepts |
| Description | DescriptionIdIdx | Unique | O(1) lookup |
| Description | ConceptIdIdx | Standard | Join to Concept table |
| Description | TypeIdIdx | Standard | Filter FSN vs Synonym |
| Relationship | RelationshipIdIdx | Unique | O(1) lookup |
| Relationship | SourceIdIdx | Standard | Find relationships FROM a concept |
| Relationship | DestinationIdIdx | Standard | Find relationships TO a concept |
| Relationship | TypeIdIdx | Standard | Filter by relationship type (IS-A, etc.) |

### What NOT To Do

- Do NOT add foreign key constraints between tables — RF2 data may have dangling references during partial loads
- Do NOT add computed/derived properties — keep classes as pure data containers
- Do NOT add class methods yet — those come in later stories (Loader in 1.2, Search in 2.1, etc.)
- Do NOT create globals directly — `%Persistent` handles storage mapping automatically
- Do NOT use `%Integer` for any ID field — all IDs are strings

### Project Structure Notes

- Classes go in `src/SNOMED/` directory following IPM conventions (Story 5.1)
- Package name is `SNOMED` — all classes use this prefix
- File naming: `Concept.cls`, `Description.cls`, `Relationship.cls` (PascalCase matching class name)
- Target namespace: `USER` (default IRIS development namespace)

### IRIS Platform Notes

- Platform: InterSystems IRIS for Health 2026.2.0AI (Docker container)
- Classes are compiled with `$SYSTEM.OBJ.Compile("SNOMED.Concept", "ck")` or via Studio/VS Code ObjectScript extension
- SQL access is automatic once classes extend `%Persistent` — table name = package.class
- The `%Storage.Default` storage strategy is used (default) — no custom storage mapping needed

### References

- [Source: _bmad-output/planning-artifacts/research/technical-iris-for-health-ai-hub-snomed-ct-port-research-2026-05-13.md#6. Recommended Architecture]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1]
- [Source: _bmad-output/project-context.md — SCTIDs are strings, RF2 is tab-separated]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A

### Completion Notes List

- Tasks 1-3 complete: All three persistent classes created with correct properties, types, and indexes per AC #1-#5
- All SCTID fields stored as `%String(MAXLEN=20)` — never numeric (AC #5)
- `SNOMED.Concept`: ConceptId (unique), Active (bitmap), EffectiveTime, ModuleId, DefinitionStatusId
- `SNOMED.Description`: DescriptionId (unique), ConceptId (indexed), Term (MAXLEN=1024), TypeId (indexed), Active, LanguageCode
- `SNOMED.Relationship`: RelationshipId (unique), SourceId (indexed), DestinationId (indexed), TypeId (indexed), Active, RelationshipGroup
- Task 4 verified: All 3 classes compiled cleanly via `$SYSTEM.OBJ.LoadDir()`, SQL tables confirmed with correct columns (Concept:6, Description:7, Relationship:7), SELECT queries return SQLCODE 0

### File List

- src/SNOMED/Concept.cls (NEW)
- src/SNOMED/Description.cls (NEW)
- src/SNOMED/Relationship.cls (NEW)
