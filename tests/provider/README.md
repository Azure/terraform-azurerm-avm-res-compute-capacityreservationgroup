# Pinned provider read-shaping regression

Run `go test -v ./...` from this directory using Go 1.26 or later (the upstream provider's requirement). The dependency is the exact AzAPI 2.13.0 implementation resolved during this refactor, not a local reimplementation of its algorithm. Its canonical Go pseudo-version pins release commit `cf3ecee858fa48c0aca95d0b995a8bfd4950c8ec`; the provider module path has no `/v2` suffix. Dependency checksums belong in `go.sum`.

These offline cases exercise the provider's exported `UpdateObject` helper for sharing-list additions, removals, final clear, restore, retarget, reorder, external drift, and omission of read-only child/VM projections. They do **not** execute provider RPCs or HTTP requests and do not establish serialized request fidelity, Azure persistence, two refreshed plans, or released-state migration. Actual HTTP serialization and real-Azure collection/ownership tests remain deferred pending an approved isolated test scope.

The inspected `azapi_resource` write path serializes the configured body directly when no `sensitive_body` or ignored paths are supplied. Do not copy a workaround for a different provider version/resource-kind's merge behavior into this module. Consumers selecting ignore paths explicitly change that path and need their own coverage.
