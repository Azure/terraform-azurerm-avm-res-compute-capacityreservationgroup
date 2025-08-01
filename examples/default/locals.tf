locals {
  capacity_reservation_group_name = "test-capacity-reservation-group"
  tags = {
    environment = "test"
    project     = "demo"
  }
  subscription_id = "ad6f62ba-74ae-4f03-8123-5431c364621d" # Replace with your actual subscription ID
  sku = {
    capacity = 1
    name     = "Standard_B2ms"
  }
  zones = ["1"] # Specify the availability zones for the
}