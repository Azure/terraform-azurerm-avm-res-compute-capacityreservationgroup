variable "child_principal" {
  type    = string
  default = "22222222-2222-4222-8222-222222222222"
}

variable "child_role" {
  type    = string
  default = "Reader"
}

variable "dependency" {
  type    = string
  default = "before"
}

variable "parent_id" {
  type    = string
  default = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "The offline fixture parent_id must be a valid resource group ARM ID."
  }
}

variable "principal" {
  type    = string
  default = "22222222-2222-4222-8222-222222222222"
}

variable "role" {
  type    = string
  default = "Reader"
}
