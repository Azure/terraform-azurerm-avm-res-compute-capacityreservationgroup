# Complete example

Combines an AzAPI resource group and identity with a parent-owned reservation, tags, non-default zones/SKU, resource-group RBAC/lock, individual reservation RBAC/lock, retries and timeouts.

**Deployment creates billable reserved compute capacity.** Obtain explicit subscription, isolated scope, quota, SKU/zone, cost and cleanup approval before deploying. It requires role-assignment and lock permissions; registrations are not performed by this example. This example has not been deployed as part of local refactoring.

The root lock protects the entire resource group, including the example identity. The child lock and child Reader assignment target only the reservation ARM ID. Parent-owned children (including their extensions) and root RBAC are ordered before the RG lock; the child lock follows child RBAC. Other independently managed resources need their own ordering. Selective replacement requires staged removal of all applicable locks, propagation wait and relock. Retry settings can help with propagation but do not prove teardown.

`resource_id` exposes the group ARM ID for opt-in consumption by an existing VM owner; `capacity_reservation_resource_ids` exposes a keyed map of child ARM IDs. No VM is created or modified here. See the root's association contract for the exact VM-side ARM property and the distinction from platform `reservationId`.
