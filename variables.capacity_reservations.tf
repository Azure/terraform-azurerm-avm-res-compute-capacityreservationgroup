variable "capacity_reservations" {
  type = map(object({
    name = string
    sku = object({
      capacity = number
      name     = string
      tier     = optional(string, "")
    })
    zones = optional(list(string), ["1", "2", "3"])
    tags  = optional(map(string))
    lock = optional(object({
      kind  = string
      name  = optional(string, null)
      notes = optional(string, null)
    }))
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
  }))
  default     = {}
  description = <<DESCRIPTION
Capacity reservations managed through the local single-instance submodule, keyed by stable consumer keys. Defaults to no children. Do not also manage these objects through separate module calls.

- `name` - Reservation name; unique within the group.
- `sku` - Required capacity and VM size name, with optional tier (empty, Standard or Basic).
- `zones` - Reservation availability zones.
- `tags` - Complete per-child tag override; null inherits module tags.
- `lock` - Optional reservation-scoped lock with required `kind` (CanNotDelete or ReadOnly), optional `name` (defaults to lock-<kind>) and optional `notes`.
- `role_assignments` - Reservation-scoped assignments keyed by stable consumer keys. Each accepts optional `name` (otherwise random UUID), required `role_definition_id_or_name` and `principal_id`, optional `description`, `skip_service_principal_aad_check` (false), `condition`, `condition_version`, `delegated_managed_identity_resource_id` and `principal_type`. See the submodule's canonical interface descriptions.

Child extensions default to null/empty and do not inherit root interface values. The root RG lock/RBAC still apply through Azure scope inheritance.

Existing separately called reservation submodules need not move into this collection during upgrade.
DESCRIPTION
  nullable    = false

  validation {
    condition     = length(distinct([for reservation in var.capacity_reservations : lower(reservation.name)])) == length(var.capacity_reservations)
    error_message = "Capacity reservation names must be unique within the group."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      reservation.lock == null ? true : contains(["CanNotDelete", "ReadOnly"], reservation.lock.kind)
    ])
    error_message = "Each capacity_reservations[*].lock.kind must be CanNotDelete or ReadOnly."
  }
  validation {
    condition = alltrue(flatten([
      for reservation in var.capacity_reservations : [
        for assignment in reservation.role_assignments :
        assignment.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", assignment.delegated_managed_identity_resource_id))
      ]
    ]))
    error_message = "Each capacity_reservations[*].role_assignments[*].delegated_managed_identity_resource_id must be a valid user-assigned managed identity resource ID, or null."
  }
}
