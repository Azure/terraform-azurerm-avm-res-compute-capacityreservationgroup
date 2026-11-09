# Capacity Reservation Group

Manages an Azure Capacity Reservation Group, with a submodule for individual Capacity Reservations.

## Provider and scope

The implementation and examples use `Azure/azapi`; the target module has no AzureRM provider dependency. Configure providers in the calling root and pass the intended AzAPI instance to this module and any separately called reservation submodule. Terraform **1.11.0 or later** is required.

`subscription_id` is an optional assertion against the **AzAPI provider subscription**. Null or `""` skips the assertion; it does not select a subscription. Configure the provider separately. This differs from v0.2.0, which inspected AzureRM's independent provider context. The assertion is not a check that a cross-subscription `parent_id` matches the provider subscription.

For compatibility, `lock` and `role_assignments` remain scoped to the **resource group supplied in `parent_id`**, not to the capacity reservation group. They affect other resources in that resource group. This deliberately preserves released identities and RBAC reach rather than silently adopting the narrower scope illustrated by the canonical interface examples.

## Children and controls

Use `capacity_reservations` to compose single-instance reservation submodules with cardinality owned by this module, or continue to call `modules/capacity_reservation` separately. Do not manage the same reservation through both paths. Existing separately called submodules do not need to be relocated during this upgrade.

Each child supports optional `lock` and `role_assignments` scoped to the **individual reservation ARM ID**, available through both consumption paths. Child values default to null/empty; root values are not copied into them. Azure still inherits the root RG lock/RBAC at descendant scopes. A child lock cannot relax an inherited RG lock. Child extension support is based on the published scoped authorization operations; reservation-specific creation, persistence and locked teardown have not been Azure-tested for this candidate.

`resource_types`, `retry`, `timeouts` and `ignore_body_changes` expose AzAPI controls. Nested child slots are passed unchanged; defaults for child API versions belong to the child. Ignore paths are body-relative dot notation without list indices. Ignored configuration is not sent to Azure, and changes to this provider-private setting take effect only after apply.

The group writes sharing configuration, not the read-only `capacityReservations` or VM-association projections. Reservations have independent GET/PUT/DELETE operations. VM associations remain owned by the VM configuration.

An unset sharing profile omits `sharingProfile`; an explicit empty `subscription_ids` list remains an empty ARM list. Module request shape alone does not establish that clearing/shrinking persists in Azure.

## Opt-in VM association contract

`resource_id` and its alias `capacity_reservation_group_id` are the **group ARM ID** (`.../capacityReservationGroups/<group>`). The VM owner chooses whether to use that reference; this module accepts no VM IDs and creates no association resource or VM-property writer. Omitting the reference leaves the VM association unconfigured by this module.

The [Compute ARM 2024-11-01 specification](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/compute/resource-manager/Microsoft.Compute/Compute/stable/2024-11-01/ComputeRP.json) defines the VM-side writable path as `properties.capacityReservation.capacityReservationGroup.id`. The following is only the capacity-reservation fragment to compose into the **existing VM owner's** AzAPI body, not a standalone VM deployment or an assumed VM module input name:

```hcl
capacityReservation = {
  capacityReservationGroup = {
    id = module.capacity_reservation_group.resource_id
  }
}
```

Place that fragment inside the VM body's existing `properties`; preserve its other properties. When using a VM module, consult that module's exact versioned association interface and pass this group ARM ID through it. VM eligibility, reserved size/zone matching and association/dissociation lifecycle remain the VM owner's responsibility.

`capacity_reservation_resource_ids` is a **map of child ARM IDs**, keyed by the parent input keys. A directly consumed child exposes the same scalar ARM ID as `resource_id` and `capacity_reservation_resource_id`. The child `capacity_reservation_id` is a separate platform-generated scalar from `properties.reservationId`, **not** an ARM ID and **not** the VM association reference. Do not use it as a plan-time key.

## Upgrading from v0.2.0

This is a breaking **input/provider-context** change with module-owned state moves. Local mocks and validation do not establish an Azure-tested upgrade; released-state migration and fresh Azure E2E remain required before release.

1. Back up the existing protected state and dependency lock. Use the same backend/workspace and unchanged module instance addresses.
2. Upgrade Terraform to at least 1.11. Replace root input `resource_group_id` with `parent_id`. In separately called reservation submodules replace `capacity_reservation_group_id` with `parent_id`. Pass the same existing ARM IDs. Names, SKU, zones, sharing and scalar output aliases remain available.
3. Configure and pass the intended AzAPI provider. Remove AzureRM from target module provider mappings. A historical consumer may temporarily need its baseline AzureRM provider configuration while converting other state; do not remove a provider still required by unrelated resources.
4. Keep existing keys, names, scopes and child call addresses. Module-owned moves rename `azapi_resource.capacity_reservation_group` to `azapi_resource.this`, rename the child `azapi_resource.capacity_reservation` to `azapi_resource.this` within its existing module, and convert the old lock/role collections to `azapi_resource.lock` and `azapi_resource.role_assignments` without changing count/map keys.
5. Initialize, save and inspect a **normal refreshed** migration plan. Require unchanged ARM IDs, assignment GUIDs and lock names/notes, with no unintended deletes or replacements. New utility UUID state may be created; it must not replace an adopted assignment GUID. With telemetry enabled, the new interfaces utility also adds its own empty subscription deployment; classify that auxiliary Azure write separately, not as a state-only addition. The assignment's `name` is narrowly ignored for adoption; explicit name/input changes are tracked by replacement triggers.
6. Apply only the inspected plan after the appropriate authorization. Verify independent Azure readbacks, stable outputs and two normal refreshed infrastructure-no-op plans for sharing/normalization cases. Exercise telemetry enabled/disabled separately; explicitly classify only managed telemetry timestamp updates, never infrastructure drift. There is no one-time migration toggle for the standard moved path.

### Extension compatibility

- Lock defaults retain `lock-<kind>` and the released kind-specific notes. Optional `lock.notes` now accepts custom notes. Lock kind/notes changes retain replacement behavior.
- Role names resolve case-insensitively at the existing resource-group scope. Full definition IDs bypass the lookup. Tenant-level definition IDs are normalized to the parent subscription prefix. A missing role name fails explicitly.
- `skip_service_principal_aad_check = true` maps to ARM `principalType = "ServicePrincipal"` unless an explicit `principal_type` takes precedence, matching the old provider. AzAPI does not perform AzureRM's separate directory check.
- Optional role `name` is now supported for new assignments. Existing generated GUIDs are retained by the provider move and ignored-name lifecycle rule. Principal, definition, type, delegation, condition/version, description and explicit name changes request replacement; these operations require separate lock handling.
- `description` was accepted but not wired by v0.2.0. It is now sent to ARM. Consumers with a previously ignored non-null description must inspect the adoption plan and approve any resulting write; do not assume an entirely no-op upgrade.

### Exceptional state and locks

The standard move requires a normal ARM resource ID. AzureRM cross-tenant assignment IDs with a `|tenant` suffix are **not a supported automatic conversion** in the inspected AzAPI converter. Tenant-level role-definition normalization is unrelated. Do not attempt the standard upgrade for these bindings without a separately reviewed, identity-preserving removal/import path at the exact nested consumer address, provider tenant context and pinned API version. No such exceptional path has been Azure-tested here.

For existing `ReadOnly` locks, stage lock removal through the released configuration before migration writes; reapply the lock only after convergence. For parent replacement or selective child/RBAC replacement under `CanNotDelete`, explicitly stage unlock, the intended operation, and relock. A full-destroy dependency graph does not unlock an unchanged lock for updates. Lock deletion propagation may require consumer retry patterns such as `ScopeLocked`; graph ordering alone does not prove Azure cleanup.

The new child collection is optional. Moving existing external child calls into it is a separate address migration requiring explicit consumer moves; this release does not provide a wildcard move across arbitrary caller module addresses. Keep those calls in place for the standard upgrade.

Child extension addresses are new: within each reservation module, `azapi_resource.lock[0]`, `azapi_resource.role_assignments["<key>"]`, and utility `module.avm_interfaces.random_uuid.role_assignment_name["<key>"]`. They have no historical AzureRM move sources. Null/empty child interfaces create no extension or role-UUID resources. With telemetry enabled (the existing default), the newly composed utility additionally creates its own subscription telemetry deployment even without extensions; inspect that separately. No existing root assignment GUID lifecycle was changed by these additions.

Creation orders each child before its roles, then its lock; the root RG lock depends on the complete child modules. Full destroy reverses those dependencies, but does not prove Azure lock-deletion propagation or unlock for selective replacement. For selective child/role replacement, remove all applicable CanNotDelete locks in a separate approved apply, wait for propagation, perform the intended operation, then relock. Stage removal of applicable ReadOnly locks before any PUT/migration, and restore them only after convergence. For independently consumed children, the caller owns ordering of any separately managed parent RG lock; do not make the child depend on that lock and create a cycle.

After provider/state conversion, reverting code alone is not a proven rollback. Preserve protected baseline state and provider resolutions; reconcile live Azure changes before any reviewed recovery. Never restore an old state backup blindly after mutations.

### Earlier upgrade history

For upgrades from versions before v0.2.0, remove unsupported template inputs `customer_managed_key`, `diagnostic_settings`, `managed_identities`, `private_endpoints`, and `private_endpoints_manage_dns_zone_group`. These inputs never configured Capacity Reservation resources. This historical removal is distinct from the current input renames and provider conversion.
