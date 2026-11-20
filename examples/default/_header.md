# Default example

This deploys the module in its simplest form.

The resource group uses the naming module's `resource_group.name_unique`, including its state-stable random suffix. The regions utility reads live subscription location data and filters to recommended regions with availability zones; a random index selects the deployment region. `location` is the utility's telemetry location, not a deployment-region override. Live data changes can change that index's effective region; inspect existing-state plans for replacement before applying.

The standalone reservation explicitly receives one `zone`, also passed as the group envelope. Choose an approved `vm_size` and `zone`; the example default is one fixed `Standard_D2s_v5` slot, not a randomly selected SKU. The region filters do not check compute SKU restrictions, quota, selected-zone support or available capacity. Use the complete example with an explicit approved location when a fixed target is required. Reserved capacity is billable even when unused. When upgrading an already-applied older example, explicitly preserve its actual size/zone rather than accepting changed example defaults as a nondestructive upgrade.

Group and standalone-reservation operations retry only the nested-resource deletion message, with an initial 15-second interval, a 60-second maximum interval and a 10-minute delete timeout. This accommodates propagation delays, not persistent child resources or failed-create orphans outside Terraform state. Those require inspection and scoped recovery; retries do not prove cleanup.

All direct Azure scaffolding uses AzAPI. If upgrading an already-applied v0.2.0 example in the same state, the example includes a move from its old AzureRM resource group binding to the AzAPI binding. Inspect the saved refreshed plan and preserve the resource group ID; do not approve a resource group deletion/replacement. This path remains untested against Azure.
