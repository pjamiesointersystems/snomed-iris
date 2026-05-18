Class SNOMED.ToolSet Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="SNOMEDTools">
    <Description>SNOMED CT terminology operations - concept lookup, lexical search, and hierarchy navigation</Description>
    <Include Class="SNOMED.Tools.Lookup"/>
    <Include Class="SNOMED.Tools.Search"/>
    <Include Class="SNOMED.Tools.Hierarchy"/>
    <Include Class="SNOMED.Tools.Semantic"/>
</ToolSet>
}

}
