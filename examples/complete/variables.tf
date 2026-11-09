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
