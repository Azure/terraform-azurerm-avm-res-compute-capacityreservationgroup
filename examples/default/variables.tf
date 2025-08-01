variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}

# subscription ID for azurerm provider
# variable "subscription_id" {
#   type        = string
#   description = "The subscription ID to use for the azurerm provider."
#   default     = ""
# }