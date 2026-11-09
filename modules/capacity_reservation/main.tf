resource "azapi_resource" "this" {
  location  = var.location
  name      = var.capacity_reservation_name
  parent_id = var.parent_id
  type      = var.resource_types.compute_capacity_reservation_groups_capacity_reservations
  body = merge({
    properties = {
    }
    sku = var.sku
  }, var.zone == null ? {} : { zones = [var.zone] })
  ignore_body_changes              = length(var.ignore_body_changes.compute_capacity_reservation_groups_capacity_reservations) > 0 ? var.ignore_body_changes.compute_capacity_reservation_groups_capacity_reservations : null
  replace_triggers_external_values = [var.zone]
  replace_triggers_refs            = ["sku.name"]
  response_export_values           = ["properties.reservationId"]
  retry                            = var.retry
  tags                             = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

moved {
  from = azapi_resource.capacity_reservation
  to   = azapi_resource.this
}
