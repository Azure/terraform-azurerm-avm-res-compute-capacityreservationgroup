variable "capacity_reservation_name" {
  type        = string
  description = "The name of the capacity reservation."
}

variable "location" {
  type        = string
  description = "The location where the capacity reservation will be created."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "The fully-qualified ARM resource ID of the existing capacity reservation group."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Compute/capacityReservationGroups", var.parent_id))
    error_message = "`parent_id` must be a valid capacity reservation group resource ID."
  }
}

variable "sku" {
  type = object({
    capacity = number
    name     = string
    tier     = optional(string, "")
  })
  description = "The SKU information for the capacity reservation."
  nullable    = false

  validation {
    condition     = try(var.sku.capacity >= 0 && var.sku.capacity == floor(var.sku.capacity), false)
    error_message = "sku.capacity must be a nonnegative whole number. Zero supports resizing down; quota and capacity are checked by Azure."
  }
  validation {
    condition     = try(trimspace(var.sku.name) != "", false)
    error_message = "sku.name must be a nonempty VM size name. Check live SKU eligibility in the target region."
  }
  validation {
    condition = (
      var.sku.tier == "" || var.sku.tier == "Standard" || var.sku.tier == "Basic"
    )
    error_message = "If specified, 'tier' must be either 'Standard' or 'Basic'."
  }
}

variable "zone" {
  type        = string
  description = "Required single logical availability zone (1, 2 or 3), or explicit null for regional capacity (zones omitted from ARM). No default. The caller must match the existing group's location and regional/zonal envelope; this submodule does not read remote group properties."

  validation {
    condition     = var.zone == null ? true : contains(["1", "2", "3"], var.zone)
    error_message = "zone must be one logical zone from 1, 2 or 3, or explicit null for a regional reservation."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}
