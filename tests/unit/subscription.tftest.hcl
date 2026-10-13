mock_provider "azapi" {
  # A different subscription verifies that the guard reads AzureRM, not AzAPI.
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "cccccccc-cccc-cccc-cccc-cccccccccccc"
      subscription_resource_id = "/subscriptions/cccccccc-cccc-cccc-cccc-cccccccccccc"
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

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    override_during = plan
    defaults = {
      subscription_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
}

mock_provider "modtm" {}

mock_provider "random" {}

run "matching_subscription_and_outputs" {
  command = apply

  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }

  variables {
    capacity_reservation_group_name = "unit"
    location                        = "westeurope"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
    subscription_id                 = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
  }

  assert {
    condition     = output.resource_id == output.capacity_reservation_group_id && output.name == "unit"
    error_message = "Standard outputs must preserve the existing group ID and configured name."
  }

  assert {
    condition     = length(data.azurerm_client_config.caller) == 1
    error_message = "An explicit subscription must be checked against the caller's AzureRM provider."
  }
}

run "rejects_wrong_provider_subscription" {
  command = plan

  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }

  variables {
    capacity_reservation_group_name = "unit"
    location                        = "westeurope"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
    subscription_id                 = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  }

  expect_failures = [azapi_resource.capacity_reservation_group]
}

run "omitted_subscription_does_not_read_provider_context" {
  command = apply

  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }

  variables {
    capacity_reservation_group_name = "unit"
    location                        = "westeurope"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
  }

  assert {
    condition     = length(data.azurerm_client_config.caller) == 0
    error_message = "The empty default must not force an AzureRM client-context lookup."
  }
}

run "null_subscription_does_not_read_provider_context" {
  command = apply

  providers = {
    azapi   = azapi
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }

  variables {
    capacity_reservation_group_name = "unit"
    location                        = "westeurope"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
    subscription_id                 = null
  }

  assert {
    condition     = length(data.azurerm_client_config.caller) == 0
    error_message = "An explicit null must retain the previous unset-subscription behavior."
  }
}

run "child_outputs_and_optional_tags" {
  command = apply

  module {
    source = "./modules/capacity_reservation"
  }

  providers = {
    azapi = azapi
  }

  variables {
    capacity_reservation_group_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
    capacity_reservation_name     = "child"
    location                      = "westeurope"
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
}
