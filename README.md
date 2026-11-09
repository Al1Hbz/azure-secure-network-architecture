# Secure Azure Lab: Network Architecture & Bicep Deployment

A clean and secure Azure VNet setup built with Bicep. This project isolates public web traffic from management and internal storage.

##  What's inside?
* **Public Traffic:** Internet $\rightarrow$ Application Gateway $\rightarrow$ Azure Firewall $\rightarrow$ Backend VM.
* **Admin Management:** Direct and secure RDP access using **Azure Bastion** (no public IP on the VM, completely bypassing the firewall).
* **Storage Security:** The VM talks to the Storage Account safely via a **Private Endpoint**.

##  Components
- `VNet-Prod-01` (`10.0.0.0/16`)
- Subnets: Firewall, Bastion, Workload, Private Endpoint
- Core Services: Azure Firewall, Bastion, VM, Private Link
