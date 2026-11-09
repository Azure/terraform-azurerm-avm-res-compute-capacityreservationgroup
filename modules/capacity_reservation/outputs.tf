output "capacity_reservation_id" {
  description = "Platform-generated scalar properties.reservationId, not an ARM resource ID and not a VM association reference. May be unknown during updates."
  value       = azapi_resource.this.output.properties["reservationId"]
}

output "capacity_reservation_resource_id" {
  description = "Alias of resource_id: the child reservation ARM resource ID, not the platform reservationId or group VM-association ID."
  value       = azapi_resource.this.id
}

output "name" {
  description = "The name of the capacity reservation."
  value       = azapi_resource.this.name
}

output "resource_id" {
  description = "The child reservation ARM resource ID. VM association uses the parent group ARM ID instead."
  value       = azapi_resource.this.id
}
