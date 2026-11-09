variable "capacity_reservations" {
  type = map(object({
    name = string
    sku = object({
      capacity = number
      name     = string
      tier     = optional(string, "")
    })
    zones = list(string)
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
Logical SKU definitions expanded into single-instance reservation submodules. Defaults to no children. Do not also manage these objects through separate module calls.

- `name` - Consumer-supplied name prefix. Each Azure name is `<name>-z<zone>` or `<name>-regional`, and must be unique case-insensitively and at most 80 characters.
- `sku` - Required nonnegative integer capacity PER ZONE and VM size name, with optional tier (empty, Standard or Basic). Zero supports resizing down; quota and live capacity remain Azure checks.
- `zones` - Required explicit list of distinct logical zones (1, 2 or 3), each within the group envelope. An empty list creates ONE regional reservation and requires a regional group (`zones = []`).
- `tags` - Complete per-child tag override; null inherits module tags.
- `lock` - Optional reservation-scoped lock with required `kind` (CanNotDelete or ReadOnly), optional `name` (defaults to lock-<kind>) and optional `notes`.
- `role_assignments` - Reservation-scoped assignments keyed by stable consumer keys. Each accepts optional `name` (otherwise random UUID), required `role_definition_id_or_name` and `principal_id`, optional `description`, `skip_service_principal_aad_check` (false), `condition`, `condition_version`, `delegated_managed_identity_resource_id` and `principal_type`. See the submodule's canonical interface descriptions.

Child extensions default to null/empty and do not inherit root interface values. The root RG lock/RBAC still apply through Azure scope inheritance.

Existing separately called reservation submodules need not move into this collection during upgrade.

Expanded keys are `<length-of-definition-key>:<definition-key>:zone-<zone>` or `<length-of-definition-key>:<definition-key>:regional`. The length prefix avoids delimiter collisions. Zone ordering never changes keys. Each effective VM-size/zone tuple must be unique across definitions regardless of names. Multiple appliances share the reserved quantity, not separate same-size/same-zone reservations.
DESCRIPTION
  nullable    = false

  validation {
    condition = length(distinct(flatten([
      for reservation in var.capacity_reservations : [
        for zone in(try(length(reservation.zones), 0) == 0 ? [null] : distinct(reservation.zones)) :
        lower("${reservation.name}-${zone == null ? "regional" : "z${zone}"}")
      ]
    ]))) == sum(concat([0], [for reservation in var.capacity_reservations : max(1, try(length(distinct(reservation.zones)), 0))]))
    error_message = "Expanded capacity reservation names must be unique within the group (case-insensitive). Choose distinct name prefixes."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      try(can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", reservation.name)) && length(reservation.name) <= (length(reservation.zones) == 0 ? 71 : 77), false)
    ])
    error_message = "Each expanded reservation name must be at most 80 characters, use letters, numbers, underscores, periods or hyphens, and start/end with a letter, number or underscore."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      try(reservation.sku.capacity >= 0 && reservation.sku.capacity == floor(reservation.sku.capacity), false)
    ])
    error_message = "Each capacity_reservations[*].sku.capacity must be a nonnegative whole number; zero is supported for resizing."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      try(trimspace(reservation.sku.name) != "" && contains(["", "Standard", "Basic"], reservation.sku.tier), false)
    ])
    error_message = "Each SKU needs a nonempty VM size name and tier must be empty, Standard or Basic. Check live SKU eligibility in the target region."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      try(length(distinct(reservation.zones)) == length(reservation.zones) && alltrue([for zone in reservation.zones : contains(["1", "2", "3"], zone)]), false)
    ])
    error_message = "Each definition must explicitly supply zones = [] for regional capacity or distinct logical zones from 1, 2 and 3. Duplicate zones are not allowed."
  }
  validation {
    condition = alltrue([
      for reservation in var.capacity_reservations :
      try(length(reservation.zones) == 0 ? length(var.zones) == 0 : length(var.zones) > 0 && alltrue([for zone in reservation.zones : contains(var.zones, zone)]), false)
    ])
    error_message = "Reservation zones must match the group envelope: regional definitions require group zones = []; zonal definitions must be a subset of nonempty group zones."
  }
  validation {
    condition = length(distinct(flatten([
      for reservation in var.capacity_reservations : [
        for zone in(try(length(reservation.zones), 0) == 0 ? [null] : distinct(reservation.zones)) :
        jsonencode([lower(reservation.sku.name), zone])
      ]
    ]))) == sum(concat([0], [for reservation in var.capacity_reservations : max(1, try(length(distinct(reservation.zones)), 0))]))
    error_message = "Only one reservation per effective VM size/zone (or size regionally) is allowed in a group, regardless of reservation names. Combine appliance quantities instead."
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
