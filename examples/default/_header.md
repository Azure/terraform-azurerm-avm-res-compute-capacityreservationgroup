# Default example

This deploys the module in its simplest form.

All direct Azure scaffolding uses AzAPI. If upgrading an already-applied v0.2.0 example in the same state, the example includes a move from its old AzureRM resource group binding to the AzAPI binding. Inspect the saved refreshed plan and preserve the resource group ID; do not approve a resource group deletion/replacement. This path remains untested against Azure.
