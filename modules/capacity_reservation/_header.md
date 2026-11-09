# Capacity Reservation

Manages one capacity reservation using AzAPI. Supply the existing group ID in required `parent_id`. Cardinality belongs at the caller's module block, not inside this submodule.

## Optional reservation-scoped extensions

`lock` and `role_assignments` attach to this **reservation's ARM ID**, not the group or resource group. They work when called directly or through the root's `capacity_reservations` map. Defaults are null/empty; no lock, role assignment or role-name UUID is created when omitted. Existing telemetry defaults remain enabled; the composed interfaces utility adds its own subscription telemetry deployment unless `enable_telemetry = false`.

Role names resolve case-insensitively at the supplied group `parent_id`, without a lookup against the not-yet-created reservation. Fully qualified definition IDs bypass lookup; tenant-level definition IDs normalize to the parent subscription. Unknown names fail explicitly. `skip_service_principal_aad_check` maps to ServicePrincipal unless explicit `principal_type` wins; AzAPI does not perform AzureRM's separate directory check. Changing immutable assignment inputs requests replacement. Explicit names replace normally; there is no historical child AzureRM GUID to adopt or ignore.

```hcl
module "reservation" {
  source = "../../modules/capacity_reservation"

  parent_id                 = module.capacity_reservation_group.resource_id
  capacity_reservation_name = "standalone"
  location                  = "westeurope"
  sku                       = { name = "Standard_D2s_v5", capacity = 1 }
  zone                      = "1"
  lock                      = { kind = "CanNotDelete" }
  role_assignments = {
    reader = {
      role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
      principal_id               = "00000000-0000-0000-0000-000000000001" # Existing principal supplied by the consumer.
      principal_type             = "Group"
    }
  }
}
```

The relative source above assumes a caller at `examples/<name>` in this repository; use the appropriate submodule source for your caller. Do not also add that same reservation to the parent's map. If the caller manages a parent RG lock, order it after this entire module for creation and before module teardown. A child lock cannot relax an inherited lock. Selective replacement requires staged removal of **all applicable** CanNotDelete locks; ReadOnly requires staged removal before writes. Wait for propagation, perform the approved operation, converge, and relock. Terraform dependencies are not runtime propagation or update-time unlock guarantees.

The published authorization APIs support nested resource scopes, but child-specific Azure support/persistence and full/selective locked teardown remain untested pending authorization.

## Output and association identity

`resource_id` and `capacity_reservation_resource_id` are aliases for the **child ARM ID** (`.../capacityReservationGroups/<group>/capacityReservations/<reservation>`). `capacity_reservation_id` is the platform-generated **scalar** `properties.reservationId`; it is not an ARM ID. VM owners opt in with the **group ARM ID**, available from the root `resource_id`, not either child output. This submodule never writes VMs or the read-only association projections.

## Upgrade from v0.2.0

Requires Terraform 1.11+. Rename input `capacity_reservation_group_id` to `parent_id`, keeping the same ID and caller module address. The module-owned move from `azapi_resource.capacity_reservation` to `azapi_resource.this` preserves the state address relationship; Azure upgrade proof remains pending. Existing resource ID aliases, `name`, and the scalar `capacity_reservation_id` (ARM `properties.reservationId`) remain available. The response export is narrowed to the property used by that output. The computed reservation ID may be unknown during an update; do not use it as a stable plan-time key.

`resource_types`, `retry`, `timeouts` and `ignore_body_changes` apply to the reservation and both owned extensions. Ignore paths are body-relative dot notation; ignored values are not sent to Azure and changes take effect after apply. New lock/assignment addresses have no AzureRM migration sources; enabling them is an intentional addition, not conversion of released child resources.

`zone` is required with no default: supply one logical zone (`"1"`, `"2"` or `"3"`) or explicit `null` for regional capacity. The ARM body contains `zones = [var.zone]` only for a zonal reservation; regional requests omit `zones`, following the published regional create contract. Replace the old list-valued `zones` input with this single value and preserve the existing effective zone during upgrade. A reservation never spans three zones.

The standalone caller must match the existing group's location and regional/zonal envelope and ensure each size/zone tuple is unique across every reservation owner. This submodule performs no hidden group read. The root validates those properties for its own children and expands explicit SKU-definition zone lists.

`sku.capacity` must be a nonnegative integer. Zero is valid for the published resize-to-zero/disassociation workflow; it does not reserve useful capacity or prove zero-create acceptance. Capacity remains updateable; changing SKU name or zone requests replacement. Quota, live capacity and Targeted SKU eligibility remain service checks. Block reservations and their different quantity/update restrictions are not modeled.

Availability/quota, zero-create/resize persistence, collection behavior, externally associated VMs and locked replacement require separately authorized Azure tests. Do not infer persistence, released-state adoption or a safe rollback from mocks. See the root module's upgrade and lock guidance.
