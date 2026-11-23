# Offline role assignment dependency regression

Run from the repository root with the managed Terraform executable:

```powershell
./tests/Test-RoleAssignmentDependency.ps1 -TerraformPath <managed-terraform-path>
```

The script uses the current worktree, real Terraform/builtin/random and the installed AzAPI planner. It seeds and destroys only **mocked** Azure objects, then plans against that state with dummy authentication, `refresh = false`, a pending `terraform_data.dep` change and `depends_on` on the consumer module.

It asserts deferred root/child `Reader` lookups, unchanged configured triggers, no assignment replacement or deletion, preserved GUIDs, unchanged guard state and the existing lock dependency graph. The ARM body retains a resolved role definition ID in prior state and becomes unknown pending lookup; the configured role name is never substituted into `roleDefinitionId`.

Additional CLI plans use explicitly **synthetic** state for both current configured-input guards and old pre-release resolved-ID guards. Mock-only provider defaults and IDs are normalized; typed/untyped nulls are encoded for this specific fixture. Both locks must remain no-op. Principal and role edits are rejected independently at root and child scope. A separate synthetic adopted-GUID case checks null-to-configured-trigger initialization without replacement.

Generated inputs, synthetic state and saved plans live in a unique ignored `.terraform` directory and are removed in `finally`. AzAPI dependency versions come from the root lock file. Compact test labels avoid Windows module-cache path limits; the test-directory argument uses Windows backslashes to prevent a zero-test false pass.

This is replacement-planning coverage, **not** actual Azure requests, persistence, refreshed convergence, lock propagation/deletion or a released same-state migration. Existing provider-mocked unit tests and `Test-RoleAssignmentLocalState.ps1` separately cover staged removal/recreation and real UUIDs. Fresh E2E and exact-candidate live upgrade verification still require separate authorization.
