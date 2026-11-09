data "azapi_client_config" "this" {}

resource "azapi_resource" "resource_group" {
  location               = var.location
  name                   = var.resource_group_name
  parent_id              = data.azapi_client_config.this.subscription_resource_id
  type                   = "Microsoft.Resources/resourceGroups@2024-03-01"
  response_export_values = []
}

module "capacity_reservation_group" {
  source = "../../"

  capacity_reservation_group_name = "vm-consumption"
  location                        = var.location
  parent_id                       = azapi_resource.resource_group.id
  capacity_reservations = {
    vm = {
      name  = "vm"
      sku   = { name = var.vm_size, capacity = var.reservation_capacity }
      zones = [var.zone]
    }
  }
  enable_telemetry = var.enable_telemetry
  tags             = { environment = "example" }
  zones            = [var.zone]
}

resource "azapi_resource" "ssh_public_key" {
  count = var.ssh_public_key == null ? 1 : 0

  location               = var.location
  name                   = "vm-consumption-key"
  parent_id              = azapi_resource.resource_group.id
  type                   = "Microsoft.Compute/sshPublicKeys@2024-11-01"
  body                   = { properties = {} }
  response_export_values = []
}

resource "azapi_resource_action" "ssh_key_pair" {
  count = var.ssh_public_key == null ? 1 : 0

  action                 = "generateKeyPair"
  method                 = "POST"
  resource_id            = azapi_resource.ssh_public_key[0].id
  type                   = "Microsoft.Compute/sshPublicKeys@2024-11-01"
  response_export_values = ["publicKey"]
}

resource "azapi_resource" "virtual_machine" {
  location  = var.location
  name      = "vm-consumption"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Compute/virtualMachines@2024-11-01"
  body = {
    zones = [var.zone]
    properties = {
      hardwareProfile = { vmSize = var.vm_size }
      capacityReservation = {
        capacityReservationGroup = {
          id = var.capacity_reservation_enabled ? module.capacity_reservation_group.resource_id : null
        }
      }
      storageProfile = {
        imageReference = {
          publisher = "Canonical"
          offer     = "0001-com-ubuntu-server-jammy"
          sku       = "22_04-lts-gen2"
          version   = "latest"
        }
        osDisk = {
          createOption = "FromImage"
          deleteOption = "Delete"
          managedDisk  = { storageAccountType = "Premium_LRS" }
        }
      }
      osProfile = {
        computerName  = "vm-consumption"
        adminUsername = "azureuser"
        linuxConfiguration = {
          disablePasswordAuthentication = true
          provisionVMAgent              = true
          ssh = {
            publicKeys = [{
              path    = "/home/azureuser/.ssh/authorized_keys"
              keyData = var.ssh_public_key == null ? azapi_resource_action.ssh_key_pair[0].output.publicKey : var.ssh_public_key
            }]
          }
        }
      }
      networkProfile = {
        networkInterfaces = [{
          id         = azapi_resource.network_interface.id
          properties = { primary = true, deleteOption = "Detach" }
        }]
      }
      securityProfile = {
        securityType = "TrustedLaunch"
        uefiSettings = { secureBootEnabled = true, vTpmEnabled = true }
      }
      diagnosticsProfile = { bootDiagnostics = { enabled = true } }
    }
  }
  response_export_values = []

  # The group ID alone depends only on the container, not the reserved capacity.
  depends_on = [module.capacity_reservation_group]
}
