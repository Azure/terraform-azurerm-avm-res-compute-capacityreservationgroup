mock_provider "azapi" {
  mock_data "azapi_client_config" {
    override_during = plan
    defaults = {
      subscription_id          = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      subscription_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      tenant_id                = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
      output = {
        properties = {
          reservationId = "reservation-unit"
        }
      }
    }
  }
}

mock_provider "random" {}

mock_provider "terraform" {}

variables {
  capacity_reservation_group_name = "unit"
  location                        = "westeurope"
  parent_id                       = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
  enable_telemetry                = false
}

run "matching_subscription_and_outputs" {
  command = apply
  variables {
    subscription_id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
  }
  assert {
    condition     = output.resource_id == output.capacity_reservation_group_id && output.name == "unit"
    error_message = "Standard outputs must preserve the existing group ID and configured name."
  }
  assert {
    condition     = length(data.azapi_client_config.caller) == 1
    error_message = "An explicit subscription must be checked against the caller's AzAPI provider."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_wrong_provider_subscription" {
  command = plan
  variables {
    subscription_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  }
  expect_failures = [azapi_resource.this]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "omitted_subscription_does_not_read_provider_context" {
  command = apply
  assert {
    condition     = length(data.azapi_client_config.caller) == 0
    error_message = "The empty default must not force a client-context lookup."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "null_subscription_does_not_read_provider_context" {
  command = apply
  variables {
    subscription_id = null
  }
  assert {
    condition     = length(data.azapi_client_config.caller) == 0
    error_message = "An explicit null must retain the previous unset-subscription behavior."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "explicit_empty_subscription_does_not_read_provider_context" {
  command = apply
  variables {
    subscription_id = ""
  }
  assert {
    condition     = length(data.azapi_client_config.caller) == 0
    error_message = "An explicitly empty subscription must skip the AzAPI subscription assertion."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "child_outputs_and_optional_tags" {
  command = apply
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    parent_id                 = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
    capacity_reservation_name = "child"
    sku = {
      capacity = 1
      name     = "Standard_B2ms"
    }
  }
  assert {
    condition     = output.resource_id == output.capacity_reservation_resource_id && output.name == "child"
    error_message = "Standard child outputs must preserve the existing resource ID and configured name."
  }
  assert {
    condition     = output.capacity_reservation_id == "reservation-unit"
    error_message = "The existing reservation ID output must continue exporting properties.reservationId."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
