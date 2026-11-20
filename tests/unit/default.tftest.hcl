mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      subscription_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        value = [
          {
            name        = "eastus"
            displayName = "East US"
            metadata = {
              geography      = "United States"
              geographyGroup = "US"
              pairedRegion   = [{ name = "westus" }]
              regionCategory = "Recommended"
              regionType     = "Physical"
            }
            availabilityZoneMappings = [{ logicalZone = "1" }]
          },
          {
            name        = "uaecentral"
            displayName = "UAE Central"
            metadata = {
              geography      = "United Arab Emirates"
              geographyGroup = "Middle East"
              pairedRegion   = [{ name = "uaenorth" }]
              regionCategory = "Recommended"
              regionType     = "Physical"
            }
          },
          {
            name        = "centraluseuap"
            displayName = "Central US EUAP"
            metadata = {
              geography      = "United States"
              geographyGroup = "US"
              pairedRegion   = [{ name = "eastus2euap" }]
              regionCategory = "Other"
              regionType     = "Physical"
            }
            availabilityZoneMappings = [{ logicalZone = "1" }]
          }
        ]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
      output = { properties = { reservationId = "unit" } }
    }
  }
}
mock_provider "random" {}
mock_provider "terraform" {}

run "live_regions" {
  command = apply
  module { source = "./examples/default" }
  variables {
    enable_telemetry = false
  }
  override_resource {
    target = random_integer.region_index
    values = { result = 0 }
  }
  override_resource {
    target = module.capacity_reservation_group.azapi_resource.this
    values = { id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit" }
  }
  assert {
    condition = (
      [for region in module.regions.regions : region.name] == ["eastus"] &&
      azapi_resource.resource_group.location == "eastus"
    )
    error_message = "Region selection must use live subscription data and exclude non-zonal and non-recommended locations."
  }
  assert {
    condition     = azapi_resource.resource_group.name == module.naming.resource_group.name_unique
    error_message = "The RG must use the naming module's unique name."
  }
}

run "no_regions" {
  command = plan
  module { source = "./examples/default" }
  variables {
    enable_telemetry = false
  }
  override_module {
    target  = module.regions
    outputs = { regions = [] }
  }
  expect_failures = [random_integer.region_index]
}
