variable "capacity_reservation_enabled" {
  type        = bool
  default     = true
  description = "Explicit VM-owner opt-in to consuming the group ARM ID. False sends id = null to disassociate; it does NOT remove or stop billing the reservation. Follow the staged disassociation contract before changing an allocated VM."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Enable AVM telemetry."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Approved region with quota, capacity and the selected VM image/size/zone available."
  nullable    = false
}

variable "reservation_capacity" {
  type        = number
  default     = 1
  description = "Reserved VM quantity, normally one for this single-VM test. Zero is available for the documented staged disassociation workflow, not a capacity guarantee."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  default     = "capacity-reservation-vm-example"
  description = "Unique name for an isolated example resource group."
  nullable    = false
}

variable "ssh_public_key" {
  type        = string
  default     = null
  description = "Optional real RSA SSH public key (at least 2048 bits). Null generates a throwaway 3072-bit RSA key through Azure; only the public key is exported to state and the private key is deliberately discarded. No password or placeholder credential is used."
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "AzAPI subscription; null uses normal provider authentication configuration (CLI or ARM_* / OIDC)."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v5"
  description = "CapacityReservationSupported VM size compatible with the x64 Gen2 Ubuntu image and Trusted Launch; used identically by VM and reservation. Verify live region/zone eligibility and quota before applying."
  nullable    = false
}

variable "zone" {
  type        = string
  default     = "1"
  description = "Explicit example zone, shared by VM, group envelope and reservation. Override for the approved target. This is an example selection, not a reusable child-module default."
  nullable    = false

  validation {
    condition     = contains(["1", "2", "3"], var.zone)
    error_message = "Choose one logical zone from 1, 2 and 3."
  }
}
