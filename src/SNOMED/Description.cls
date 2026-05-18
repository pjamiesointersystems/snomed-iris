Class SNOMED.Description Extends %Persistent
{

/// SNOMED CT Description Identifier (SCTID)
Property DescriptionId As %String(MAXLEN = 20) [ Required ];

/// Concept this description belongs to (SCTID)
Property ConceptId As %String(MAXLEN = 20) [ Required ];

/// Human-readable term text
Property Term As %String(MAXLEN = 1024) [ Required ];

/// Description type: FSN, Synonym, or Definition (SCTID)
Property TypeId As %String(MAXLEN = 20);

/// Whether the description is active in the current release
Property Active As %Boolean;

/// ISO language code (e.g., "en")
Property LanguageCode As %String(MAXLEN = 5);

/// Unique lookup by description SCTID
Index DescriptionIdIdx On DescriptionId [ Unique ];

/// Join to Concept table
Index ConceptIdIdx On ConceptId;

/// Filter by description type (FSN/Synonym/Definition)
Index TypeIdIdx On TypeId;

/// Full-text search index on Term for lexical queries
Index TermIdx On (Term) As %iFind.Index.Basic;

}
