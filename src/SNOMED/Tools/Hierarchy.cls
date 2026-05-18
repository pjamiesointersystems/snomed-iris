Class SNOMED.Tools.Hierarchy Extends %AI.Tool
{

/// Check if a SNOMED concept is a descendant of (is-a) another concept.
/// Returns whether the subsumption relationship exists.
ClassMethod IsA(conceptId As %String, ancestorId As %String) As %String
{
    Set result = {}
    Set result.isDescendant = ##class(SNOMED.Hierarchy).IsDescendantOf(conceptId, ancestorId)
    Set result.conceptId = conceptId
    Set result.ancestorId = ancestorId
    Return result.%ToJSON()
}

/// Get all ancestor concepts for a given SNOMED concept.
/// Returns ancestors with their Fully Specified Names.
ClassMethod GetAncestors(conceptId As %String) As %String
{
    Set jsonStr = ##class(SNOMED.Hierarchy).GetAncestors(conceptId)
    Set ids = ##class(%DynamicArray).%FromJSON(jsonStr)
    Set results = []
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")
    Set iter = ids.%GetIterator()
    While iter.%GetNext(.key, .id) {
        Set rs = stmt.%Execute(id)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = id
        Set obj.FSN = term
        Do results.%Push(obj)
    }
    Return results.%ToJSON()
}

/// Get descendant concepts for a given SNOMED concept.
/// Limited to maxResults (default 100) to avoid overwhelming output.
ClassMethod GetDescendants(conceptId As %String, maxResults As %Integer = 100) As %String
{
    Set results = []
    Set count = 0
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")
    Set desc = ""
    For {
        Set desc = $ORDER(^SNOMED.TC(conceptId, desc))
        Quit:desc=""
        Quit:count>=maxResults
        Set rs = stmt.%Execute(desc)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = desc
        Set obj.FSN = term
        Do results.%Push(obj)
        Set count = count + 1
    }
    Return results.%ToJSON()
}

/// Get direct children of a SNOMED concept with their Fully Specified Names.
ClassMethod GetChildren(conceptId As %String) As %String
{
    Set jsonStr = ##class(SNOMED.Hierarchy).GetChildren(conceptId)
    Set ids = ##class(%DynamicArray).%FromJSON(jsonStr)
    Set results = []
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")
    Set iter = ids.%GetIterator()
    While iter.%GetNext(.key, .id) {
        Set rs = stmt.%Execute(id)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = id
        Set obj.FSN = term
        Do results.%Push(obj)
    }
    Return results.%ToJSON()
}

/// Get direct parents of a SNOMED concept with their Fully Specified Names.
ClassMethod GetParents(conceptId As %String) As %String
{
    Set jsonStr = ##class(SNOMED.Hierarchy).GetParents(conceptId)
    Set ids = ##class(%DynamicArray).%FromJSON(jsonStr)
    Set results = []
    Set stmt = ##class(%SQL.Statement).%New()
    Do stmt.%Prepare("SELECT Term FROM SNOMED.Description WHERE ConceptId = ? AND TypeId = '900000000000003001' AND Active = 1")
    Set iter = ids.%GetIterator()
    While iter.%GetNext(.key, .id) {
        Set rs = stmt.%Execute(id)
        Set term = ""
        If rs.%Next() Set term = rs.Term
        Set obj = {}
        Set obj.ConceptId = id
        Set obj.FSN = term
        Do results.%Push(obj)
    }
    Return results.%ToJSON()
}

}
