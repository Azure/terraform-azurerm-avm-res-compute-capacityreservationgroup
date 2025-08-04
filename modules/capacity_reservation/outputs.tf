output "capacity_reservation_id" {
  description = "The Reservation ID of the capacity reservation"
  value       = azapi_resource.capacity_reservation.output.properties["reservationId"]
}

output "capacity_reservation_resource_id" {
  description = "The Resource ID of the capacity reservation"
  value       = azapi_resource.capacity_reservation.id
}
