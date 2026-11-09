mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/child"
      output = { properties = { reservationId = "reservation-unit" } }
    }
  }
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "terraform" {}

mock_provider "random" {}

run "child_body_controls_and_outputs" {
  command = apply
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    parent_id                 = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
    capacity_reservation_name = "child"
    location                  = "westeurope"
    enable_telemetry          = false
    sku                       = { name = "Standard_D2s_v5", capacity = 3, tier = "Standard" }
    tags                      = { environment = "unit" }
    zone                      = "1"
    retry                     = { error_message_regex = ["ScopeLocked"], interval_seconds = 5 }
    timeouts                  = { create = "45m", delete = "10m" }
    ignore_body_changes       = { compute_capacity_reservation_groups_capacity_reservations = ["sku.capacity"] }
  }
  assert {
    condition = (
      azapi_resource.this.parent_id == var.parent_id &&
      azapi_resource.this.body.sku.capacity == 3 &&
      azapi_resource.this.body.sku.name == "Standard_D2s_v5" &&
      azapi_resource.this.body.sku.tier == "Standard" &&
      azapi_resource.this.body.zones[0] == "1" &&
      length(keys(azapi_resource.this.body.properties)) == 0 &&
      azapi_resource.this.tags.environment == "unit"
    )
    error_message = "SKU and zones belong at ARM top level; read-only properties must not be replayed."
  }
  assert {
    condition = (
      azapi_resource.this.retry.interval_seconds == 5 &&
      azapi_resource.this.timeouts.create == "45m" &&
      azapi_resource.this.response_export_values[0] == "properties.reservationId" &&
      output.capacity_reservation_id == "reservation-unit" &&
      output.resource_id == output.capacity_reservation_resource_id &&
      output.resource_id != output.capacity_reservation_id &&
      can(provider::azapi::parse_resource_id("Microsoft.Compute/capacityReservationGroups/capacityReservations", output.resource_id)) &&
      length(azapi_resource.lock) == 0 &&
      length(azapi_resource.role_assignments) == 0 &&
      length(data.azapi_resource_list.role_definitions) == 0
    )
    error_message = "Child controls, narrow export and scalar output aliases must be preserved."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_child_wrong_parent_type" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    parent_id                 = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
    capacity_reservation_name = "child"
    location                  = "westeurope"
    enable_telemetry          = false
    sku                       = { name = "Standard_B2ms", capacity = 1 }
    zone                      = null
  }
  expect_failures = [var.parent_id]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
