mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }

  }
  mock_data "azapi_resource_list" {
    override_during = plan
    defaults = {
      output = {
        value = [{
          id         = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          properties = { roleName = "Reader" }
        }]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
      output = {
        properties = {
          principalId   = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
          reservationId = "reservation-unit"
        }
      }
    }
  }
}
mock_provider "random" {}
mock_provider "terraform" {}

run "composition" {
  command = apply
  module { source = "./examples/complete" }
  variables {
    enable_telemetry = false
  }
  override_resource {
    target = module.capacity_reservation_group.azapi_resource.this
    values = { id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit" }
  }
  assert {
    condition = toset(keys(output.capacity_reservation_resource_ids)) == toset([
      "7:primary:zone-1",
      "7:primary:zone-2",
      "11:replacement:zone-1",
      "8:untagged:zone-1"
    ])
    error_message = "The actual complete example must create both primary zones plus sibling replacement/untagged definitions, not silently discard nested extra attributes."
  }
  assert {
    condition     = azapi_resource.resource_group.name == module.naming.resource_group.name_unique
    error_message = "The default RG name must include the naming module's unique suffix."
  }
}

run "unlocked" {
  command = apply
  module { source = "./examples/complete" }
  variables {
    enable_telemetry    = false
    locks_enabled       = false
    resource_group_name = "approved-existing-complete"
    tags                = { environment = "mutation", owner = "parent" }
  }
  override_resource {
    target = module.capacity_reservation_group.azapi_resource.this
    values = { id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit" }
  }
  assert {
    condition     = length(output.capacity_reservation_resource_ids) == 4
    error_message = "Staging unlock and a metadata change must retain all four reservation instances."
  }
  assert {
    condition     = azapi_resource.resource_group.name == "approved-existing-complete"
    error_message = "An explicitly approved existing RG name must not gain a random suffix."
  }
}
