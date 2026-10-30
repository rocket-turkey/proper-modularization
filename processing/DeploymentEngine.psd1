@{
    RootModule = 'DeploymentEngine.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c5cf5e8e-7fb1-418d-bf6b-fa6a02591cf7'
    Author = 'Deployment experiment'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Test-Release','Install-Release','Get-ReleaseHistory','Get-ReleaseStatus','Undo-Release')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
