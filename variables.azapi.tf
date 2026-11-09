variable "ignore_body_changes" {
  type = object({
    compute_capacity_reservation_groups = optional(list(string), [])
    authorization_locks                 = optional(list(string), [])
    authorization_role_assignments      = optional(list(string), [])
    compute_capacity_reservation_groups_capacity_reservations = optional(object({
      authorization_locks                                       = optional(list(string), [])
      authorization_role_assignments                            = optional(list(string), [])
      compute_capacity_reservation_groups_capacity_reservations = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Body-relative dot-notation paths to ignore. Ignored configuration is not sent to Azure until the path is removed. Changes take effect only after apply; individual list indices are unsupported.

- `compute_capacity_reservation_groups` - Paths ignored on the group.
- `authorization_locks` - Paths ignored on the resource group lock.
- `authorization_role_assignments` - Paths ignored on resource group role assignments.
- `compute_capacity_reservation_groups_capacity_reservations` - Child-shaped controls passed unchanged to reservation submodules.
- `compute_capacity_reservation_groups_capacity_reservations.compute_capacity_reservation_groups_capacity_reservations` - Paths ignored on reservations.
- `compute_capacity_reservation_groups_capacity_reservations.authorization_locks` - Paths ignored on reservation-scoped locks.
- `compute_capacity_reservation_groups_capacity_reservations.authorization_role_assignments` - Paths ignored on reservation-scoped assignments.
DESCRIPTION
  nullable    = false
}

variable "resource_types" {
  type = object({
    compute_capacity_reservation_groups = optional(string, "Microsoft.Compute/capacityReservationGroups@2024-11-01")
    authorization_locks                 = optional(string, "Microsoft.Authorization/locks@2020-05-01")
    authorization_role_assignments      = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")
    authorization_role_definitions      = optional(string, "Microsoft.Authorization/roleDefinitions@2022-04-01")
    compute_capacity_reservation_groups_capacity_reservations = optional(object({
      authorization_locks                                       = optional(string)
      authorization_role_assignments                            = optional(string)
      authorization_role_definitions                            = optional(string)
      compute_capacity_reservation_groups_capacity_reservations = optional(string)
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource types and API versions.

- `compute_capacity_reservation_groups` - Capacity reservation group type and API version.
- `authorization_locks` - Resource group lock type and API version.
- `authorization_role_assignments` - Resource group role assignment type and API version.
- `authorization_role_definitions` - Role definition lookup type and API version.
- `compute_capacity_reservation_groups_capacity_reservations` - Controls passed unchanged to capacity reservation submodules.
- `compute_capacity_reservation_groups_capacity_reservations.compute_capacity_reservation_groups_capacity_reservations` - Child resource type and API version override; the child owns the default.
- `compute_capacity_reservation_groups_capacity_reservations.authorization_locks` - Reservation-scoped lock type override; the child owns the default.
- `compute_capacity_reservation_groups_capacity_reservations.authorization_role_assignments` - Reservation-scoped assignment type override; the child owns the default.
- `compute_capacity_reservation_groups_capacity_reservations.authorization_role_definitions` - Child role definition lookup type override; the child owns the default.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string))
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
  })
  default     = null
  description = <<DESCRIPTION
Retry configuration for supported AzAPI resources and applicable submodules. Null uses provider defaults.

- `error_message_regex` - Error patterns that trigger retries; for lock propagation consider ScopeLocked.
- `interval_seconds` - Initial retry interval in seconds.
- `max_interval_seconds` - Maximum retry interval in seconds.
DESCRIPTION
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = null
  description = <<DESCRIPTION
Operation timeouts for supported AzAPI resources and applicable submodules. Null uses provider defaults. Values are Go durations.

- `create` - Create timeout.
- `read` - Read timeout.
- `update` - Update timeout.
- `delete` - Delete timeout.
DESCRIPTION
}
