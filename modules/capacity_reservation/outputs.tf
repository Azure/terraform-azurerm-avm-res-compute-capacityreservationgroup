output "capacity_reservation_resource_id" {
  value       = azapi_resource.capacity_reservation.id
  description = "The Resource ID of the capacity reservation"
}

output "capacity_reservation_id" {
  value       = azapi_resource.capacity_reservation.output.properties["reservationId"]
  description = "The Reservation ID of the capacity reservation"
}