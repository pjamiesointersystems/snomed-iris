Class SNOMED.Concept Extends %Persistent
{

/// SNOMED CT Concept Identifier (SCTID)
Property ConceptId As %String(MAXLEN = 20) [ Required ];

/// Whether the concept is active in the current release
Property Active As %Boolean;

/// RF2 effective time in YYYYMMDD format
Property EffectiveTime As %String(MAXLEN = 8);

/// Module that owns this concept (SCTID)
Property ModuleId As %String(MAXLEN = 20);

/// Primitive or fully defined (SCTID)
Property DefinitionStatusId As %String(MAXLEN = 20);

/// Unique lookup by SCTID
Index ConceptIdIdx On ConceptId [ Unique ];

/// Fast filtering of active/inactive concepts
Index ActiveIdx On Active [ Type = bitmap ];

}
