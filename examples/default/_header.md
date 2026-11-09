# Default example

This deploys the module in its simplest form.

The standalone reservation explicitly receives one `zone`, also passed as the group envelope. Choose an approved `vm_size`, `zone` and `location`; the example default is one `Standard_D2s_v5` slot, not the former B-series selection. Reserved capacity is billable even when unused. When upgrading an already-applied older example, explicitly preserve its actual size/zone rather than accepting changed example defaults as a nondestructive upgrade.

All direct Azure scaffolding uses AzAPI. If upgrading an already-applied v0.2.0 example in the same state, the example includes a move from its old AzureRM resource group binding to the AzAPI binding. Inspect the saved refreshed plan and preserve the resource group ID; do not approve a resource group deletion/replacement. This path remains untested against Azure.
