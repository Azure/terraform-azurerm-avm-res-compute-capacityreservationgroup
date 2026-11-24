mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
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
  capacity_reservation_group_name = "unit"
  location                        = "westeurope"
  parent_id                       = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
  enable_telemetry                = false
  zones                           = ["1", "2"]
}

run "reject_multizone_guid" {
  command = plan
  variables {
    capacity_reservations = {
      multi = {
        name = "multi", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1", "2"]
        role_assignments = {
          reader = {
            name                       = "11111111-1111-4111-8111-111111111111"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "reject_cross_definition_guid" {
  command = plan
  variables {
    capacity_reservations = {
      one = {
        name = "one", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"]
        role_assignments = {
          reader = {
            name                       = "abcdefab-1111-4111-8111-111111111111"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
      two = {
        name = "two", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["2"]
        role_assignments = {
          reader = {
            name                       = "ABCDEFAB-1111-4111-8111-111111111111"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "reject_root_child_guid" {
  command = plan
  variables {
    role_assignments = {
      reader = {
        name                       = "11111111-1111-4111-8111-111111111111"
        principal_id               = "22222222-2222-4222-8222-222222222222"
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
      }
    }
    capacity_reservations = {
      one = {
        name = "one", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"]
        role_assignments = {
          reader = {
            name                       = "11111111-1111-4111-8111-111111111111"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "distinct_single_zone_guids" {
  command = apply
  variables {
    capacity_reservations = {
      one = {
        name = "one", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"]
        role_assignments = {
          reader = {
            name                       = "11111111-1111-4111-8111-111111111111"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
      two = {
        name = "two", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["2"]
        role_assignments = {
          reader = {
            name                       = "33333333-3333-4333-8333-333333333333"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  assert {
    condition     = length(output.capacity_reservation_resource_ids) == 2
    error_message = "Distinct explicit GUIDs on separate single-zone definitions must remain supported."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "regional_guid" {
  command = apply
  variables {
    zones = []
    capacity_reservations = {
      regional = {
        name = "regional", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = []
        role_assignments = {
          reader = {
            name                       = "44444444-4444-4444-8444-444444444444"
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  assert {
    condition     = length(output.capacity_reservation_resource_ids) == 1
    error_message = "A single regional reservation may still use an explicit GUID."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "generated_multizone_guids" {
  command = apply
  variables {
    capacity_reservations = {
      multi = {
        name = "multi", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1", "2"]
        role_assignments = {
          reader = {
            principal_id               = "22222222-2222-4222-8222-222222222222"
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          }
        }
      }
    }
  }
  assert {
    condition     = length(output.capacity_reservation_resource_ids) == 2
    error_message = "Omitting names must support multi-zone fan-out with independently generated UUIDs."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
