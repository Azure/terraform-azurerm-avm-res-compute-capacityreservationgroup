output "resource_id" {
  description = "Capacity reservation group ARM ID."
  value       = module.capacity_reservation_group.resource_id
}

output "capacity_reservation_resource_ids" {
  description = "Child reservation ARM IDs keyed by the parent collection."
  value       = module.capacity_reservation_group.capacity_reservation_resource_ids
}
