Class SNOMED.Hierarchy Extends %RegisteredObject
{

/// Check if conceptId is a descendant of ancestorId. O(1) via global lookup.
ClassMethod IsDescendantOf(conceptId As %String, ancestorId As %String) As %Boolean
{
    Quit $DATA(^SNOMED.TC(ancestorId, conceptId))#2
}

/// Get all ancestor concept IDs for a given concept. Returns JSON array.
ClassMethod GetAncestors(conceptId As %String) As %String
{
    Set results = []
    Set ancestor = ""
    For {
        Set ancestor = $ORDER(^SNOMED.TC(ancestor))
        Quit:ancestor=""
        If $DATA(^SNOMED.TC(ancestor, conceptId))#2 {
            Do results.%Push(ancestor)
        }
    }
    Return results.%ToJSON()
}

/// Get all descendant concept IDs for a given concept. Returns JSON array.
ClassMethod GetDescendants(conceptId As %String) As %String
{
    Set results = []
    Set desc = ""
    For {
        Set desc = $ORDER(^SNOMED.TC(conceptId, desc))
        Quit:desc=""
        Do results.%Push(desc)
    }
    Return results.%ToJSON()
}

/// Get direct children of a concept. Returns JSON array.
ClassMethod GetChildren(conceptId As %String) As %String
{
    Set results = []
    Set child = ""
    For {
        Set child = $ORDER(^SNOMED.Children(conceptId, child))
        Quit:child=""
        Do results.%Push(child)
    }
    Return results.%ToJSON()
}

/// Get direct parents of a concept. Returns JSON array.
ClassMethod GetParents(conceptId As %String) As %String
{
    Set results = []
    Set parent = ""
    For {
        Set parent = $ORDER(^SNOMED.Children(parent))
        Quit:parent=""
        If $DATA(^SNOMED.Children(parent, conceptId))#2 {
            Do results.%Push(parent)
        }
    }
    Return results.%ToJSON()
}

}
