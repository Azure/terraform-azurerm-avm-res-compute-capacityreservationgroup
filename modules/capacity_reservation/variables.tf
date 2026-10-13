variable "capacity_reservation_group_id" {
  type        = string
  description = "The ID of the capacity reservation group."
}

variable "capacity_reservation_name" {
  type        = string
  description = "The name of the capacity reservation."
}

variable "location" {
  type        = string
  description = "The location where the capacity reservation will be created."
  nullable    = false
}

variable "sku" {
  type = object({
    capacity = number
    name     = string
    tier     = optional(string, "")
  })
  description = "The SKU information for the capacity reservation."

  validation {
    condition = (
      var.sku.tier == "" || var.sku.tier == "Standard" || var.sku.tier == "Basic"
    )
    error_message = "If specified, 'tier' must be either 'Standard' or 'Basic'."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}

variable "zones" {
  type        = list(string)
  default     = ["1", "2", "3"]
  description = "The availability zones for the capacity reservation."
}
