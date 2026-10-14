output "capacity_reservation_group_id" {
  description = "The ID of the capacity reservation group"
  value       = azapi_resource.capacity_reservation_group.id
}

output "name" {
  description = "The name of the capacity reservation group."
  value       = azapi_resource.capacity_reservation_group.name
}

output "resource_id" {
  description = "The resource ID of the capacity reservation group."
  value       = azapi_resource.capacity_reservation_group.id
}
