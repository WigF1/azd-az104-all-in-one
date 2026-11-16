# AZ-104 Azure Administrator Demo Environment

This repository contains infrastructure as code (Bicep) to deploy a comprehensive environment for Azure Administrator (AZ-104) training and demonstrations.

## Pre-deployment Steps

> **Bastion Developer SKU:** this fork deploys free Bastion Developer hosts, one in each VNet that hosts VMs (spoke1, spoke2, workload), because the Developer SKU does not support VNet peering. Both of your regions must support it — see the [region list](https://learn.microsoft.com/azure/bastion/bastion-sku-comparison). It allows one VM connection at a time and portal connections only. Set `deployBastion` to `false` if a region is unsupported.

1. **Verify VM SKU availability in your target regions**:
   This deployment uses `Standard_B2s_v2` VM SKUs by default. Check that this SKU is available in your chosen regions:
   ```bash
   az vm list-skus --resource-type virtualMachines --query "[?name=='Standard_B2s_v2'].locations[]" -o tsv
   ```
   If the SKU is not available in your target regions, you can modify the VM sizes in `infra/main.parameters.json` or choose different regions.

2. **Check App Service quota in your target regions**:
   Verify that your subscription has sufficient App Service quota for the deployment. Check that both "Total Regional VMs" and "S1 VMs" quotas are not set to 0 in your target regions.
   
   ![App Service Quota Check](demoguide/images/appservicequota.png)

3. **Configure deployment parameters** (optional):
   Before deploying, you can customize the deployment by editing `infra/main.parameters.json`. See the "Configuration" section below for details.

4. **Verify subscription access**:
   - Ensure you have Owner or Contributor access to the subscription
   - For governance components, you need User Access Administrator to create custom roles

## Deployment Instructions

## 1. Installation 
- You need [Azure Developer CLI - AZD](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd), in case that's your first azd deployment go ahead and install it.
    - When installing AZD, the following tools will be installed on your machine as well, if not already installed:
        - [GitHub CLI](https://cli.github.com)
        - [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

## 2. Deploying the scenario in 3 steps: 

1. Create a new folder on your machine and navigate to it.
```
mkdir -p sqltattoo/azd-az104-all-in-one && cd sqltattoo/azd-az104-all-in-one 
```
2. Next, run `azd init` to initialize the deployment.
```
azd init -t sqltattoo/azd-az104-all-in-one
```
3. Last, run `azd up` to trigger an actual deployment.
```
azd up
```

**During `azd up` you will be prompted for:**

| Prompt | Purpose | Example |
|--------|---------|--------|
| `hubLocation` | Primary region — used for hub, spoke1, and workload VNets | `uksouth` |
| `spoke2Location` | Cross-region spoke — **must be different from hub** to demonstrate multi-region routing | `northeurope` |
| `adminPassword` | VM administrator password | *(secure input)* |

> The separate `spoke2Location` prompt is intentional — deploying spoke2 in a different region is a core AZ-104 demo scenario (cross-region VNet peering, latency-based routing).

**Optional:** If you need to force a fresh redeployment ignoring stored state, or explicitly pass the parameter file:
```bash
azd provision --no-state  # Force fresh deployment ignoring stored deployment state (Bicep only)

# Or explicitly reference the parameter file:
azd deploy --parameters @infra/main.parameters.json
```
## Demo Features
Check the **[demo guide](https://github.com/SQLtattoo/azd-az104-all-in-one/blob/master/demoguide/demoguide.md)** for details on the demo scenario.

## Cleanup

### Tearing Down the Environment

To remove all deployed resources:

```bash
# Standard cleanup (prompts for confirmation)
azd down

# Skip confirmation prompts
azd down --force

# Also purge soft-deleted resources (Key Vault, etc.)
azd down --purge --force
```

**Note:** `azd down` runs a postdown hook (PowerShell 7 / `pwsh` required) that removes the resources living outside the resource group: the Connection Monitor in `NetworkWatcherRG`, the custom RBAC role and the policy initiative definition. Policy assignments you create by hand during a demo are not removed.

Key Vault purge protection is **off by default**, so `azd down --purge` fully removes the vault and you can redeploy with the same environment name straight away. If you enable purge protection (or CMK), the vault name stays reserved for 7 days after deletion.

### Manual Cleanup (if needed)

If the hook could not run, re-run it (it reads `AZURE_LOCATION` and `AZURE_RESOURCE_GROUP` from the azd environment):

```bash
azd hooks run postdown
```

## Configuration

**Updated: November 17, 2025**

### Parameter File Approach

All deployment configuration is managed through the Bicep parameters file `infra/main.parameters.json`. This provides predictable, consistent behavior across all deployments.

**Why we moved from `azure.yaml` to a parameter file:**
- The `infra.parameters` section in `azure.yaml` did not reliably control runtime deployments
- Changes to feature toggles (like `deployBastion`, `deployVpnGateway`) and VM sizes were not consistently applied
- A standard ARM/Bicep parameter file ensures Azure Resource Manager processes parameters correctly every time

### Customizing Your Deployment

Edit `infra/main.parameters.json` before running `azd up`. Key parameters you can customize:

**Locations:**

`hubLocation`, `spoke1Location`, and `workloadLocation` are bound to `AZURE_LOCATION` (the primary region you choose during `azd up`). `spoke2Location` is prompted separately — set it to a **different region** to demonstrate cross-region routing scenarios.

**Feature Toggles:**
```json
"deployBastion": { "value": false },      // Set to false to skip the Bastion Developer hosts (free; check region support)
"deployVpnGateway": { "value": false },   // Set to false to skip VPN Gateway
"deployKeyVault": { "value": true },      // Enable/disable Key Vault demos
"deployGovernance": { "value": true },    // Custom RBAC role + policy initiative definitions (needs Owner/User Access Administrator)
"enableKeyVaultPurgeProtection": { "value": false } // Off so azd down --purge works; enable it live in the Key Vault demo
```

**Alert email:** monitoring alerts go to the address in the `AZURE_ALERT_EMAIL` azd environment value. Set it once per environment before `azd up`:
```bash
azd env set AZURE_ALERT_EMAIL you@example.com
```
If it isn't set, alerts go to the placeholder `trainer@contoso.com`.

**VM Size Configuration:**

Control VM sizes for cost optimization or quota constraints:

```json
"defaultVmSize": { "value": "Standard_B2s_v2" },        // Default for all tiers
"webTierVmSize": { "value": "" },                   // Empty = use default
"appTierVmSize": { "value": "Standard_B2s_v2" },      // Override for app tier only
"workloadTierVmSize": { "value": "" },              // Empty = use default
"vmssVmSize": { "value": "Standard_B2s_v2" }           // VMSS instance size
```

**Example: Low-quota environment**
```json
"defaultVmSize": { "value": "Standard_B1s" },
"deployBastion": { "value": false },
"deployVpnGateway": { "value": false }
```

**Naming and DNS:**
```json
"publicDnsZoneBase": { "value": "contoso.com" },
"privateDnsZoneBase": { "value": "contoso.local" },
"vaultName": { "value": "contoso-rsv" },
"storageAccountPrefix": { "value": "staz104" },
"adminObjectId": { "value": "${AZURE_PRINCIPAL_ID}" }  // Set automatically by azd: the signed-in user gets Key Vault Administrator
```

After editing the parameter file, run:
```bash
azd up
```

**Note:** `adminUsername` and `adminPassword` are handled interactively by `azd` during deployment and should not be added to the parameter file.

## Cleanup for Previous Deployments

**Important Note (Updated: October 17, 2025)**

If you deployed this solution **before October 17, 2025**, you may encounter deployment errors when redeploying to a different Azure region. This is due to a static subscription-scoped governance deployment that was location-bound.

### Symptoms
You'll see an error like:
```
InvalidDeploymentLocation: The deployment 'governance-components' already exists in location 'uksouth'.
```

### Solution
Before running `azd up` in a new region, delete the old subscription-scoped deployment:

```bash
# Delete the static governance deployment (one-time cleanup)
az deployment sub delete --name governance-components

# Optional: List and clean up custom roles if starting fresh
az role definition list --custom-role-only true --query "[?contains(roleName, 'AZ104')]"

# Optional: List policy assignments for review
az policy assignment list --query "[?contains(displayName, 'AZ104')]"
```

After cleanup, proceed with normal deployment:
```bash
azd up
```

**What changed:** The governance deployment now uses a dynamic name based on your hub location (e.g., `governance-westeurope`), allowing multi-region deployments without conflicts.

## Troubleshooting

- Key Vault deployment fails: you need permission to create role assignments (Owner or User Access Administrator) because the deployer is granted Key Vault Administrator
- Governance deployment fails with an authorization error: set `deployGovernance` to `false`, or get Owner/User Access Administrator on the subscription
- Custom RBAC role not visible: It may take a few minutes for the role to appear in the Azure Portal
- Monitoring agent failures: Ensure VMs are fully provisioned before deploying monitoring
- Location conflicts: See the "Cleanup for Previous Deployments" section above
