Class SNOMED.ConceptEmbedding Extends %Persistent
{

/// SNOMED CT Concept Identifier (SCTID)
Property ConceptId As %String(MAXLEN = 20) [ Required ];

/// The description term that was embedded
Property Term As %String(MAXLEN = 1024);

/// Vector embedding of the term (384 dimensions for MiniLM-compatible models)
Property Embedding As %Library.Vector(DATATYPE = "DOUBLE", LEN = 384);

/// Unique lookup by concept ID
Index ConceptIdIdx On ConceptId [ Unique ];

/// ANN index for fast approximate nearest neighbor search (HNSW)
Index EmbeddingIdx On (Embedding) As %SQL.Index.HNSW;

}
