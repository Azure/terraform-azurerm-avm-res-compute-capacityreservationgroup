# VM consumption E2E example

An executable, directly discovered `examples/*` scenario: one reservation and one matching Linux VM. Every authored Azure resource and operation uses AzAPI; no extra provider or large VM module dependency is introduced. This example explicitly opts in by default with `capacity_reservation_enabled = true`. The reusable reservation module never owns VM associations.

## Approval, eligibility and cost

**Do not apply without separate Azure scope/cost/cleanup approval.** Authenticate with Azure CLI or supported `ARM_*`/OIDC configuration and choose an isolated `resource_group_name`. The selected subscription must already have the required providers registered. No registrations are performed.

The VM and reservation share `vm_size`, `location` and `zone`; the group envelope contains that same zone. Defaults select `Standard_D2s_v5`, zone `1`, and the Canonical `0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest` x64 Gen2 image with Trusted Launch. Verify image availability, `CapacityReservationSupported`, Targeted capacity support, Trusted Launch eligibility, subscription restrictions, regional/VM-family quota and available capacity in the approved region/zone. The example is not a runtime eligibility lookup and does not guarantee current capacity. Configure a compatible approved SKU rather than assuming every SKU works.

One reserved VM slot is billed even when unused. The VM also incurs Premium LRS OS-disk and applicable compute charges; capacity-reservation allocation avoids double charging the matching consumed reservation, not all VM costs. Premium storage satisfies the managed resiliency policy without a policy exception. Disabling association does **not** release the reservation or stop its billing.

## Authentication and exposure

Password authentication is disabled. Supply a real `ssh_public_key` if access is needed. With null (the noninteractive default), Azure's `sshPublicKeys/generateKeyPair` POST creates a genuine 3072-bit RSA pair. Only `publicKey` is exported by the AzAPI action; the returned private key is discarded, never an output or committed credential. This intentionally creates no usable operator login credential. Do not enable HTTP/debug logging that could capture the raw secret-bearing action response; protect state and plan artifacts regardless. There is no TLS/private-key Terraform provider.

The VM has no public IP, no default outbound Internet access, and an NSG explicitly denying all inbound traffic. It uses managed boot diagnostics, secure boot and vTPM. This is an allocation/lifecycle test, not a guest connectivity or application test.

## Ownership, opt-out and teardown

The **VM resource** writes `properties.capacityReservation.capacityReservationGroup.id` using the **group ARM ID**. It never uses a child ARM ID or the platform `reservationId`. An explicit module dependency waits for the reservation, not merely its container. The reverse dependency keeps the reservation until VM deletion completes; the OS disk uses `deleteOption = "Delete"` and Terraform separately deletes the detached NIC/network.

For a **fresh unassociated VM**, set `capacity_reservation_enabled = false`. The VM request explicitly sends `id = null`, as documented by Azure, rather than relying on omission to clear an existing association. For an **already allocated VM**, do not simply flip the switch and assume an in-place update works:

1. With separately approved scope, deallocate the VM and wait for completion; then apply `capacity_reservation_enabled = false`, verify an independent VM readback and normal refreshed plan, and optionally restart it.
2. Alternatively, first apply `reservation_capacity = 0` while association remains enabled, verify the reservation readback, then disable association in a **second** apply. This relinquishes guaranteed capacity and can affect every VM sharing that reservation.
3. Full `terraform destroy` deletes the VM first; Azure removes its association after deletion. Allocation projection latency can still affect reservation deletion and must be investigated, not hidden by broad cleanup.

No updater, second VM writer, deallocation action or subscription mutation runs automatically. Changing name/size/zone requires deliberate migration/replacement planning. Do not remove the module dependency or reservation independently while the VM is associated.

## Managed checks

`avm test e2e --list` discovers `vm_consumption`; after approval use `avm test e2e --example vm_consumption` for apply, idempotency and destroy. Defaults require no interactive credential variable or placeholder value, so policy-plan discovery remains noninteractive. Local mock/validate/policy results do **not** establish deployed E2E, persistence, toggle or teardown success. No Azure deployment has been run for this candidate.

Sources: [Compute 2024-11-01 API](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/compute/resource-manager/Microsoft.Compute/Compute/stable/2024-11-01/ComputeRP.json), [associate a VM](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-associate-vm), [remove a VM association / zero quantity](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-remove-vm).
