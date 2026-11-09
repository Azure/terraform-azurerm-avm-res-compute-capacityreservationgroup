data "azapi_client_config" "this" {}

resource "azapi_resource" "resource_group" {
  location               = var.location
  name                   = var.resource_group_name
  parent_id              = data.azapi_client_config.this.subscription_resource_id
  type                   = "Microsoft.Resources/resourceGroups@2024-03-01"
  response_export_values = []
}

resource "azapi_resource" "identity" {
  location               = var.location
  name                   = "capacity-reader"
  parent_id              = azapi_resource.resource_group.id
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  response_export_values = ["properties.principalId"]
}

module "capacity_reservation_group" {
  source = "../../"

  capacity_reservation_group_name = "capacity-complete"
  location                        = var.location
  parent_id                       = azapi_resource.resource_group.id
  capacity_reservations = {
    primary = {
      name  = "primary"
      sku   = { name = var.vm_sizes.primary, capacity = 1, tier = "Standard" }
      zones = var.reservation_zones
      lock  = { kind = "CanNotDelete", notes = "Example individual reservation lock" }
      role_assignments = {
        reader = {
          role_definition_id_or_name       = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          principal_id                     = azapi_resource.identity.output.properties.principalId
          principal_type                   = "ServicePrincipal"
          skip_service_principal_aad_check = true
        }
      }
    }
    replacement = {
      name  = "replacement"
      sku   = { name = var.vm_sizes.replacement, capacity = 1 }
      zones = [var.reservation_zones[0]]
      tags  = { workload = "explicit-replacement" }
    }
    untagged = {
      name  = "untagged"
      sku   = { name = var.vm_sizes.untagged, capacity = 1 }
      zones = [var.reservation_zones[0]]
      tags  = {}
    }
  }
  enable_telemetry = var.enable_telemetry
  lock = {
    kind  = "CanNotDelete"
    notes = "Example resource-group lock"
  }
  retry = {
    error_message_regex  = ["ScopeLocked", "PrincipalNotFound"]
    interval_seconds     = 15
    max_interval_seconds = 60
  }
  role_assignments = {
    reader = {
      role_definition_id_or_name       = "Reader"
      principal_id                     = azapi_resource.identity.output.properties.principalId
      principal_type                   = "ServicePrincipal"
      skip_service_principal_aad_check = true
    }
  }
  subscription_id = var.subscription_id
  tags            = { environment = "example" }
  timeouts        = { create = "30m", delete = "30m" }
  zones           = var.reservation_zones
}
