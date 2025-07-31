resource "azapi_resource" "capacity_reservation" {
  type      = "Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-11-01"
  name      = var.capacity_reservation_name
  parent_id = var.capacity_reservation_group_id
  location  = var.location
  tags      = var.tags
  body = {
    properties = {
    }
    sku   = var.sku
    zones = var.zones
  }
  response_export_values = ["*"]
}