Class SNOMED.Tools.Search Extends %AI.Tool
{

/// Search SNOMED CT concepts by keyword or phrase using full-text lexical search.
/// Returns matching active concepts with ConceptId, Term, and TypeId.
ClassMethod LexicalSearch(term As %String, maxResults As %Integer = 20) As %String
{
    Return ##class(SNOMED.Search).Lexical(term, maxResults)
}

/// SQL query for pattern-based search using LIKE wildcards.
/// Use % for any characters, _ for single character.
Query SearchByPattern(pattern As %String, maxResults As %Integer = 50) As %SQLQuery [ SqlProc ]
{
    SELECT TOP :maxResults d.ConceptId, d.Term, d.TypeId
    FROM SNOMED.Description d
    JOIN SNOMED.Concept c ON c.ConceptId = d.ConceptId
    WHERE d.Term LIKE :pattern
    AND d.Active = 1 AND c.Active = 1
    ORDER BY d.Term
}

}
