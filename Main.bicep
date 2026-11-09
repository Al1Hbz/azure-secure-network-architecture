
@description('Azure region for all regional resources.')
param location string = 'northcentralus'

@description('Windows VM local administrator username. Supplied at deployment time.')
param adminUsername string

@secure()
@description('Windows VM local administrator password. Supplied securely at deployment time.')
param adminPassword string

var prefix = 'lab'
var vnetName = 'vnet-${prefix}-01'
var workloadSubnetName = 'subnet-workload'
var bastionSubnetName = 'AzureBastionSubnet'
var firewallSubnetName = 'AzureFirewallSubnet'
var vmName = 'vm-app-01'
var nicName = 'nic-${vmName}'
var bastionName = 'bastion-${prefix}-01'
var firewallName = 'fw-${prefix}-01'
var storageAccountName = 'stg${uniqueString(resourceGroup().id)}'
var privateEndpointName = 'pe-blob-${prefix}'
var privateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

// Workload subnet NSG: permit RDP from Azure Bastion only, then deny
// other inbound traffic originating from the virtual network.
resource workloadNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-workload-01'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Bastion'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.0.2.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.0.1.0/24'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Deny-Other-VNet-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Virtual network. Subnets are declared separately below.
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: workloadSubnetName
  properties: {
    addressPrefix: '10.0.1.0/24'
    networkSecurityGroup: {
      id: workloadNsg.id
    }
    routeTable: {
      id: workloadRouteTable.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    routeToFirewall
  ]
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: bastionSubnetName
  properties: {
    addressPrefix: '10.0.2.0/24'
  }
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: firewallSubnetName
  properties: {
    addressPrefix: '10.0.3.0/26'
  }
}

// Standard static public IP addresses for Bastion and Azure Firewall.
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-fw-01'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Firewall Standard. Its dedicated subnet must be at least /26.
resource firewall 'Microsoft.Network/azureFirewalls@2023-09-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    ipConfigurations: [
      {
        name: 'AzureFirewallIpConfiguration'
        properties: {
          publicIPAddress: {
            id: firewallPublicIp.id
          }
          subnet: {
            id: firewallSubnet.id
          }
        }
      }
    ]
    applicationRuleCollections: [
      {
        name: 'RC-Web-Access'
        properties: {
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'Allow-HTTP-HTTPS'
              protocols: [
                {
                  protocolType: 'Http'
                  port: 80
                }
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                '*'
              ]
              sourceAddresses: [
                '10.0.1.0/24'
              ]
            }
          ]
        }
      }
    ]
  }
}

// Route workload-subnet internet-bound IPv4 traffic through Azure Firewall.
// Azure Firewall uses 10.0.3.4, the first usable address in this dedicated subnet.
resource workloadRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'rt-workload-to-fw'
  location: location
  properties: {
    disableBgpRoutePropagation: false
  }
}

resource routeToFirewall 'Microsoft.Network/routeTables/routes@2023-09-01' = {
  parent: workloadRouteTable
  name: 'Route-To-Firewall'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: '10.0.3.4'
  }
  dependsOn: [
    firewall
  ]
}

// Storage account: no public network access; Blob is reached via Private Endpoint.
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Private DNS zone and VNet link for the Storage Blob Private Endpoint.
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for the Blob service.
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: workloadSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'blobConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storagePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blobPrivateDnsZone'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Private network interface for the Windows VM; no public IP is assigned.
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: workloadSubnet.id
          }
        }
      }
    ]
  }
}

// Windows Server VM. Credentials are parameters and are not stored in this file.
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2as_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}

// Azure Bastion provides RDP access without exposing the VM to the internet.
resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: bastionSubnet.id
          }
        }
      }
    ]
  }
}

output virtualNetworkName string = vnet.name
output virtualMachineName string = vm.name
output storageAccountName string = storageAccount.name
output firewallName string = firewall.name
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output bastionName string = bastion.name
