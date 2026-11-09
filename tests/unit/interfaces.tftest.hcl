mock_provider "azapi" {
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
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
      output = { properties = { reservationId = "reservation-unit" } }
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
}

run "defaults_omit_extensions_and_sharing" {
  command = apply
  assert {
    condition     = length(azapi_resource.lock) == 0 && length(azapi_resource.role_assignments) == 0 && length(data.azapi_resource_list.role_definitions) == 0
    error_message = "Optional extensions and role lookup must be absent by default."
  }
  assert {
    condition     = !can(azapi_resource.this.body.properties.sharingProfile) && length(azapi_resource.this.response_export_values) == 0
    error_message = "Unset sharing must be omitted, and the group must not export unneeded read-only child projections."
  }
  assert {
    condition     = length(output.capacity_reservation_resource_ids) == 0
    error_message = "Adding the parent-owned collection must not create children by default."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "combined_rg_extensions_and_sharing" {
  command = apply
  variables {
    lock = { kind = "CanNotDelete" }
    sharing_profile = {
      subscription_ids = [{ id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" }]
    }
    role_assignments = {
      reader = {
        name                                   = "11111111-1111-4111-8111-111111111111"
        role_definition_id_or_name             = "rEaDeR"
        principal_id                           = "22222222-2222-4222-8222-222222222222"
        skip_service_principal_aad_check       = true
        description                            = "Unit description"
        condition                              = "(@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'example')"
        condition_version                      = "2.0"
        delegated_managed_identity_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.ManagedIdentity/userAssignedIdentities/delegated"
      }
    }
    tags  = { environment = "unit" }
    zones = ["1"]
    retry = {
      error_message_regex  = ["ScopeLocked"]
      interval_seconds     = 5
      max_interval_seconds = 20
    }
    timeouts = { create = "20m", read = "5m", update = "20m", delete = "10m" }
  }
  assert {
    condition = (
      azapi_resource.lock[0].parent_id == var.parent_id &&
      azapi_resource.role_assignments["reader"].parent_id == var.parent_id &&
      azapi_resource.lock[0].name == "lock-CanNotDelete" &&
      azapi_resource.lock[0].body.properties.level == "CanNotDelete" &&
      azapi_resource.lock[0].body.properties.notes == "Cannot delete the resource or its child resources."
    )
    error_message = "Both extensions must keep the released resource-group scope and lock identity/default notes."
  }
  assert {
    condition = (
      azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId == "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7" &&
      azapi_resource.role_assignments["reader"].body.properties.principalType == "ServicePrincipal" &&
      azapi_resource.role_assignments["reader"].body.properties.description == "Unit description" &&
      azapi_resource.role_assignments["reader"].body.properties.conditionVersion == "2.0" &&
      azapi_resource.role_assignments["reader"].body.properties.condition == var.role_assignments.reader.condition &&
      azapi_resource.role_assignments["reader"].body.properties.delegatedManagedIdentityResourceId == var.role_assignments.reader.delegated_managed_identity_resource_id
    )
    error_message = "RBAC must resolve names case-insensitively and preserve ARM casing, ABAC, delegation and skip-check principal semantics."
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.sharingProfile.subscriptionIds[0].id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" &&
      azapi_resource.this.body.zones[0] == "1" &&
      azapi_resource.this.tags.environment == "unit" &&
      azapi_resource.this.retry.interval_seconds == 5 &&
      azapi_resource.role_assignments["reader"].retry.max_interval_seconds == 20 &&
      azapi_resource.lock[0].timeouts.delete == "10m"
    )
    error_message = "Non-default sharing, zones, tags and retry/timeouts must reach the owned resources."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "read_only_custom_lock_and_explicit_principal_type" {
  command = apply
  variables {
    lock = { kind = "ReadOnly", name = "custom-lock", notes = "Custom notes" }
    role_assignments = {
      reader = {
        role_definition_id_or_name       = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id                     = "22222222-2222-4222-8222-222222222222"
        principal_type                   = "Group"
        skip_service_principal_aad_check = true
      }
    }
  }
  assert {
    condition     = azapi_resource.lock[0].name == "custom-lock" && azapi_resource.lock[0].body.properties.notes == "Custom notes" && azapi_resource.lock[0].body.properties.level == "ReadOnly"
    error_message = "Explicit lock settings must be preserved."
  }
  assert {
    condition = (
      length(data.azapi_resource_list.role_definitions) == 0 &&
      azapi_resource.role_assignments["reader"].body.properties.principalType == "Group" &&
      startswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/")
    )
    error_message = "Role IDs must bypass lookup, tenant-level definitions must normalize, and explicit principal type must take precedence."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "empty_sharing_is_an_explicit_list" {
  command = apply
  variables {
    sharing_profile = { subscription_ids = [] }
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.sharingProfile.subscriptionIds) == 0
    error_message = "An explicit empty sharing list must not be changed into omission by module logic. This does not prove provider serialization."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "parent_owns_child_cardinality" {
  command = apply
  variables {
    capacity_reservations = {
      first = {
        name = "first", sku = { name = "Standard_B2ms", capacity = 1 }, zones = ["1"]
        lock = { kind = "CanNotDelete", notes = "Nested lock" }
        role_assignments = {
          reader = { role_definition_id_or_name = "rEaDeR", principal_id = "22222222-2222-4222-8222-222222222222", principal_type = "Group" }
        }
      }
      second = { name = "second", sku = { name = "Standard_D2s_v5", capacity = 2, tier = "Standard" }, zones = ["2"] }
    }
    retry    = { error_message_regex = ["ScopeLocked"], interval_seconds = 5 }
    timeouts = { create = "30m", delete = "10m" }
    resource_types = {
      compute_capacity_reservation_groups_capacity_reservations = {
        compute_capacity_reservation_groups_capacity_reservations = "Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-11-01"
        authorization_locks                                       = "Microsoft.Authorization/locks@2016-09-01"
        authorization_role_assignments                            = "Microsoft.Authorization/roleAssignments@2022-04-01"
        authorization_role_definitions                            = "Microsoft.Authorization/roleDefinitions@2022-04-01"
      }
    }
    ignore_body_changes = {
      compute_capacity_reservation_groups_capacity_reservations = {
        compute_capacity_reservation_groups_capacity_reservations = ["sku.capacity"]
        authorization_locks                                       = ["properties.notes"]
        authorization_role_assignments                            = ["properties.description"]
      }
    }
  }
  override_resource {
    target = module.capacity_reservation["first"].azapi_resource.this
    values = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/first"
      output = { properties = { reservationId = "platform-first" } }
    }
  }
  override_resource {
    target = module.capacity_reservation["second"].azapi_resource.this
    values = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/second"
      output = { properties = { reservationId = "platform-second" } }
    }
  }
  assert {
    condition     = toset(keys(output.capacity_reservation_resource_ids)) == toset(["first", "second"])
    error_message = "The parent must aggregate independently managed single-instance children by input key."
  }
  assert {
    condition = (
      output.resource_id == output.capacity_reservation_group_id &&
      can(provider::azapi::parse_resource_id("Microsoft.Compute/capacityReservationGroups", output.resource_id)) &&
      alltrue([for id in output.capacity_reservation_resource_ids : can(provider::azapi::parse_resource_id("Microsoft.Compute/capacityReservationGroups/capacityReservations", id))]) &&
      output.capacity_reservation_resource_ids["first"] != output.resource_id &&
      output.capacity_reservation_resource_ids["first"] != output.capacity_reservation_resource_ids["second"] &&
      !can(azapi_resource.this.body.properties.capacityReservation) &&
      !can(azapi_resource.this.body.properties.virtualMachinesAssociated)
    )
    error_message = "Group association aliases must be scalar group ARM IDs, the child map must contain distinct child ARM IDs, and this module must not write VM associations."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_parent" {
  command = plan
  variables {
    parent_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  }
  expect_failures = [var.parent_id]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "resource_controls_accept_overrides" {
  command = apply
  variables {
    resource_types = {
      compute_capacity_reservation_groups = "Microsoft.Compute/capacityReservationGroups@2024-07-01"
    }
    ignore_body_changes = {
      compute_capacity_reservation_groups = ["properties.sharingProfile"]
      authorization_locks                 = ["properties.notes"]
      authorization_role_assignments      = ["properties.description"]
    }
  }
  assert {
    condition     = azapi_resource.this.type == "Microsoft.Compute/capacityReservationGroups@2024-07-01"
    error_message = "The primary resource must honor its consumer API override."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_assignment_names" {
  command = plan
  variables {
    role_assignments = {
      first = {
        name                       = "11111111-1111-4111-8111-111111111111"
        role_definition_id_or_name = "Reader"
        principal_id               = "22222222-2222-4222-8222-222222222222"
      }
      second = {
        name                       = "11111111-1111-4111-8111-111111111111"
        role_definition_id_or_name = "Reader"
        principal_id               = "33333333-3333-4333-8333-333333333333"
      }
    }
  }
  expect_failures = [azapi_resource.role_assignments]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_principal_type" {
  command = plan
  variables {
    role_assignments = {
      invalid = {
        role_definition_id_or_name = "Reader"
        principal_id               = "22222222-2222-4222-8222-222222222222"
        principal_type             = "Unknown"
      }
    }
  }
  expect_failures = [azapi_resource.role_assignments]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_lock_kind" {
  command = plan
  variables {
    lock = { kind = "None" }
  }
  expect_failures = [var.lock]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_invalid_delegation" {
  command = plan
  variables {
    role_assignments = {
      invalid = {
        role_definition_id_or_name             = "Reader"
        principal_id                           = "22222222-2222-4222-8222-222222222222"
        delegated_managed_identity_resource_id = "/not-an-identity"
      }
    }
  }
  expect_failures = [var.role_assignments]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_unknown_role_name" {
  command = plan
  variables {
    role_assignments = {
      invalid = {
        role_definition_id_or_name = "Not an existing role"
        principal_id               = "22222222-2222-4222-8222-222222222222"
      }
    }
  }
  expect_failures = [azapi_resource.role_assignments]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_duplicate_child_names" {
  command = plan
  variables {
    capacity_reservations = {
      first  = { name = "duplicate", sku = { name = "Standard_B2ms", capacity = 1 } }
      second = { name = "DUPLICATE", sku = { name = "Standard_B2ms", capacity = 1 } }
    }
  }
  expect_failures = [var.capacity_reservations]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
