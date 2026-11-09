resource "azapi_resource" "network_security_group" {
  location  = var.location
  name      = "vm-consumption-nsg"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  body = {
    properties = {
      securityRules = [{
        name = "DenyAllInbound"
        properties = {
          access                   = "Deny"
          direction                = "Inbound"
          priority                 = 100
          protocol                 = "*"
          sourceAddressPrefix      = "*"
          sourcePortRange          = "*"
          destinationAddressPrefix = "*"
          destinationPortRange     = "*"
        }
      }]
    }
  }
  response_export_values = []
}

resource "azapi_resource" "virtual_network" {
  location  = var.location
  name      = "vm-consumption-vnet"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.40.0.0/16"] }
    }
  }
  response_export_values = []
}

resource "azapi_resource" "subnet" {
  name      = "private"
  parent_id = azapi_resource.virtual_network.id
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  body = {
    properties = {
      addressPrefix         = "10.40.0.0/24"
      defaultOutboundAccess = false
      networkSecurityGroup  = { id = azapi_resource.network_security_group.id }
    }
  }
  response_export_values = []
}

resource "azapi_resource" "network_interface" {
  location  = var.location
  name      = "vm-consumption-nic"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  body = {
    properties = {
      ipConfigurations = [{
        name = "primary"
        properties = {
          privateIPAllocationMethod = "Dynamic"
          subnet                    = { id = azapi_resource.subnet.id }
        }
      }]
    }
  }
  response_export_values = []
}
