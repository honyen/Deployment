# DeploymentNetCore

`azure-pipelines.yml` builds the project on pushes to `main`.
`azure-pipelines-deploy.yml` is a separate, manually run build and IIS deployment
pipeline. Deployment runs only for the `main` branch. It publishes a
framework-dependent Windows x64 application and executes PowerShell locally on
the selected VM's Azure DevOps Environment agent.

## Prepare the Azure Windows VM

1. Install IIS and its management scripting tools from an elevated Windows
   PowerShell prompt:
   ```powershell
   Install-WindowsFeature Web-Server, Web-Scripting-Tools -IncludeManagementTools
   ```
2. Install the x64 [.NET 10 Hosting Bundle](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
   **after IIS**, then restart the VM. The bundle supplies both the ASP.NET Core
   runtime and `AspNetCoreModuleV2`; installing just the SDK is insufficient.
3. In Azure DevOps, create a **Pipelines > Environments** environment, add a
   **Virtual machines > Windows** resource, and run the generated registration
   script on the VM in elevated Windows PowerShell. Configure the agent as a
   service with an account permitted to manage IIS, set filesystem ACLs, and
   write to the deployment root. Record the Environment and resource names.
   See [Microsoft's VM registration instructions](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments-virtual-machines?view=azure-devops).
4. For access outside the VM, allow the site's port in the Azure NSG and Windows
   Firewall. The agent requires outbound HTTPS access to Azure DevOps and its
   artifact storage. Configure an IIS HTTPS binding and certificate if needed;
   the pipeline creates an HTTP binding for a new site on port 8080 by default.

## Create and run the deployment pipeline

1. Create a new Azure Pipeline using **Existing Azure Pipelines YAML file** and
   select `azure-pipelines-deploy.yml`.
2. Authorize that pipeline to use the Environment and its agent pool.
3. Select **Run pipeline**, choose `main`, and supply `environmentName` and
   `vmResourceName`. These are Azure DevOps names, not the Azure resource group
   or necessarily the Azure VM resource name.
4. Review `siteName`, `deploymentRoot`, `httpPort`, and `healthCheckUrl`.
   Defaults create `DeploymentNetCore`, its dedicated
   `DeploymentNetCore-AppPool`, and `http://localhost:8080/HealthCheck`.
   An existing site must use `<siteName>-AppPool`; existing bindings are preserved,
   so set the health URL to match them, including HTTPS/hostname if applicable.
   Use a dedicated pool with no other applications because deployment recycles it.

No Azure subscription service connection, VM password, WinRM listener, or Web
Deploy installation is needed: the Environment agent performs the deployment
on the VM. Keep application secrets in server configuration rather than this YAML.

Each deployment copies the artifact into a unique folder under
`<deploymentRoot>\releases`, grants the app pool read/execute access, switches
the site's physical path, and checks `/HealthCheck`. A failed check restores the
previous physical path and recycles the pool; on the first deployment it stops
the failed site. Releases are retained for recovery and need periodic cleanup
after confirming they are no longer in use. A pool recycle can briefly interrupt
requests; this is not a zero-downtime rollout.

The pipeline and deployment script require Azure DevOps Services pipeline
artifacts and Windows PowerShell 5.1 on the VM. IIS and Hosting Bundle installation
are prerequisites, not changes performed by the pipeline.
