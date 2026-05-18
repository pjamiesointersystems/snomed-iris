Class SNOMED.Loader Extends %RegisteredObject
{

/// Load SNOMED CT concepts from an RF2 Snapshot file into SNOMED.Concept table.
/// filepath: absolute path to sct2_Concept_Snapshot_*.txt
/// Returns $$$OK on success, error status on failure.
ClassMethod LoadConcepts(filepath As %String) As %Status [ Language = python ]
{
    import iris
    import os
    import csv

    if not os.path.isfile(filepath):
        return iris.cls("%SYSTEM.Status").Error(5001, f"File not found: {filepath}")

    sql = iris.sql.prepare(
        "INSERT INTO SNOMED.Concept (ConceptId, Active, EffectiveTime, ModuleId, DefinitionStatusId) "
        "VALUES (?, ?, ?, ?, ?)"
    )

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        count = 0
        for row in reader:
            sql.execute(row['id'], int(row['active']), row['effectiveTime'],
                       row['moduleId'], row['definitionStatusId'])
            count += 1
            if count % 50000 == 0:
                print(f"  Loaded {count} concepts...")

    print(f"Total: {count} concepts loaded")
    return iris.cls("%SYSTEM.Status").OK()
}

/// Load SNOMED CT descriptions from an RF2 Snapshot file into SNOMED.Description table.
/// filepath: absolute path to sct2_Description_Snapshot_*.txt
/// Returns $$$OK on success, error status on failure.
ClassMethod LoadDescriptions(filepath As %String) As %Status [ Language = python ]
{
    import iris
    import os
    import csv
    import sys

    csv.field_size_limit(sys.maxsize)

    if not os.path.isfile(filepath):
        return iris.cls("%SYSTEM.Status").Error(5001, f"File not found: {filepath}")

    sql = iris.sql.prepare(
        "INSERT INTO SNOMED.Description (DescriptionId, ConceptId, Term, TypeId, Active, LanguageCode) "
        "VALUES (?, ?, ?, ?, ?, ?)"
    )

    skipped = 0
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        count = 0
        for row in reader:
            try:
                term = row.get('term', '')
                if not term or not row.get('id'):
                    skipped += 1
                    continue
                sql.execute(row['id'], row['conceptId'], term,
                           row['typeId'], int(row['active']), row['languageCode'])
                count += 1
            except Exception as e:
                skipped += 1
                if skipped <= 5:
                    print(f"  Warning: skipped row {count + skipped}: {e}")
            if count % 50000 == 0 and count > 0:
                print(f"  Loaded {count} descriptions...")

    print(f"Total: {count} descriptions loaded ({skipped} skipped)")
    return iris.cls("%SYSTEM.Status").OK()
}

/// Load SNOMED CT relationships from an RF2 Snapshot file into SNOMED.Relationship table.
/// filepath: absolute path to sct2_Relationship_Snapshot_*.txt
/// Returns $$$OK on success, error status on failure.
ClassMethod LoadRelationships(filepath As %String) As %Status [ Language = python ]
{
    import iris
    import os
    import csv

    if not os.path.isfile(filepath):
        return iris.cls("%SYSTEM.Status").Error(5001, f"File not found: {filepath}")

    sql = iris.sql.prepare(
        "INSERT INTO SNOMED.Relationship (RelationshipId, SourceId, DestinationId, TypeId, Active, RelationshipGroup) "
        "VALUES (?, ?, ?, ?, ?, ?)"
    )

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        count = 0
        isa_count = 0
        for row in reader:
            active = int(row['active'])
            type_id = row['typeId']
            sql.execute(row['id'], row['sourceId'], row['destinationId'],
                       type_id, active, int(row['relationshipGroup']))
            count += 1
            if active == 1 and type_id == "116680003":
                isa_count += 1
            if count % 50000 == 0:
                print(f"  Loaded {count} relationships...")

    print(f"Total: {count} relationships loaded ({isa_count} active IS-A)")
    return iris.cls("%SYSTEM.Status").OK()
}

/// Truncate all SNOMED tables for re-loading.
/// Returns $$$OK on success.
ClassMethod TruncateAll() As %Status [ Language = python ]
{
    import iris

    iris.sql.exec("TRUNCATE TABLE SNOMED.Concept")
    iris.sql.exec("TRUNCATE TABLE SNOMED.Description")
    iris.sql.exec("TRUNCATE TABLE SNOMED.Relationship")
    print("Truncated SNOMED.Concept, SNOMED.Description, and SNOMED.Relationship")
    return iris.cls("%SYSTEM.Status").OK()
}

}
