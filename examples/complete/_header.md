# Complete example

Combines an AzAPI resource group and identity with multiple parent-owned reservations, non-default zones/SKUs, resource-group RBAC/lock, individual reservation RBAC/lock, retries and timeouts.

`primary` fans out to one reservation per `reservation_zones` entry (two by default). Each gets one unit **per zone**, inherits `{ environment = "example" }`, and has its own reservation-scoped lock and Reader assignment. `replacement` uses another SKU in the first zone and replaces inherited tags with `{ workload = "explicit-replacement" }`. `untagged` uses a third SKU in that zone and explicitly clears tags with `{}`. No maps are merged. `vm_sizes` and `reservation_zones` let the operator select approved capacity rather than relying on fixed availability.

The defaults reserve **four VM slots** (D2s_v5 in two zones, D4s_v5 and D8s_v5 in one zone each); unused reserved capacity is billed. Choose one zone to reduce the demonstration to three slots. Distinct effective size/zone tuples are mandatory even when reservation names differ. Expanded output keys include `7:primary:zone-1`, `11:replacement:zone-1` and `8:untagged:zone-1`, plus the other primary zones.

**Deployment creates billable reserved compute capacity.** Obtain explicit subscription, isolated scope, quota, SKU/zone, cost and cleanup approval before deploying. It requires role-assignment and lock permissions; registrations are not performed by this example. This example has not been deployed as part of local refactoring.

The root lock protects the entire resource group, including the example identity. The child lock and child Reader assignment target only the reservation ARM ID. Parent-owned children (including their extensions) and root RBAC are ordered before the RG lock; the child lock follows child RBAC. Other independently managed resources need their own ordering. Selective replacement requires staged removal of all applicable locks, propagation wait and relock. Retry settings can help with propagation but do not prove teardown.

`resource_id` exposes the group ARM ID for opt-in consumption by an existing VM owner; `capacity_reservation_resource_ids` exposes a keyed map of child ARM IDs. No VM is created or modified here. See the root's association contract for the exact VM-side ARM property and the distinction from platform `reservationId`.
