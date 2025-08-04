/*
output "private_endpoints" {
  description = <<DESCRIPTION
  A map of the private endpoints created.
  DESCRIPTION
  value       = var.private_endpoints_manage_dns_zone_group ? azurerm_private_endpoint.this_managed_dns_zone_groups : azurerm_private_endpoint.this_unmanaged_dns_zone_groups
}
*/
output "capacity_reservation_group_id" {
  description = "The ID of the capacity reservation group"
  value       = azapi_resource.capacity_reservation_group.id
}
