resource "azapi_resource" "capacity_reservation" {
  location  = var.location
  name      = var.capacity_reservation_name
  parent_id = var.capacity_reservation_group_id
  type      = "Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-11-01"
  body = {
    properties = {
    }
    sku   = var.sku
    zones = var.zones
  }
  response_export_values = ["*"]
  tags                   = var.tags
}