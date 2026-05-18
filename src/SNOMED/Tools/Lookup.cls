Class SNOMED.Tools.Lookup Extends %AI.Tool
{

/// Look up a SNOMED CT concept by its identifier (SCTID).
/// Returns concept details including the Fully Specified Name (FSN), active status, and all active descriptions.
ClassMethod GetConcept(sctid As %String) As %String
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("SELECT ConceptId, Active, DefinitionStatusId FROM SNOMED.Concept WHERE ConceptId = ?")
    If $$$ISERR(sc) {
        Set err = {}
        Set err.error = "Prepare failed"
        Return err.%ToJSON()
    }
    Set rs = stmt.%Execute(sctid)
    If 'rs.%Next() {
        Set err = {}
        Set err.error = "Concept not found"
        Set err.sctid = sctid
        Return err.%ToJSON()
    }

    Set result = {}
    Set result.ConceptId = rs.ConceptId
    Set result.Active = rs.Active
    Set result.DefinitionStatusId = rs.DefinitionStatusId

    // Get active descriptions
    Set descStmt = ##class(%SQL.Statement).%New()
    Set sc = descStmt.%Prepare("SELECT Term, TypeId, Active FROM SNOMED.Description WHERE ConceptId = ? AND Active = 1 ORDER BY TypeId, Term")
    Set descRs = descStmt.%Execute(sctid)
    Set descriptions = []
    Set fsn = ""
    While descRs.%Next() {
        Set desc = {}
        Set desc.Term = descRs.Term
        Set desc.TypeId = descRs.TypeId
        Do descriptions.%Push(desc)
        If descRs.TypeId = "900000000000003001" Set fsn = descRs.Term
    }
    Set result.FSN = fsn
    Set result.Descriptions = descriptions
    Return result.%ToJSON()
}

}
