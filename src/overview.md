# Resharper Code Quality Analysis Task

Based on the free-to-use Resharper Command-Line Tools (CLT), this build task will automatically run over a thousand code quality checks for various languages including C# and Typescript. Add this task to your continuous build to fail the build whenever code quality standards are violated.

### Quick Setup

* Add the Resharper Code Quality Analysis task to your build template
* Set the path to your solution (.sln) or project (.csproj) file
* That's it!

**Task Configuration**
![taskconfiguration](images/taskconfiguration.png )

**Build Result**
![output](images/output.png )

### Usage

The CLT will use the default code quality inspections to generate a report with no Resharper or Visual Studio license necessary.

**Rule Configuration**

To customize the rules, it is possible to manage the team-shared options in the Inspection Severity section from the Resharper toolbar within Visual Studio. Commit the changed sln.DotSettings file and the next build will use the updated rules.

![configuration](images/configureseverity.png )

> **Tip** The build is configured by default to fail at the Warning level. Optional improvements should be set as Suggestion or Hint in the team-shared rules to prevent unnecessary build failure. Some recommendations:

| Code issue                                                       | Languages  | Default Setting | Recommended Setting |
|------------------------------------------------------------------|------------|-----------------|---------------------|
| Redundant using directive                                        | C#, ASPX   | Warning         | Suggestion          |
| Auto-property accessor is never used (non-private accessibility) | C#, VB.NET | Warning         | Suggestion          |

[Download sample sln.DotSettings file](samples/Sample.sln.DotSettings)

> **Tip** Exclude folders which contain third-party or generated code e.g. Build, Scripts, Resources within the Resharper toolbar > Options > Code Inspection > Settings section

![configuration](images/configurefolderstoskip.png )

### Configuration

The build task will download the latest Resharper CLT from NuGet and use it for code quality inspection automatically.

Alternatively, [download the CLT](https://www.jetbrains.com/resharper/download/index.html#section=resharper-clt) and copy it to the appropriate path in the repository or build controller. This increases the speed of the code inspection task and ensures the same version is used each time.

> **Note** Please ensure that the .zip file is "unblocked" before extracting. Right click on the file, select Properties and click Unblock to avoid issues running the CLT.

##### Hosted Build Controller

Copy the folder into your repository and check the downloaded files in. The default path will be Lib\Resharper and is configurable in the build task.

##### Custom Build Controller

Either check the files in as above or copy them to the build controller. The path can then be configured to an absolute path, for example C:\Tools\Resharper.

### Legal
This extension is provided as-is, without warranty of any kind, express or implied. Resharper is a registered trademark of JetBrains and the extension is produced independently of JetBrains.