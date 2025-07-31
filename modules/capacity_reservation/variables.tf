variable "capacity_reservation_name" {
  description = "The name of the capacity reservation."
  type        = string
}

variable "capacity_reservation_group_id" {
  description = "The ID of the capacity reservation group."
  type        = string
}

variable "location" {
  description = "The location where the capacity reservation will be created."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the capacity reservation."
  type        = map(string)
}

variable "sku" {
  description = "The SKU information for the capacity reservation."
  type = object({
    capacity = number
    name     = string
    tier     = optional(string, "")
  })

  validation {
    condition = (
      var.sku.tier == "" || var.sku.tier == "Standard" || var.sku.tier == "Basic"
    )
    error_message = "If specified, 'tier' must be either 'Standard' or 'Basic'."
  }
}


variable "zones" {
  description = "The availability zones for the capacity reservation."
  type        = list(string)
  default     = ["1", "2", "3"]
}
