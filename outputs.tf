output "capacity_reservation_group_id" {
  description = "Alias of resource_id: the group ARM resource ID for opt-in VM association, not a reservation ARM ID or reservationId."
  value       = azapi_resource.this.id
}

output "capacity_reservation_resource_ids" {
  description = "Map of child ARM resource IDs keyed by capacity_reservations input keys; these are not VM association group IDs or platform reservationId values."
  value       = { for key, reservation in module.capacity_reservation : key => reservation.resource_id }
}

output "name" {
  description = "The name of the capacity reservation group."
  value       = azapi_resource.this.name
}

output "resource_id" {
  description = "The group ARM resource ID. The VM owner can opt in using this reference in properties.capacityReservation.capacityReservationGroup.id; this module does not manage VM associations."
  value       = azapi_resource.this.id
}
