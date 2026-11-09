variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Whether to enable AVM telemetry for this example."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Region with approved capacity reservation quota and the selected SKU/zone available."
  nullable    = false
}

variable "reservation_zones" {
  type        = list(string)
  default     = ["1", "2"]
  description = "Approved distinct zones for primary fan-out and the group envelope. Secondary definitions use the first zone. Quantity is one PER ZONE."
  nullable    = false

  validation {
    condition     = length(var.reservation_zones) > 0 && length(distinct(var.reservation_zones)) == length(var.reservation_zones) && alltrue([for zone in var.reservation_zones : contains(["1", "2", "3"], zone)])
    error_message = "Choose one or more distinct zones from 1, 2 and 3."
  }
}

variable "resource_group_name" {
  type        = string
  default     = "capacity-reservation-complete-example"
  description = "Unique name for an isolated example resource group."
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "AzAPI subscription; null uses normal provider authentication configuration."
}

variable "vm_sizes" {
  type = object({
    primary     = string
    replacement = string
    untagged    = string
  })
  default = {
    primary     = "Standard_D2s_v5"
    replacement = "Standard_D4s_v5"
    untagged    = "Standard_D8s_v5"
  }
  description = "Three distinct capacity-reservation-supported VM sizes with approved quota in the chosen region/zones. Defaults reserve four VM slots across two zones; unused capacity is billed."
  nullable    = false
}
