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
  tags                            = { inherited = "yes" }
  zones                           = ["1", "2"]
}

run "zonal_fanout" {
  command = apply
  variables {
    capacity_reservations = {
      appliance = { name = "shared", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["2", "1"] }
      override  = { name = "override", sku = { name = "Standard_D4s_v5", capacity = 1 }, zones = ["1"], tags = { own = "yes" } }
      empty     = { name = "empty", sku = { name = "Standard_D8s_v5", capacity = 1 }, zones = ["1"], tags = {} }
    }
  }
  assert {
    condition     = toset(keys(output.capacity_reservation_resource_ids)) == toset(["9:appliance:zone-1", "9:appliance:zone-2", "8:override:zone-1", "5:empty:zone-1"])
    error_message = "Fan-out must produce stable definition-plus-zone output keys, not indices."
  }
  assert {
    condition = (
      local.capacity_reservations["9:appliance:zone-1"].name == "shared-z1" &&
      local.capacity_reservations["9:appliance:zone-2"].name == "shared-z2" &&
      local.capacity_reservations["9:appliance:zone-2"].sku.capacity == 1 &&
      local.capacity_reservations["9:appliance:zone-2"].zone == "2" &&
      local.capacity_reservations["9:appliance:zone-1"].tags == null &&
      local.capacity_reservations["8:override:zone-1"].tags == tomap({ own = "yes" }) &&
      length(local.capacity_reservations["5:empty:zone-1"].tags) == 0
    )
    error_message = "Names, per-zone quantity, single zone and tag override/clearing intents must survive expansion."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "reordered_zones_preserve_keys_and_ids" {
  command = plan
  variables {
    capacity_reservations = {
      appliance = { name = "shared", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1", "2"] }
      override  = { name = "override", sku = { name = "Standard_D4s_v5", capacity = 1 }, zones = ["1"], tags = { own = "yes" } }
      empty     = { name = "empty", sku = { name = "Standard_D8s_v5", capacity = 1 }, zones = ["1"], tags = {} }
    }
  }
  assert {
    condition     = output.capacity_reservation_resource_ids == run.zonal_fanout.capacity_reservation_resource_ids
    error_message = "Reordering requested zones must preserve the same state addresses and output IDs."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "regional_zero_boundary_and_delimiter_safe_keys" {
  command = apply
  variables {
    zones = []
    capacity_reservations = {
      "a:zone-1" = { name = "regional", sku = { name = "Standard_D2s_v5", capacity = 0 }, zones = [] }
    }
  }
  assert {
    condition = (
      keys(output.capacity_reservation_resource_ids) == ["8:a:zone-1:regional"] &&
      local.capacity_reservations["8:a:zone-1:regional"].zone == null &&
      local.capacity_reservations["8:a:zone-1:regional"].name == "regional-regional" &&
      local.capacity_reservations["8:a:zone-1:regional"].sku.capacity == 0 &&
      !can(azapi_resource.this.body.zones)
    )
    error_message = "An explicit empty zone list must create one regional child, accept zero, and omit group zones."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_fractional_root_capacity" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 0.5 }, zones = ["1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_negative_root_capacity" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = -1 }, zones = ["1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_zones_without_silent_drops" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1", "1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_size_zone_despite_different_names" {
  command = plan
  variables {
    capacity_reservations = {
      one = { name = "one", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1", "2"] }
      two = { name = "two", sku = { name = "standard_d2s_v5", capacity = 1 }, zones = ["2"] }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_regional_sizes" {
  command = plan
  variables {
    zones = []
    capacity_reservations = {
      one = { name = "one", sku = { name = "Standard_D2s_v5", capacity = 0 }, zones = [] }
      two = { name = "two", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = [] }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_expanded_name_collisions" {
  command = plan
  variables {
    capacity_reservations = {
      one = { name = "same", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"] }
      two = { name = "SAME", sku = { name = "Standard_D4s_v5", capacity = 1 }, zones = ["1"] }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_zone_outside_group" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["3"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_regional_child_in_zonal_group" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = [] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_zonal_child_in_regional_group" {
  command = plan
  variables {
    zones                 = []
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_logical_zone" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["0"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_group_zones" {
  command = plan
  variables {
    zones = ["1", "1"]
  }
  expect_failures = [var.zones]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_expanded_name" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "bad/name", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_overlong_expanded_name" {
  command = plan
  variables {
    capacity_reservations = { bad = { name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", sku = { name = "Standard_D2s_v5", capacity = 1 }, zones = ["1"] } }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
