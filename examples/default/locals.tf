locals {
  capacity_reservation_group_name = "test-capacity-reservation-group"
  capacity_reservation_name       = "test-capacity-reservation"
  tags = {
    environment = "test"
    project     = "demo"
  }
  subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # Replace with your actual subscription ID
  sku = {
    capacity = 1
    name     = "Standard_B2ms"
  }
  zones = ["1"] # Specify the availability zones for the
}