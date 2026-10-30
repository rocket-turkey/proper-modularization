@{
    RootModule = 'DeploymentEngine.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'bdc39916-346b-46b6-a25c-646478df09e2'
    Author = 'Deployment experiment'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Test-Release','Install-Release','Get-ReleaseHistory','Get-ReleaseStatus','Undo-Release')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
