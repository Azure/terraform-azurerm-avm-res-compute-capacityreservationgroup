data "azapi_client_config" "caller" {
  count = var.subscription_id == null || var.subscription_id == "" ? 0 : 1
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.capacity_reservation_group_name
  parent_id = var.parent_id
  type      = var.resource_types.compute_capacity_reservation_groups
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
  ignore_body_changes       = length(var.ignore_body_changes.compute_capacity_reservation_groups) > 0 ? var.ignore_body_changes.compute_capacity_reservation_groups : null
  response_export_values    = []
  retry                     = var.retry
  schema_validation_enabled = var.schema_validation_enabled
  tags                      = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    precondition {
      condition     = var.subscription_id == null || var.subscription_id == "" ? true : lower(var.subscription_id) == lower(one(data.azapi_client_config.caller).subscription_id)
      error_message = "subscription_id must match the subscription configured on the caller's AzAPI provider."
    }
  }
}

module "capacity_reservation" {
  source   = "./modules/capacity_reservation"
  for_each = var.capacity_reservations

  capacity_reservation_name = each.value.name
  location                  = var.location
  parent_id                 = azapi_resource.this.id
  sku                       = each.value.sku
  enable_telemetry          = var.enable_telemetry
  ignore_body_changes       = var.ignore_body_changes.compute_capacity_reservation_groups_capacity_reservations
  lock                      = each.value.lock
  resource_types            = var.resource_types.compute_capacity_reservation_groups_capacity_reservations
  retry                     = var.retry
  role_assignments          = each.value.role_assignments
  tags                      = each.value.tags == null ? var.tags : each.value.tags
  timeouts                  = var.timeouts
  zones                     = each.value.zones
}

moved {
  from = azapi_resource.capacity_reservation_group
  to   = azapi_resource.this
}

moved {
  from = azurerm_management_lock.this
  to   = azapi_resource.lock
}

moved {
  from = azurerm_role_assignment.this
  to   = azapi_resource.role_assignments
}
