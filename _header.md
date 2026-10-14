# Capacity Reservation Group

Manages an Azure Capacity Reservation Group, with a submodule for individual Capacity Reservations.

## Upgrading

Configure providers in the calling Terraform root and pass the intended provider instances to the module. `subscription_id` remains an optional safety check: when supplied, it must match the caller's AzureRM provider subscription. It no longer configures a provider inside the module. This check reads AzureRM's own client configuration; AzAPI cannot inspect another provider's subscription.

Remove the unsupported template inputs `customer_managed_key`, `diagnostic_settings`, `managed_identities`, `private_endpoints`, and `private_endpoints_manage_dns_zone_group` from existing calls. These inputs never configured Capacity Reservation resources. Existing resource addresses, outputs, and resource-group-scoped locks and role assignments are unchanged.
