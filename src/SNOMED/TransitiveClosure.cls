Class SNOMED.TransitiveClosure Extends %RegisteredObject
{

/// Compute transitive closure of IS-A hierarchy.
/// Populates ^SNOMED.TC(ancestorId, descendantId) and ^SNOMED.Children(parentId, childId).
ClassMethod Compute() As %Status [ Language = python ]
{
    import iris
    from collections import deque

    # Load active IS-A edges
    stmt = iris.sql.prepare(
        "SELECT SourceId, DestinationId FROM SNOMED.Relationship "
        "WHERE TypeId = '116680003' AND Active = 1"
    )
    rs = stmt.execute()

    parents_of = {}  # child -> [parent1, parent2, ...]
    tc_global = iris.gref("^SNOMED.TC")
    children_global = iris.gref("^SNOMED.Children")

    for row in rs:
        child = row[0]
        parent = row[1]
        parents_of.setdefault(child, []).append(parent)
        # Direct parent-child
        children_global[parent, child] = ""

    concepts = list(parents_of.keys())
    total = len(concepts)
    print(f"Computing transitive closure for {total} concepts...")

    for i, concept_id in enumerate(concepts):
        # BFS upward
        visited = {concept_id}
        queue = deque([concept_id])
        while queue:
            node = queue.popleft()
            for parent in parents_of.get(node, []):
                if parent not in visited:
                    visited.add(parent)
                    tc_global[parent, concept_id] = ""
                    queue.append(parent)

        if (i + 1) % 10000 == 0:
            print(f"  Processed {i+1}/{total} concepts...")

    print(f"Transitive closure complete: {total} concepts processed")
    return iris.cls("%SYSTEM.Status").OK()
}

/// Clear transitive closure and children globals for re-computation.
ClassMethod Clear() As %Status [ Language = python ]
{
    import iris
    tc_global = iris.gref("^SNOMED.TC")
    children_global = iris.gref("^SNOMED.Children")
    tc_global.kill([])
    children_global.kill([])
    print("Cleared ^SNOMED.TC and ^SNOMED.Children globals")
    return iris.cls("%SYSTEM.Status").OK()
}

}
