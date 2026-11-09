mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/child"
      output = { properties = { reservationId = "platform-reservation-id" } }
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
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {
  mock_resource "random_uuid" {
    defaults = { result = "11111111-1111-4111-8111-111111111111" }
  }
}

mock_provider "terraform" {}

variables {
  parent_id                 = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
  capacity_reservation_name = "child"
  location                  = "westeurope"
  sku                       = { name = "Standard_D2s_v5", capacity = 1 }
  enable_telemetry          = false
  zone                      = "1"
}

run "standalone_child_scoped_extensions" {
  command = apply
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = {
        role_definition_id_or_name             = "rEaDeR"
        principal_id                           = "22222222-2222-4222-8222-222222222222"
        skip_service_principal_aad_check       = true
        description                            = "Child role"
        condition                              = "(@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'example')"
        condition_version                      = "2.0"
        delegated_managed_identity_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.ManagedIdentity/userAssignedIdentities/delegated"
      }
    }
    retry    = { error_message_regex = ["ScopeLocked"], interval_seconds = 5, max_interval_seconds = 20 }
    timeouts = { create = "20m", read = "5m", update = "20m", delete = "10m" }
    resource_types = {
      authorization_locks            = "Microsoft.Authorization/locks@2016-09-01"
      authorization_role_assignments = "Microsoft.Authorization/roleAssignments@2022-04-01"
      authorization_role_definitions = "Microsoft.Authorization/roleDefinitions@2022-04-01"
    }
    ignore_body_changes = {
      authorization_locks            = ["properties.notes"]
      authorization_role_assignments = ["properties.description"]
    }
  }
  assert {
    condition = (
      azapi_resource.lock[0].parent_id == output.resource_id &&
      azapi_resource.role_assignments["reader"].parent_id == output.resource_id &&
      azapi_resource.lock[0].parent_id != var.parent_id &&
      azapi_resource.lock[0].name == "lock-CanNotDelete" &&
      azapi_resource.lock[0].body.properties.level == "CanNotDelete" &&
      azapi_resource.lock[0].body.properties.notes == "Cannot delete the resource or its child resources."
    )
    error_message = "Child extensions must attach to the reservation ARM ID with deterministic lock defaults, not to the group or RG."
  }
  assert {
    condition = (
      data.azapi_resource_list.role_definitions[0].parent_id == var.parent_id &&
      azapi_resource.role_assignments["reader"].name == "11111111-1111-4111-8111-111111111111" &&
      endswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/acdd72a7-3385-48ef-bd42-f606fba81ae7") &&
      azapi_resource.role_assignments["reader"].body.properties.principalId == var.role_assignments.reader.principal_id &&
      azapi_resource.role_assignments["reader"].body.properties.principalType == "ServicePrincipal" &&
      azapi_resource.role_assignments["reader"].body.properties.description == "Child role" &&
      azapi_resource.role_assignments["reader"].body.properties.condition == var.role_assignments.reader.condition &&
      azapi_resource.role_assignments["reader"].body.properties.conditionVersion == "2.0" &&
      azapi_resource.role_assignments["reader"].body.properties.delegatedManagedIdentityResourceId == var.role_assignments.reader.delegated_managed_identity_resource_id
    )
    error_message = "Child role lookup, UUID, principal semantics and optional ARM property casing must be correct."
  }
  assert {
    condition = (
      azapi_resource.lock[0].type == var.resource_types.authorization_locks &&
      azapi_resource.role_assignments["reader"].type == var.resource_types.authorization_role_assignments &&
      data.azapi_resource_list.role_definitions[0].type == var.resource_types.authorization_role_definitions &&
      azapi_resource.this.retry.interval_seconds == 5 &&
      azapi_resource.lock[0].retry.interval_seconds == 5 &&
      azapi_resource.role_assignments["reader"].retry.max_interval_seconds == 20 &&
      azapi_resource.lock[0].timeouts.delete == "10m" &&
      azapi_resource.role_assignments["reader"].timeouts.create == "20m" &&
      length(azapi_resource.lock[0].response_export_values) == 0 &&
      length(azapi_resource.role_assignments["reader"].response_export_values) == 0
    )
    error_message = "Every child-owned resource must honor API overrides, retries, timeouts and narrow exports. Write-only ignore values are exercised but not readable from state."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "standalone_read_only_explicit_name_and_type" {
  command = apply
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    lock = { kind = "ReadOnly", name = "reservation-lock", notes = "Child custom notes" }
    role_assignments = {
      reader = {
        name                             = "33333333-3333-4333-8333-333333333333"
        role_definition_id_or_name       = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id                     = "22222222-2222-4222-8222-222222222222"
        principal_type                   = "Group"
        skip_service_principal_aad_check = true
      }
    }
  }
  assert {
    condition = (
      length(data.azapi_resource_list.role_definitions) == 0 &&
      azapi_resource.role_assignments["reader"].name == var.role_assignments.reader.name &&
      azapi_resource.role_assignments["reader"].body.properties.principalType == "Group" &&
      azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId == "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7" &&
      azapi_resource.lock[0].body.properties.level == "ReadOnly" &&
      azapi_resource.lock[0].body.properties.notes == "Child custom notes" &&
      azapi_resource.lock[0].name == "reservation-lock"
    )
    error_message = "Explicit child settings must win and tenant-level role IDs must normalize without lookup."
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_child_unknown_role" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    role_assignments = {
      reader = { role_definition_id_or_name = "Missing role", principal_id = "22222222-2222-4222-8222-222222222222" }
    }
  }
  expect_failures = [azapi_resource.role_assignments["reader"]]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_child_invalid_lock" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    lock = { kind = "Invalid" }
  }
  expect_failures = [var.lock]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_child_invalid_delegation" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name             = "Reader"
        principal_id                           = "22222222-2222-4222-8222-222222222222"
        delegated_managed_identity_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
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

run "rejects_child_invalid_principal_type" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = "22222222-2222-4222-8222-222222222222", principal_type = "Invalid" }
    }
  }
  expect_failures = [azapi_resource.role_assignments["reader"]]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}

run "rejects_child_duplicate_assignment_names" {
  command = plan
  module {
    source = "./modules/capacity_reservation"
  }
  variables {
    role_assignments = {
      first  = { name = "33333333-3333-4333-8333-333333333333", role_definition_id_or_name = "Reader", principal_id = "22222222-2222-4222-8222-222222222222" }
      second = { name = "33333333-3333-4333-8333-333333333333", role_definition_id_or_name = "Reader", principal_id = "44444444-4444-4444-8444-444444444444" }
    }
  }
  expect_failures = [azapi_resource.role_assignments]
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
