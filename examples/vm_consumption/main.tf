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

module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.22.0"

  location            = var.location
  name                = "vm-consumption"
  resource_group_name = var.resource_group_name
  zone                = var.zone
  account_credentials = {
    password_authentication_disabled = true
    admin_credentials = {
      username                           = "azureuser"
      generate_admin_password_or_ssh_key = false
      ssh_keys                           = [var.ssh_public_key == null ? azapi_resource_action.ssh_key_pair[0].output.publicKey : var.ssh_public_key]
    }
  }
  capacity_reservation_group_resource_id = var.capacity_reservation_enabled ? module.capacity_reservation_group.resource_id : null
  enable_telemetry                       = var.enable_telemetry
  encryption_at_host_enabled             = false
  network_interfaces = {
    primary = {
      name       = "vm-consumption-nic"
      is_primary = true
      ip_configurations = {
        primary = {
          name                          = "primary"
          private_ip_subnet_resource_id = azapi_resource.subnet.id
          create_public_ip_address      = false
        }
      }
    }
  }
  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  os_type             = "Linux"
  parent_id           = azapi_resource.resource_group.id
  secure_boot_enabled = true
  sku_size            = var.vm_size
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  vtpm_enabled = true

  # The group ID alone depends only on the container, not the reserved capacity.
  depends_on = [module.capacity_reservation_group]
}
