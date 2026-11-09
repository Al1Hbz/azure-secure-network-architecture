# Secure Azure Lab: Network Architecture & Bicep Deployment

A clean and secure Azure VNet setup built with Bicep. This project isolates public web traffic from management and internal storage.

> 💡 **Note:** You can easily customize variables (such as `location`, naming prefixes, VM sizes, etc.) based on your own environment and requirements.

## What's inside?
* **Public Traffic:** Internet -> Application Gateway -> Azure Firewall -> Backend VM.
* **Admin Management:** Direct and secure RDP access using **Azure Bastion** (no public IP on the VM, completely bypassing the firewall).
* **Storage Security:** The VM talks to the Storage Account safely via a **Private Endpoint**.

## Components
- `VNet-Prod-01` (`10.0.0.0/16`)
- Subnets: Firewall, Bastion, Workload, Private Endpoint
- Core Services: Azure Firewall, Bastion, VM, Private Link

## Deployment
To deploy this architecture via Azure CLI / PowerShell, run:

```powershell
$adminUsername = "username"
$securePassword = Read-Host -Prompt "Enter Windows VM Password" -AsSecureString

New-AzResourceGroup -Name "rg-lab-01" -Location "northcentralus"

New-AzResourceGroupDeployment `
  -ResourceGroupName "rg-lab-01" `
  -TemplateFile ".\Main.bicep" `
  -Location "northcentralus" `
  -adminUsername $adminUsername `
  -adminPassword $securePassword
