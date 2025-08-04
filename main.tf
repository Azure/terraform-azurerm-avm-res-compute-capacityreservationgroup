# resource "azapi_resource" "resource_group" {
#   type     = "Microsoft.Resources/resourceGroups@2020-06-01"
#   name     = var.resource_group_name
#   location = var.location
# }

# required AVM resources interfaces
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-${var.lock.kind}")
  scope      = var.resource_group_id # TODO: Replace with your azurerm resource name
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = var.resource_group_id # TODO: Replace this dummy resource azurerm_resource_group.TODO with your module resource
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

resource "azapi_resource" "capacity_reservation_group" {
  location  = var.location
  name      = var.capacity_reservation_group_name
  parent_id = var.resource_group_id
  type      = "Microsoft.Compute/capacityReservationGroups@2024-11-01"
  body = {
    properties = merge(
      {},
      var.sharing_profile != null ? {
        sharingProfile = {
          subscriptionIds = [
            for item in var.sharing_profile.subscription_ids : {
              id = item.id
            }
          ]
        }
      } : {}
    )
    zones = var.zones
  }
  response_export_values    = ["*"]
  schema_validation_enabled = var.schema_validation_enabled
  tags                      = var.tags
}
