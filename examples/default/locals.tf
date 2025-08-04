locals {
  capacity_reservation_group_name = "test-capacity-reservation-group"
  capacity_reservation_name       = "test-capacity-reservation"
  sku = {
    capacity = 1
    name     = "Standard_B2ms"
  }
  subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # Replace with your actual subscription ID
  tags = {
    environment = "test"
    project     = "demo"
  }
  zones = ["1"] # Specify the availability zones for the
}