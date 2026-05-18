Class SNOMED.Relationship Extends %Persistent
{

/// SNOMED CT Relationship Identifier (SCTID)
Property RelationshipId As %String(MAXLEN = 20) [ Required ];

/// Source concept (SCTID) - the subject of the relationship
Property SourceId As %String(MAXLEN = 20) [ Required ];

/// Destination concept (SCTID) - the object of the relationship
Property DestinationId As %String(MAXLEN = 20) [ Required ];

/// Relationship type (SCTID), e.g., 116680003 = IS-A
Property TypeId As %String(MAXLEN = 20) [ Required ];

/// Whether the relationship is active in the current release
Property Active As %Boolean;

/// Relationship group number for role grouping
Property RelationshipGroup As %Integer;

/// Unique lookup by relationship SCTID
Index RelationshipIdIdx On RelationshipId [ Unique ];

/// Find relationships FROM a concept
Index SourceIdIdx On SourceId;

/// Find relationships TO a concept
Index DestinationIdIdx On DestinationId;

/// Filter by relationship type (IS-A, etc.)
Index TypeIdIdx On TypeId;

}
