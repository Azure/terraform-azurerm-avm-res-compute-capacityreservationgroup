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

run "complete_example_has_all_tag_variants" {
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
}
