locals {
  capacity_reservation_group_name = "test-capacity-reservation-group"
  capacity_reservation_name       = "test-capacity-reservation"
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
