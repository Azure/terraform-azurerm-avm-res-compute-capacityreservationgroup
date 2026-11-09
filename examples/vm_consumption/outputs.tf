output "capacity_reservation_group_id" {
  description = "Group ARM ID used by the VM owner, not a child ID or platform reservationId."
  value       = module.capacity_reservation_group.resource_id
}

output "capacity_reservation_resource_ids" {
  description = "Expanded reservation ARM IDs."
  value       = module.capacity_reservation_group.capacity_reservation_resource_ids
}

output "virtual_machine_resource_id" {
  description = "The VM ARM ID for approved readback and deallocation."
  value       = azapi_resource.virtual_machine.id
}
