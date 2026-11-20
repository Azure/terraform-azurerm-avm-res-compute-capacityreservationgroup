# Tests

- `avm test unit`: provider-mocked module and executable-example assertions.
- `Assert-ReservationMockState.ps1`: supplemental nested mock-state/plan assertions.
- [`migration`](migration/_header.md): opt-in external released-baseline/candidate fixtures, explicit post-upgrade phases, offline checks and saved-plan/write guards. No Azure run is implicit.
- [`provider`](provider/README.md): pinned provider read-shaping regression checks; not HTTP or Azure persistence proof.

Fresh example E2E, released same-state migration, serialization, independent readback, convergence and cleanup are distinct validation surfaces. Cross-subscription sharing is MCAPS manual-only, outside single-subscription AVM CI.
