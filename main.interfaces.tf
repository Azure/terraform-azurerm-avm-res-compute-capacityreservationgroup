data "azapi_resource_list" "role_definitions" {
  count = local.role_definition_lookup_enabled ? 1 : 0

  parent_id              = var.parent_id
  type                   = var.resource_types.authorization_role_definitions
  response_export_values = ["value"]
}

module "avm_interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.10.0"

  enable_telemetry                          = var.enable_telemetry
  location                                  = var.location
  lock                                      = local.lock
  role_assignment_definition_lookup_enabled = false
  role_assignments                          = local.role_assignments
}

# Freeze the first accepted inputs, not the utility UUID: an adopted assignment
# may have a different GUID. Same-key edits must not delete it then reuse its name.
resource "terraform_data" "role_assignment_identity" {
  for_each = var.role_assignments

  input = local.role_assignment_identities[each.key]

  lifecycle {
    ignore_changes = [input]
  }
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name                 = module.avm_interfaces.role_assignments_azapi[each.key].name
  parent_id            = var.parent_id
  type                 = var.resource_types.authorization_role_assignments
  body                 = module.avm_interfaces.role_assignments_azapi[each.key].body
  ignore_body_changes  = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  ignore_casing        = true
  ignore_null_property = true
  replace_triggers_external_values = {
    name         = each.value.name
    principal_id = lower(each.value.principal_id)
    # Configured names remain known when module depends_on defers the lookup.
    # An old guard retains its already-stored trigger value to avoid replacing
    # an unchanged pre-release grant just to change the trigger representation.
    role_definition_id                     = can(terraform_data.role_assignment_identity[each.key].input.role_definition_id_or_name) ? lower(each.value.role_definition_id_or_name) : terraform_data.role_assignment_identity[each.key].input.role_definition_id
    principal_type                         = local.role_assignments[each.key].principal_type
    delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
    condition                              = each.value.condition
    condition_version                      = each.value.condition_version
    description                            = each.value.description
  }
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    # Keep AzureRM's server-bound GUID after conversion; edits require staged recreation.
    ignore_changes = [name]
    precondition {
      condition = can(terraform_data.role_assignment_identity[each.key].input.role_definition_id_or_name) ? (
        terraform_data.role_assignment_identity[each.key].input == local.role_assignment_identities[each.key]
        ) : (
        { for field, value in terraform_data.role_assignment_identity[each.key].input : field => value if field != "role_definition_id" } == local.role_assignment_non_role_identities[each.key] &&
        terraform_data.role_assignment_identity[each.key].input.role_definition_id == lower(coalesce(local.role_definition_ids[each.key], "unresolved"))
      )
      error_message = "Role assignment inputs cannot change under an existing key. Stage removal of applicable locks, remove this assignment key and apply, then re-add it with the new inputs and a fresh explicit GUID (or omit name). See the README staged RBAC recreation procedure."
    }
    precondition {
      condition     = local.role_definition_ids[each.key] != null && can(provider::azapi::parse_resource_id("Microsoft.Authorization/roleDefinitions", local.role_definition_ids[each.key]))
      error_message = "The role definition name was not found at parent_id. Supply an existing role name or a fully-qualified role definition ID."
    }
    precondition {
      condition     = each.value.principal_type == null ? true : contains(["User", "Group", "ServicePrincipal"], each.value.principal_type)
      error_message = "principal_type must be User, Group or ServicePrincipal."
    }
    precondition {
      condition     = length(distinct([for assignment in var.role_assignments : lower(assignment.name) if assignment.name != null])) == length([for assignment in var.role_assignments : assignment.name if assignment.name != null])
      error_message = "Explicit role assignment names must be unique within parent_id."
    }
  }
  depends_on = [azapi_resource.this]
}

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name                   = module.avm_interfaces.lock_azapi.name
  parent_id              = var.parent_id
  type                   = var.resource_types.authorization_locks
  body                   = module.avm_interfaces.lock_azapi.body
  ignore_body_changes    = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
  replace_triggers_refs  = ["properties.level", "properties.notes"]
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  depends_on = [azapi_resource.this, azapi_resource.role_assignments, module.capacity_reservation]
}
