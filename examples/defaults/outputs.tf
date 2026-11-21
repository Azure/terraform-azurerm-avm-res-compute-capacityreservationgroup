# capacity reservation group ID output
output "capacity_reservation_group_id" {
  description = "The ID of the capacity reservation group"
  value       = module.capacity_reservation_group.capacity_reservation_group_id
}

# capacity reservation ID output
output "capacity_reservation_id" {
  description = "The Reservation ID of the capacity reservation"
  value       = module.capacity_reservation.capacity_reservation_id
}

# capacity reservation resource ID output
output "capacity_reservation_resource_id" {
  description = "The Resource ID of the capacity reservation"
  value       = module.capacity_reservation.capacity_reservation_resource_id
}
