locals {
  role_definition_resource_substring = "/providers/microsoft.authorization/roledefinitions/"
  role_definition_lookup_enabled = anytrue([
    for assignment in var.role_assignments :
    !strcontains(lower(assignment.role_definition_id_or_name), local.role_definition_resource_substring)
  ])
  role_definition_ids_by_name = local.role_definition_lookup_enabled ? {
    for role in data.azapi_resource_list.role_definitions[0].output.value :
    lower(role.properties.roleName) => role.id
  } : {}
  role_definition_ids = {
    for key, assignment in var.role_assignments : key => (
      strcontains(lower(assignment.role_definition_id_or_name), local.role_definition_resource_substring) ?
      (startswith(lower(assignment.role_definition_id_or_name), "/providers/") ?
        "/subscriptions/${provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id).subscription_id}${assignment.role_definition_id_or_name}" :
      assignment.role_definition_id_or_name) :
      lookup(local.role_definition_ids_by_name, lower(assignment.role_definition_id_or_name), null)
    )
  }
  role_assignments = {
    for key, assignment in var.role_assignments : key => merge(assignment, {
      role_definition_id_or_name = coalesce(local.role_definition_ids[key], assignment.role_definition_id_or_name)
      principal_type             = assignment.principal_type != null ? assignment.principal_type : (assignment.skip_service_principal_aad_check ? "ServicePrincipal" : null)
    })
  }
  lock = var.lock == null ? null : merge(var.lock, {
    name  = coalesce(var.lock.name, "lock-${var.lock.kind}")
    notes = coalesce(var.lock.notes, var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources.")
  })
}
