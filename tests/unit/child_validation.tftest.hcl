mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/child"
      output = { properties = { reservationId = "unit" } }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {}

mock_provider "terraform" {}

variables {
  parent_id                 = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
  capacity_reservation_name = "child"
  location                  = "westeurope"
  enable_telemetry          = false
  zone                      = null
  sku                       = { name = "Standard_D2s_v5", capacity = 1 }
}

run "regional_omits_zones" {
  command = apply
  module {
    source = "./modules/capacity_reservation"
  }
  assert {
    condition     = !can(azapi_resource.this.body.zones) && azapi_resource.this.body.sku.capacity == 1
    error_message = "Regional requests omit zones, not null or an all-zone default."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "resize_to_zero_keeps_identity" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    sku = { name = "Standard_D2s_v5", capacity = 0 }
  }
  assert {
    condition     = azapi_resource.this.body.sku.capacity == 0 && output.resource_id == run.regional_omits_zones.resource_id
    error_message = "Zero must be accepted without changing the configured identity; Azure resize persistence is a separate test."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_negative_child_capacity" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    sku = { name = "Standard_D2s_v5", capacity = -1 }
  }
  expect_failures = [var.sku]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_fractional_child_capacity" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    sku = { name = "Standard_D2s_v5", capacity = 1.5 }
  }
  expect_failures = [var.sku]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_child_zone" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    zone = "4"
  }
  expect_failures = [var.zone]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
