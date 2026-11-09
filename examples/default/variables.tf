variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "The Azure region for this module's resources or telemetry deployment."
  nullable    = false
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "The subscription ID for the AzAPI provider. Null uses its normal authentication configuration."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v5"
  description = "Capacity-reservation-supported VM size with approved quota and capacity in the selected region/zone; verify live eligibility before deployment."
  nullable    = false
}

variable "zone" {
  type        = string
  default     = "1"
  description = "Approved logical zone used by both the group envelope and standalone single-reservation submodule."
  nullable    = false

  validation {
    condition     = contains(["1", "2", "3"], var.zone)
    error_message = "Choose one logical zone from 1, 2 and 3."
  }
}
