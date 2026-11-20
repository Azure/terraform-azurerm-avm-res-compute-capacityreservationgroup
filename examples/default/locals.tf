locals {
  capacity_reservation_group_name = "test-capacity-reservation-group"
  capacity_reservation_name       = "test-capacity-reservation"
  retry = {
    error_message_regex  = ["Cannot delete resource while nested resources exist"]
    interval_seconds     = 15
    max_interval_seconds = 60
  }
  sku = {
    capacity = 1
    name     = var.vm_size
  }
  tags = {
    environment = "test"
    project     = "demo"
  }
  zone = var.zone
}
