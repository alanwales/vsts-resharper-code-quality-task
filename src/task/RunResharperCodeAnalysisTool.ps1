param
(
    [string] $solutionOrProjectPath=$(throw "solutionOrProjectPath is mandatory, please provide a value."),
    [string] $commandLineInterfacePath,
    [string] $failBuildLevelSelector="Warning",
    [bool] $failBuildOnCodeIssues=$true,
    [string] $additionalArguments="",
    [string] $buildId="Unlabeled_Build",
    [string] $inspectCodeResultsPathOverride,
    [string] $resharperNugetVersion="Latest"
)

function Set-Results {
    param(
        [string]
        $summaryMessage,
        [ValidateSet("Succeeded", "Failed")]
        [string]
        $buildResult
    )
    Write-Output ("##vso[task.complete result={0}};]{1}" -f $buildResult, $summaryMessage)
    Add-Content $summaryFilePath ($summaryMessage)
}

# Gather inputs

$inspectCodeExePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($commandLineInterfacePath, "InspectCode.exe"));
$tempDownloadFolder = $Env:BUILD_STAGINGDIRECTORY

if(!(Test-Path $inspectCodeExePath)) {
    # Download Resharper from nuget
    $useSpecificNuGetVersion = $resharperNugetVersion -and $resharperNugetVersion -ne "Latest"

    $downloadMessage = "No pre-installed Resharper CLT was found"
    if($useSpecificNuGetVersion){
        $downloadMessage += ", downloading version $resharperNugetVersion from nuget.org..."
    } else {
        $downloadMessage += ", downloading the latest from nuget.org..."
    }

    Write-Output $downloadMessage

    $nugetExeLocation = [System.IO.Path]::Combine($PSScriptRoot, ".nuget")

    Copy-Item $nugetExeLocation\* $tempDownloadFolder

    $nugetExeLocation = [System.IO.Path]::Combine($tempDownloadFolder, "nuget.exe")

    $nugetArguments = "install JetBrains.ReSharper.CommandLineTools"
    if($useSpecificNuGetVersion){
        $nugetArguments += " -Version $resharperNugetVersion"
    }

    Start-Process -FilePath "$nugetExeLocation" -ArgumentList $nugetArguments -WorkingDirectory $tempDownloadFolder -Wait

    $resharperPreInstalledDirectoryPath = [System.IO.Directory]::EnumerateDirectories($tempDownloadFolder, "*JetBrains*")[0]
    if(!(Test-Path $resharperPreInstalledDirectoryPath)) {
        Throw [System.IO.FileNotFoundException] "InspectCode.exe was not found at $inspectCodeExePath or $resharperPreInstalledDirectoryPath"
    }

    Write-Output "Resharper CLT downloaded"

    $commandLineInterfacePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($resharperPreInstalledDirectoryPath, "tools"));
    $inspectCodeExePath =  [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($commandLineInterfacePath, "InspectCode.exe"));
}

if(!(Test-Path $inspectCodeExePath)) {
    Throw [System.IO.FileNotFoundException] "InspectCode.exe was not found at $inspectCodeExePath"
}

[string] $solutionOrProjectFullPath = [System.IO.Path]::GetFullPath($solutionOrProjectPath);

if(!(Test-Path $solutionOrProjectFullPath)) {
    Throw [System.IO.FileNotFoundException] "No solution or project found at $solutionOrProjectFullPath"
}

[string] $inspectCodeResultsPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($commandLineInterfacePath, "Reports\CodeInspection_$buildId.xml"));
if($inspectCodeResultsPathOverride){
    if(!$inspectCodeResultsPathOverride.EndsWith(".xml")) {
        $inspectCodeResultsPathOverride += ".xml"
    }
    $inspectCodeResultsPath = $inspectCodeResultsPathOverride
}

$severityLevels = @{"Hint" = 0; "Suggestion" = 1; "Warning" = 2; "Error" = 3}

Write-Verbose "Using Resharper Code Analysis found at '$inspectCodeExePath'"

Write-Output "Inspecting code for $solutionOrProjectPath"

# Run code analysis

$arguments = """$solutionOrProjectFullPath"" /o:""$inspectCodeResultsPath"" $additionalArguments"

Write-Output "Invoking InspectCode.exe using arguments $arguments" 

Start-Process -FilePath $inspectCodeExePath -ArgumentList $arguments -Wait

# Analyse results

$xmlContent = [xml] (Get-Content "$inspectCodeResultsPath")
$issuesTypesXpath = "/Report/IssueTypes//IssueType"
$issuesTypesElements = $xmlContent | Select-Xml $issuesTypesXpath | Select -Expand Node

$issuesXpath = "/Report/Issues//Issue"
$issuesElements = $xmlContent | Select-Xml $issuesXpath | Select -Expand Node

$filteredElements = New-Object System.Collections.Generic.List[System.Object]

foreach($issue in $issuesElements) {
    $severity = @($issuesTypesElements | Where-Object {$_.Attributes["Id"].Value -eq $issue.Attributes["TypeId"].Value})[0].Attributes["Severity"].Value

    $severityLevel = $severityLevels[$severity]

    if($severityLevel -ge $severityLevels[$failBuildLevelSelector]) {
        $item = New-Object -TypeName PSObject -Property @{
            'Severity' = $severity
            'Message' = $issue.Attributes["Message"].Value
            'File' = $issue.Attributes["File"].Value
            'Line' = $issue.Attributes["Line"].Value
        }

        $filteredElements.Add($item)
    }
}

# Report results output

foreach ($issue in $filteredElements | Sort-Object Severity -Descending) {
    $errorType = "warning"
    if($issue.Severity -eq "Error"){
        $errorType = "error"
    }
    Write-Output ("##vso[task.logissue type={0};sourcepath={1};linenumber={2};columnnumber=1]R# {3}" -f $errorType, $issue.File, $issue.Line, $issue.Message)
}

$taskCommonTools = "Microsoft.TeamFoundation.DistributedTask.Task.Common"
if (Get-Module -ListAvailable -Name $taskCommonTools) {
    Write-Output "Preparing to add summary to build results"
} else {
    Throw [System.IO.FileNotFoundException] "Module $taskCommonTools is not installed. If using a custom build controller ensure that this library is correctly installed and available for use in PowerShell."
}

import-module $taskCommonTools
$summaryFilePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($tempDownloadFolder, "Summary.md"));
New-Item $summaryFilePath -type file -force

$summaryMessage = ""

if ($failBuildOnCodeIssues) {
    if($filteredElements.Count -eq 0) {
        Set-Results -summaryMessage "No code quality issues found" -buildResult "Succeeded"
    } elseif($filteredElements.Count -eq 1) {
        Set-Results -summaryMessage "One code quality issue found" -buildResult "Failed"
    } else {
        $summaryMessage = "{0} code quality issues found" -f $filteredElements.Count
        Set-Results -summaryMessage $summaryMessage -buildResult "Failed"
    }
} else {
    $summaryMessage = "{0} code quality issues found" -f $filteredElements.Count
    Set-Results -summaryMessage $summaryMessage -buildResult "Succeeded"
}

Write-Output "##vso[task.addattachment type=Distributedtask.Core.Summary;name=Code Quality Analysis;]$summaryFilePath"

If (Test-Path $inspectCodeResultsPath) {
 If (!$inspectCodeResultsPathOverride) {
    Remove-Item $inspectCodeResultsPath
 }
}
