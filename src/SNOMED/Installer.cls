Class SNOMED.Installer Extends %RegisteredObject
{

/// Post-install setup: installs Python dependencies and registers MCP web application.
/// Called by IPM during the Configure phase after all classes are compiled.
ClassMethod Setup() As %Status
{
    Set sc = $$$OK

    // Step 1: Install Python dependencies
    Set sc = ..InstallPythonDeps()
    If $$$ISERR(sc) Return sc

    // Step 2: Grant SQL access to SNOMED tables for MCP tool execution
    Set sc = ..GrantSQLAccess()
    If $$$ISERR(sc) Return sc

    // Step 3: Register MCP web application
    Set sc = ..RegisterMCPApp()
    If $$$ISERR(sc) Return sc

    Write "SNOMED CT MCP Tools installation complete.",!
    Return $$$OK
}

ClassMethod InstallPythonDeps() As %Status [ Language = python ]
{
    import iris
    import subprocess
    import os

    candidates = [
        os.path.join(os.getcwd(), "requirements.txt"),
        "/opt/irissys/mgr/snomed-iris/requirements.txt",
        "/usr/irissys/mgr/snomed-iris/requirements.txt",
    ]

    found = None
    for path in candidates:
        if os.path.isfile(path):
            found = path
            break

    if found is None:
        print("Warning: requirements.txt not found, skipping pip install")
        return iris.cls("%SYSTEM.Status").OK()

    print(f"Installing Python dependencies from {found}...")
    result = subprocess.run(
        ["pip", "install", "-r", found, "--quiet"],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"Warning: pip install returned non-zero: {result.stderr}")
    else:
        print("Python dependencies installed successfully")

    return iris.cls("%SYSTEM.Status").OK()
}

ClassMethod GrantRoleToUser(username As %String, role As %String) [ Private ]
{
    New $Namespace
    Set $Namespace = "%SYS"
    Set sc = ##class(Security.Users).Get(username, .props)
    If $$$ISERR(sc) Quit
    Set roles = $Get(props("Roles"))
    If roles '[ role {
        Set props("Roles") = $Select(roles="":role, 1:roles_","_role)
        Set sc = ##class(Security.Users).Modify(username, .props)
        If $$$ISOK(sc) Write "Granted "_role_" to "_username,!
    }
}

ClassMethod GrantSQLAccess() As %Status
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("GRANT SELECT ON SCHEMA SNOMED TO _PUBLIC")
    If $$$ISERR(sc) {
        Write "Warning: Could not prepare GRANT statement",!
        Return $$$OK
    }
    Set rs = stmt.%Execute()
    If rs.%SQLCODE = 0 {
        Write "Granted SELECT on SNOMED schema to _PUBLIC",!
    } Else {
        Write "Warning: GRANT SQLCODE=",rs.%SQLCODE,!
    }
    Return $$$OK
}

ClassMethod RegisterMCPApp() As %Status
{
    New $Namespace
    Set $Namespace = "%SYS"

    Set props("DispatchClass") = "SNOMED.MCP.Service"
    Set props("NameSpace") = "USER"
    Set props("Description") = "SNOMED CT MCP Service"
    Set props("Enabled") = 1
    Set props("AutheEnabled") = 64
    Set props("Resource") = ""

    Set sc = ##class(Security.Applications).Create("/mcp/snomed", .props)
    If $$$ISERR(sc) {
        If ##class(Security.Applications).Exists("/mcp/snomed") {
            Write "Web application /mcp/snomed already exists, updating...",!
            Set sc = ##class(Security.Applications).Modify("/mcp/snomed", .props)
        }
    }

    If $$$ISERR(sc) {
        Write "Warning: Could not register /mcp/snomed: ",$System.Status.GetErrorText(sc),!
        Return $$$OK
    }

    Write "Registered web application /mcp/snomed",!

    // Grant %DB_USER to UnknownUser and CSPSystem so MCP access can pass AccessCheck
    Do ..GrantRoleToUser("UnknownUser", "%DB_USER")
    Do ..GrantRoleToUser("CSPSystem", "%DB_USER")

    Return $$$OK
}

}
