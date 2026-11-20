# Released upgrade and post-upgrade coverage

These are **external, opt-in migration fixtures**, not additional fresh E2E examples. The runner never deploys on import, preparation, initialization, or offline testing. It never registers providers, grants elevated roles, changes CLI defaults, switches Git branches, or deletes the setup RG. Every live write requires a separate, unexpired, exact-phase approval. Do not run live phases without separately approved subscription, tenant, isolated RG, existing Reader principal, quota, SKU/zones, costs, retention, and cleanup.

The released baseline is Registry **0.2.0**, commit `c1ca05054fa11ec5b18ba327210801c7a25d92cd`. Initialization verifies the downloaded root and standalone child's runtime files byte-for-byte against that commit. The candidate must be a **full immutable commit SHA** available in this repository; preparation uses `git archive` and subsequently checks every archived file. An uncommitted worktree is not disguised as a tested candidate. Fixtures and protected artifacts must be outside the repository. No real scope defaults are provided.

## Coverage matrix

| Scenario | Released-to-candidate boundary | Separate candidate-only phases | Independent observations |
| --- | --- | --- | --- |
| `telemetry` | Telemetry enabled in both root and retained standalone child; keep historical providers during conversion | Classify subscription deployment additions, replacements, forgotten historical telemetry bindings, and per-plan timestamps distinctly | Subscription-scope deployment identity/template; infrastructure/output convergence excluding **only** the exact empty deployment's timestamp path; normal candidate teardown includes captured deployments |
| `readonly` | Apply released objects unlocked; add released RG ReadOnly lock; remove it in its own released apply; only then migrate | Relock after candidate convergence; independently unlock before normal candidate destroy | Retained group/child/platform/Reader IDs; exact RG scope, lock name/notes; absence and propagation after unlock. No claim that a PUT works under ReadOnly |
| `child_extensions` | Upgrade an existing **standalone** child at its unchanged caller address, no extensions in the upgrade plan | Add child CanNotDelete and Reader at the reservation scope only | Child extension IDs/scopes and Reader principal/definition, retained RG Reader GUID; full destroy is separate from selective immutable replacement under an unchanged lock |
| `fanout` | Upgrade existing group and separately owned child with empty parent collection | Add two-zone fan-out; reorder; subset removal; final clear; restore; parent tags | Stable definition/zone addresses; exact owned child membership; inherited tags, unchanged standalone ID/platform GUID/tags. Each intended delete is a separate phase, never an upgrade pass |
| `vm` | Official Registry **`Azure/avm-res-compute-virtualmachine/azurerm` 0.22.0**, identical in both group stages; VM/network owner exists in the **released baseline**, referencing group `resource_id` directly throughout upgrade | Explicit approved deallocation/readback, VM-owner disassociation, deallocation/readback and reassociation | Actual VM capacityReservation property, matching SKU/zone, retained group/child/VM platform GUID/disk/NIC identities; no casing transforms, added ignores, association resource, child-ID target or competing writer |
| MCAPS cross-subscription sharing | **Manual-only, separate scope and approval**, not a single-subscription AVM CI dependency | Add/subset/clear/restore/retarget/reorder, independent member drift/reconciliation, parent tags preserving unrelated child, both subscriptions' visibility and consumption permissions | Inspected requests, independent owner/consumer readbacks, two refreshed plans at each step, normal scoped cleanup. Not VM-association proof or cross-tenant assignment-exception proof |

No cross-subscription example is added to AVM E2E. If one is added later, it must have `.e2eignore` with the multi-subscription reason. Single-subscription examples keep the capacity-reservation target local; `vm_consumption` additionally pins the upstream VM dependency above. That dependency requires Terraform 1.16+ and resolves time/tls providers without generating private credentials.

**Live status is version-scoped and mixed.** Earlier evidence at candidate `138de45b` covers the standard migration and the four separately recorded expanded group scenarios described below. A separately approved live run with released VM **0.22.0** on 2026-11-16 passed baseline deployment and independent association readbacks, but both refreshed plans reproduced the upstream casing observation before candidate migration. Mock checks below establish fixture schema/graph and guard behavior only, not a live pass for a later source or dependency selection.

## Local checks (no Azure)

Use the Terraform executable installed by the current `Avm.Authoring` toolchain, not an independently upgraded binary:

```powershell
pwsh ./tests/migration/Test-MigrationSafety.ps1
pwsh ./tests/migration/Test-MigrationOffline.ps1 `
  -FixturePath <new-protected-external-directory> `
  -TerraformPath <managed-terraform-executable> `
  -CandidateSha <full-immutable-candidate-sha>
avm test unit
avm pre-commit
```

The offline checker initializes and validates the real Registry baseline and exact candidate configuration for each non-cleanup phase, then executes only fully provider-mocked Terraform apply/normal-plan tests. It routes the actual verbose mock-plan events through the convergence classifier, including timestamp-only deployment classification. It uses dummy identifiers/public-key text and marks the artifacts **offline-only** so the live runner refuses them. It does not fabricate successfully applied baseline state, migration moves, persisted Azure relationships, serialized requests, two refreshed Azure no-ops, or normal cleanup. Safety tests additionally execute the actual plan classifier against synthetic saved-plan-shaped objects; a rejected destructive test is not a real migration-plan result.

## Prepare one live scenario, without writing Azure

`Invoke-Migration.ps1` accepts operations separately; it never runs the next phase automatically:

```powershell
pwsh ./tests/migration/Invoke-Migration.ps1 -Operation Prepare `
  -FixturePath <new-external-directory> -Scenario readonly `
  -CandidateSha <full-immutable-candidate-sha> -ScopePath <protected-scope-json> `
  -TerraformPath <managed-terraform-executable>
```

The scope JSON requires `subscription_id`, `tenant_id`, `parent_id` (an existing **empty isolated RG**), `location`, `group_name`, `zone`, `zones` (fixed group envelope), `sku_name`, distinct `fanout_sku_name`, `reader_principal_id`, and `reader_principal_type` (`User`, `Group` or `ServicePrincipal`). VM additionally requires a genuine `ssh_public_key`; only offline checks use dummy key text. Use an AzAPI-only, separately approved setup to provision the RG; its state/cleanup remain separate. The runner does not adopt or delete it.

Use one fresh fixture per scenario. The fan-out case requires at least two approved zones and reserves one unit **per zone** in addition to the retained standalone slot. VM additionally creates a VM, Premium LRS disk and private network. Telemetry additionally needs subscription deployment read/write/delete permissions; RG Contributor is insufficient. None of these permissions, registrations or costs is implied by preparation.

## Live sequence and write approval contract

For each configured phase:

1. `-Operation Init`: initialize/validate and retain the resolved dependency lock. Both historical AzureRM and modtm remain available for conversion; no new target AzureRM resource is authored.
2. `-Operation Plan`: check explicit AzureCloud subscription/tenant, save a normal refreshed plan (or normal `-destroy` plan only in `cleanup`), decode it, classify exact allowed changes, and print its SHA256.
3. Independently inspect that binary plan's JSON privately: all bodies/unknowns, imports/moves/forgets, identities, GUIDs, scope, action invocations, outputs, and telemetry changes. The structural allowlist is a **safety guard, not plan approval**. Reject unexplained writes; do not broaden the allowlist to force a pass.
4. With separately granted approval, `-Operation Apply -ApprovalPath <protected-approval-json>` applies **that saved binary**, verifying its hash and decoding it again immediately beforehand. No implicit re-plan, `-target`, `-refresh=false`, state copying, state edits or backend/workspace changes are used.
5. `-Operation Readback`: independently GET every managed ARM object and check retained identities, child SKU/quantity/zone/tags/membership, Reader GUID/scope/principal/definition, child extensions, ReadOnly lock, or VM property as applicable. Independently GET the VM's OS disk with its disk API version; retain the exercised API version for every captured ID so final absence checks never guess a version from its resource path.
6. `-Operation Noop` **twice**: inspect two normal refreshed plans. Only exact empty subscription telemetry deployments with unchanged identity/body except `properties.template.outputs.apply_id.value` can be classified as timestamp-only writes; this is not a literal Terraform no-op. Other resource or output drift fails.
7. `-Operation Stage -Phase <next-phase>` permits only the next phase in the matrix, after successful apply/readback/two convergence inspections. It rewrites only configuration in the **same consumer directory, local default workspace and state**. Sources are literal HCL, never a variable.

Every write approval JSON requires the exact `subscription_id`, `tenant_id`, `parent_id`, `candidate_sha`, `scenario`, `phase`, `operation` (`Apply` or `Deallocate`), `plan_sha256` (exact printed hash for Apply; empty for Deallocate), future RFC3339 `expires_utc`, Boolean `telemetry_enabled` (true only for telemetry scenario), and `cost_and_cleanup_approved = true`. These fields represent a **real user approval**, not permission for an agent to invent one. Approval for a lifecycle deletion/removal must explicitly cover that phase; approving nondestructive upgrade does not authorize removal.

### Phase ordering

- Telemetry: `baseline → candidate → cleanup`.
- ReadOnly: `baseline → baseline-lock → baseline-unlock → candidate → relock → cleanup-unlock → cleanup`. Unlock phases may delete only the exact configured RG lock. Verify absence and allow propagation before advancing. Creating the lock is separated from creation of the independently consumed child.
- Child extensions: `baseline → candidate → child-extensions → cleanup`.
- Fan-out: `baseline → candidate → fanout-add → fanout-reorder → fanout-subset → fanout-clear → fanout-restore → parent-tags → cleanup`. The existing standalone child's definition/address is never moved into the new collection.
- VM: `baseline → candidate → vm-disassociate → vm-reassociate → cleanup`. Before each association change, invoke the separately approved `Deallocate` operation at the preceding phase. It targets only the captured test VM and checks actual `PowerState/deallocated`. Apply checks power state again; the property is changed only by the existing Terraform VM owner. There is no automatic restart. Inspect/read back both group membership and VM association projections.

The consumer root's existing external-child call remains
`module.estate["existing"].module.reservation["retained"]`.
The group remains `module.estate["existing"].module.group`.
Candidate parent fan-out uses `module.capacity_reservation["6:fanout:zone-<zone>"]` **inside that group**, and is new after upgrade, not a purported v0.2.0 resource.

## Cleanup, failure history and readiness

Stage `cleanup` only after the preceding phase completes. `Plan` creates the normal candidate destroy plan, which may delete only captured task-owned IDs. Obtain its own exact-plan approval, then Apply and `VerifyCleanup`. Verification requires empty consumer state and independent 404/ResourceNotFound for every captured Azure object, including **subscription deployments**, not merely an empty RG resource inventory. The separately owned setup RG is never deleted by this runner. A failed destroy remains failed; no broad RG deletion or recovery is attempted.

Private audit files retain every command/time/exit, original failure, decoded plan/classification, lock, and readback. The runner checks local state hashes/lineage between approved applies and rejects ambient CLI/workspace/data-directory overrides; state copying/restoring is not an allowed stage. A retry/recovery needs a new inspected plan and new approval. Do not enable raw Terraform HTTP/debug logging: VM/key APIs and state can contain secrets. Supply a public key to the migration fixture rather than generating a private-key-bearing action response.

**Still required before release readiness:** independent Migration Test execution against the final committed candidate; fresh E2E; exact-provider serialized-request capture/regression review using a protected, redacted request-only method; all independent readback/convergence checks; and normal cleanup. The runner deliberately does not pretend its readback or mock test is HTTP serialization proof. Selective immutable replacement under unchanged locks, deliberate parent replacement, regional/zero-create, cross-state handoff, MCAPS sharing and cross-tenant assignment exceptions remain separate unproved cases unless independently exercised.

## Executed-result qualification

The scenario table is a coverage contract, not an all-pass report. At group candidate `138de45b99ca6c4feeaeae9c95fdc13ad8b1cb4d`, the separately recorded released upgrades for enabled telemetry, staged ReadOnly, candidate child extensions and fan-out passed their scoped live checks and cleanup. Historically, the VM baseline failed normal refreshed convergence both with the earlier handwritten owner and with official VM AVM main `0bd2e266b1676c77ccb69f071d83c7161d12945c`: two plans for the latter contained the same single casing-only VM update, not replacements. The VM group upgrade and association mutations were not executed. This remains an upstream observation/follow-up, not a blocker attributed to the group refactor.

The current fixture instead selects released VM **0.22.0** (tag `bac606921999710f478197474ed077c145e8c066`) at both stages and verifies Registry source/version plus immutable runtime bytes without assuming a `.git` directory. The VM's interfaces utility advances from 0.9.0 to 0.10.0; the association body/defaults/outputs/provider requirements are unchanged. A new approved live run on 2026-11-16 actually applied the released group v0.2.0 baseline with VM 0.22.0 and passed independent identity/property/association/backlink readbacks. Both normal refreshed plans reproduced exactly one case-only VM association-ID update, with zero literal no-ops. Neither proposed update was applied; the candidate upgrade and owner mutations were not executed. This is an upstream observation, not a blocker attributed to the group refactor.

The November 16 run's normal released-baseline destroy initially received the nested-child group-delete 409. A newly inspected same-state normal retry succeeded after independent child-absence and empty-group checks. All nine captured consumer objects and the separately owned setup RG were independently absent, and both states were empty. No group candidate teardown, VM mutation, request-serialization or fresh-E2E pass is inferred from this recovered baseline cleanup. The separately frozen consumer/harness source was not part of the tested group commit; later publication must preserve that attribution.

The corrected attempt used an actually applied Registry v0.2.0 group, passed independent VM/association/platform-GUID/disk/NIC readbacks, applied neither drift plan, and used normal released-baseline teardown. A first group DELETE returned a nested-child 409; a newly inspected same-state normal destroy retry succeeded after independent child absence and empty-group readbacks. No broad RG recovery, imperative state edit, source patch or added ignore was used. A final audit verified twelve original/corrected consumer/setup states empty, six owned RGs absent and all six captured subscription telemetry deployment identities absent. Artifacts, private identities, original failures and exact fingerprints remain in the protected authoritative evidence record, not this repository.

The November 10 corrected consumer's managed units and focused offline phases passed; managed docs were regenerated. Its pre-commit attempt remained incomplete at transform after a local provider-cache failure/retry. On November 16, local validation with Registry VM 0.22.0 passed managed pre-commit (all seven phases), managed units (58 runs), four VM offline phases and 96 safety assertions. These are local results, not renewed Azure evidence. The clean-commit PR gate was not run. Do not relabel earlier authoring results, mock phases, recovered cleanup or these mixed live results as complete release readiness.

`avm pr-check` remains deferred until the complete changes are explicitly authorized to be committed and the worktree is clean. No commit/push/PR edit is part of these scripts.
