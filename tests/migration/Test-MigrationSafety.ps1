$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Migration.Helpers.ps1"
$script:passed = 0
function Assert-Test([bool]$Condition, [string]$Label) {
  if (-not $Condition) { throw "FAIL: $Label" }
  $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Label) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  Assert-Test $failed $Label
}
function Copy-Object($Value) { $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable }
$scope = @{
  subscription_id = '00000000-0000-0000-0000-000000000000'
  tenant_id = '11111111-1111-1111-1111-111111111111'
  parent_id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/unit'
}
$manifest = @{
  scope = $scope; phase = 'candidate'; scenario = 'child_extensions'
  candidate_sha = ('a' * 40); owned_ids = @()
}
$g = 'module.estate["existing"].module.group'
$c = 'module.estate["existing"].module.reservation["retained"]'
$id = "$($scope.parent_id)/providers/Microsoft.Compute/capacityReservationGroups/unit"
$manifest.owned_ids = @($id)
function New-Change([string]$Address, [string[]]$Actions, [string]$Type = 'azapi_resource') {
  return @{
    address = $Address; type = $Type; mode = 'managed'
    change = @{
      actions = $Actions
      before = @{ id = $id; parent_id = $scope.parent_id }
      after = @{ id = $id; parent_id = $scope.parent_id }
    }
  }
}
function New-Plan($Changes) { @{ resource_changes = @($Changes); output_changes = @{}; action_invocations = @() } }
$empty = @{ output_changes = @{} }
Assert-MigrationPlan $empty $manifest -Noop | Out-Null
Assert-Test $true 'omitted empty plan arrays are not phantom actions'
$move = New-Change "$g.azapi_resource.this" @('update')
$move.previous_address = "$g.azapi_resource.capacity_reservation_group"
Assert-MigrationPlan (New-Plan $move) $manifest | Out-Null
Assert-Test $true 'known module-owned move accepted'
$bad = Copy-Object $move
$bad.change.actions = @('delete', 'create')
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest } 'upgrade replacement rejected'
$bad = Copy-Object $move
$bad.previous_address = "$g.azapi_resource.unexpected"
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest } 'unknown move rejected'
$bad = Copy-Object $move
$bad.change.after.id = "$id-other"
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest } 'identity-changing move rejected'
$bad = Copy-Object $move
$bad.change.after.parent_id = '/subscriptions/other/resourceGroups/unrelated'
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest } 'out-of-scope write rejected'
$bad = Copy-Object $move
$bad.change.importing = @{ id = $id }
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest } 'unexpected import rejected'
$bad = New-Plan $move
$bad.action_invocations = @(@{ address = 'action.unreviewed' })
Assert-Rejected { Assert-MigrationPlan $bad $manifest } 'stateless action rejected'
Assert-Rejected { Assert-MigrationPlan (New-Plan (New-Change "$c.azapi_resource.lock[0]" @('create'))) $manifest } 'candidate-only child feature cannot masquerade as migration'

$manifest.phase = 'child-extensions'
foreach ($suffix in @('azapi_resource.lock[0]', 'azapi_resource.role_assignments["reader"]', 'module.avm_interfaces.random_uuid.role_assignment_name["reader"]')) {
  $type = if ($suffix -like '*random_uuid*') { 'random_uuid' } else { 'azapi_resource' }
  Assert-MigrationPlan (New-Plan (New-Change "$c.$suffix" @('create') $type)) $manifest | Out-Null
  Assert-Test $true "child extension allowlist $suffix"
}
Assert-Rejected { Assert-MigrationPlan (New-Plan (New-Change "$c.azapi_resource.this" @('delete', 'create'))) $manifest } 'child replacement not child-extension coverage'

$manifest.scenario = 'fanout'
foreach ($phase in @('fanout-add', 'fanout-subset', 'fanout-clear', 'fanout-restore')) {
  $manifest.phase = $phase
  $action = if ($phase -in @('fanout-subset', 'fanout-clear')) { 'delete' } else { 'create' }
  $r = New-Change "$g.module.capacity_reservation[`"6:fanout:zone-2`"].azapi_resource.this" @($action)
  Assert-MigrationPlan (New-Plan $r) $manifest | Out-Null
  Assert-Test $true "intentional fan-out phase $phase"
}
$manifest.phase = 'fanout-reorder'
Assert-Rejected { Assert-MigrationPlan (New-Plan $r) $manifest } 'reorder cannot hide churn'
$manifest.phase = 'fanout-clear'
Assert-Rejected { Assert-MigrationPlan (New-Plan (New-Change "$c.azapi_resource.this" @('delete'))) $manifest } 'fan-out deletion cannot delete retained standalone child'

$manifest.scenario = 'readonly'
foreach ($phase in @('baseline-lock', 'baseline-unlock', 'relock', 'cleanup-unlock')) {
  $manifest.phase = $phase
  $address = if ($phase.StartsWith('baseline')) { "$g.azurerm_management_lock.this[0]" } else { "$g.azapi_resource.lock[0]" }
  $action = if ($phase -like '*unlock') { 'delete' } else { 'create' }
  Assert-MigrationPlan (New-Plan (New-Change $address @($action))) $manifest | Out-Null
  Assert-Test $true "separate ReadOnly stage $phase"
}
Assert-Rejected { Assert-MigrationPlan (New-Plan (New-Change "$g.azapi_resource.this" @('update'))) $manifest } 'unlock cannot include a parent PUT'

$manifest.phase = 'candidate'; $manifest.scenario = 'telemetry'
$telemetry = New-Change "$g.azapi_resource.telemetry[0]" @('update')
$telemetry.change.before = @{
  id = "/subscriptions/$($scope.subscription_id)/providers/Microsoft.Resources/deployments/unit"
  parent_id = "/subscriptions/$($scope.subscription_id)"
  name = 'unit'; location = 'eastus'; type = 'Microsoft.Resources/deployments@2025-04-01'
  body = @{ properties = @{ mode = 'Incremental'; template = @{ resources = @(); outputs = @{ apply_id = @{ type = 'String'; value = 'old' } } } } }
}
$telemetry.change.after = Copy-Object $telemetry.change.before
$telemetry.change.after.body.properties.template.outputs.apply_id.value = 'new'
Assert-MigrationPlan (New-Plan $telemetry) $manifest -Noop | Out-Null
Assert-Test $true 'only telemetry timestamp classified during convergence'
$bad = Copy-Object $telemetry
$bad.change.after.body.properties.template.resources = @(@{ type = 'Microsoft.Compute/virtualMachines' })
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest -Noop } 'nonempty deployment never discounted as telemetry'
$bad = Copy-Object $telemetry
$bad.change.after.name = 'replacement'
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest -Noop } 'telemetry name change is not timestamp drift'
$bad = Copy-Object $telemetry
$bad.change.after.body.properties.mode = 'Complete'
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest -Noop } 'telemetry mode drift not discounted'
$bad = Copy-Object $telemetry
$bad.change.actions = @('delete', 'create')
Assert-Rejected { Assert-MigrationPlan (New-Plan $bad) $manifest -Noop } 'telemetry replacement is not no-op'
$manifest.owned_ids = @($telemetry.change.before.id)
Assert-MigrationPlan (New-Plan $bad) $manifest | Out-Null
Assert-Test $true 'telemetry replacement distinct in upgrade inspection'
$manifest.scenario = 'fanout'
Assert-Rejected { Assert-MigrationPlan (New-Plan $telemetry) $manifest } 'unexpected telemetry opt-in rejected'
$manifest.phase = 'cleanup'; $manifest.owned_ids = @($id)
Assert-MigrationPlan (New-Plan (New-Change "$g.azapi_resource.this" @('delete'))) $manifest | Out-Null
Assert-Test $true 'captured normal candidate teardown accepted'
$manifest.owned_ids = @()
Assert-Rejected { Assert-MigrationPlan (New-Plan (New-Change "$g.azapi_resource.this" @('delete'))) $manifest } 'uncaptured cleanup resource rejected'
$manifest.scenario = 'telemetry'
$uncapturedTelemetry = Copy-Object $telemetry
$uncapturedTelemetry.change.actions = @('delete')
$uncapturedTelemetry.change.after = $null
Assert-Rejected { Assert-MigrationPlan (New-Plan $uncapturedTelemetry) $manifest } 'uncaptured subscription deployment cleanup rejected'
$manifest.scenario = 'fanout'
$p = New-Plan @()
$p.output_changes.changed = @{ actions = @('update') }
Assert-Rejected { Assert-MigrationPlan $p $manifest -Noop } 'output-only drift rejected'

$manifest.phase = 'parent-tags'
$badMetadata = New-Change "$g.azapi_resource.this" @('update')
$badMetadata.change.before.body = @{ properties = @{} }
$badMetadata.change.after.body = @{ properties = @{ unexpected = $true } }
Assert-Rejected { Assert-MigrationPlan (New-Plan $badMetadata) $manifest } 'metadata phase cannot hide a body mutation'
$manifest.scenario = 'vm'; $manifest.phase = 'vm-disassociate'; $manifest.scope.group_name = 'unit'
$vmChange = New-Change 'module.virtual_machine.azapi_resource.this_linux_virtual_machine[0]' @('update')
$vmChange.change.before.body = @{ properties = @{
  capacityReservation = @{ capacityReservationGroup = @{ id = $id } }
  hardwareProfile = @{ vmSize = 'Standard_D2s_v5' }
} }
$vmChange.change.after.body = Copy-Object $vmChange.change.before.body
$vmChange.change.after.body.properties.capacityReservation = $null
Assert-MigrationPlan (New-Plan $vmChange) $manifest | Out-Null
Assert-Test $true 'VM phase allows only the intended owner-side null reference'
$oldOwner = Copy-Object $vmChange
$oldOwner.address = 'azapi_resource.virtual_machine'
Assert-Rejected { Assert-MigrationPlan (New-Plan $oldOwner) $manifest } 'retired handwritten VM owner is not admitted'
$oldNullShape = Copy-Object $vmChange
$oldNullShape.change.after.body.properties.capacityReservation = @{ capacityReservationGroup = @{ id = $null } }
Assert-Rejected { Assert-MigrationPlan (New-Plan $oldNullShape) $manifest } 'VM toggle must match the pinned upstream null contract'
$badVm = Copy-Object $vmChange
$badVm.change.after.body.properties.hardwareProfile.vmSize = 'Standard_D8s_v5'
Assert-Rejected { Assert-MigrationPlan (New-Plan $badVm) $manifest } 'VM toggle cannot hide a size mutation'
$manifest.phase = 'vm-reassociate'
$badVm = Copy-Object $vmChange
$badVm.change.after.body.properties.capacityReservation = @{ capacityReservationGroup = @{ id = "$id-other" } }
Assert-Rejected { Assert-MigrationPlan (New-Plan $badVm) $manifest } 'VM toggle cannot target another group'
$extraAssociation = Copy-Object $badVm
$extraAssociation.change.after.body.properties.capacityReservation = @{ capacityReservationGroup = @{ id = $id }; unexpected = $true }
Assert-Rejected { Assert-MigrationPlan (New-Plan $extraAssociation) $manifest } 'VM toggle cannot hide another association-body field'
$goodVm = Copy-Object $vmChange
$goodVm.change.before.body.properties.capacityReservation = $null
$goodVm.change.after.body.properties.capacityReservation = @{ capacityReservationGroup = @{ id = $id } }
Assert-MigrationPlan (New-Plan $goodVm) $manifest | Out-Null
Assert-Test $true 'pinned upstream VM owner can reassociate without another property mutation'
$privateKey = New-Change 'module.virtual_machine.tls_private_key.this[0]' @('create') 'tls_private_key'
Assert-Rejected { Assert-MigrationPlan (New-Plan $privateKey) $manifest } 'VM fixture cannot generate private credentials'
$vmSource = Get-Content (Join-Path $PSScriptRoot '../../examples/vm_consumption/main.tf') -Raw
Assert-Test ($vmSource -cmatch 'source\s*=\s*"Azure/avm-res-compute-virtualmachine/azurerm"' -and $vmSource -cmatch 'version\s*=\s*"0\.22\.0"') 'VM consumer pins the exact official Registry release'
Assert-Test ($vmSource -notmatch 'resource "azapi_resource" "virtual_machine"|ignore_casing|ignore_body_changes|upper\(|lower\(') 'VM consumer adds no second VM writer or casing/ignore workaround'
$release = @{
  upstream_vm_source = 'Azure/avm-res-compute-virtualmachine/azurerm'
  upstream_vm_version = '0.22.0'
  upstream_vm_sha = 'bac606921999710f478197474ed077c145e8c066'
}
foreach ($key in @('upstream_vm_source', 'upstream_vm_version', 'upstream_vm_sha')) {
  $badRelease = Copy-Object $release
  $badRelease[$key] = 'incorrect'
  Assert-Rejected { Assert-MigrationVmSource $PSScriptRoot $badRelease } "VM release guard rejects $key drift before reading packages"
}
$releaseFixture = Join-Path ([IO.Path]::GetTempPath()) ('vm-release-guard-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path (Join-Path $releaseFixture '.terraform/modules') -Force | Out-Null
  $vmModules = @{ Modules = @(
    @{ Key = 'virtual_machine'; Source = 'registry.terraform.io/Azure/avm-res-compute-virtualmachine/azurerm'; Version = '0.22.0'; Dir = '.' }
    @{ Key = 'virtual_machine.avm_utl_interfaces'; Source = 'registry.terraform.io/Azure/avm-utl-interfaces/azure'; Version = '0.10.0'; Dir = '.' }
  ) }
  foreach ($mutation in @('source', 'version', 'utility-version', 'bytes')) {
    $badModules = Copy-Object $vmModules
    switch ($mutation) {
      source { $badModules.Modules[0].Source = 'git::https://example.invalid/vm.git' }
      version { $badModules.Modules[0].Version = '0.21.0' }
      utility-version { $badModules.Modules[1].Version = '0.9.0' }
    }
    Write-MigrationJson (Join-Path $releaseFixture '.terraform/modules/modules.json') $badModules
    Assert-Rejected { Assert-MigrationVmSource $releaseFixture $release } "VM release guard rejects package $mutation drift"
  }
} finally {
  Remove-Item -LiteralPath $releaseFixture -Recurse -Force
}
$manifest.scenario = 'telemetry'
$badTelemetry = Copy-Object $telemetry
$badTelemetry.change.after.tags = @{ unexpected = 'tag' }
Assert-Rejected { Assert-MigrationPlan (New-Plan $badTelemetry) $manifest -Noop } 'telemetry non-body changes are not timestamp drift'
$manifest.scenario = 'fanout'

$approval = @{
  subscription_id = $scope.subscription_id; tenant_id = $scope.tenant_id; parent_id = $scope.parent_id
  candidate_sha = $manifest.candidate_sha; scenario = $manifest.scenario; phase = $manifest.phase
  operation = 'Apply'; plan_sha256 = 'ABC'; expires_utc = [DateTimeOffset]::UtcNow.AddMinutes(2).ToString('o')
  cost_and_cleanup_approved = $true; telemetry_enabled = $false
}
Assert-MigrationApproval $approval $manifest 'Apply' 'ABC'
Assert-Test $true 'complete phase-bound plan approval accepted'
foreach ($key in @('subscription_id', 'tenant_id', 'parent_id', 'candidate_sha', 'scenario', 'phase', 'operation', 'plan_sha256', 'expires_utc', 'cost_and_cleanup_approved', 'telemetry_enabled')) {
  $badApproval = Copy-Object $approval
  $badApproval[$key] = switch ($key) {
    'expires_utc' { '2000-01-01T00:00:00Z' }
    'cost_and_cleanup_approved' { $false }
    'telemetry_enabled' { $true }
    default { 'incorrect' }
  }
  Assert-Rejected { Assert-MigrationApproval $badApproval $manifest 'Apply' 'ABC' } "approval rejects $key drift"
}
$templates = Join-Path $PSScriptRoot 'templates'
$state = @{ scenario = 'readonly'; phase = 'baseline'; completed = @(); readback = $false; noops = 0 }
Assert-Rejected { Assert-MigrationAdvance $state 'candidate' } 'cannot skip released ReadOnly lock/unlock stages'
Assert-Rejected { Assert-MigrationAdvance $state 'baseline-lock' } 'cannot advance without successful applied baseline'
$state.completed = @('baseline')
Assert-Rejected { Assert-MigrationAdvance $state 'baseline-lock' } 'cannot advance without independent readback'
$state.readback = $true; $state.noops = 1
Assert-Rejected { Assert-MigrationAdvance $state 'baseline-lock' } 'one refreshed no-op is insufficient'
$state.noops = 2
Assert-MigrationAdvance $state 'baseline-lock'
Assert-Test $true 'all phase prerequisites permit only next phase'
$state.scenario = 'vm'; $state.phase = 'candidate'; $state.completed = @('baseline', 'candidate')
Assert-Rejected { Assert-MigrationAdvance $state 'vm-disassociate' } 'association toggle requires independent deallocation'
$state.deallocated = $true
Assert-MigrationAdvance $state 'vm-disassociate'
Assert-Test $true 'explicit verified deallocation permits VM property stage'
$state.phase = 'cleanup'; $state.completed += 'cleanup'
Assert-Rejected { Assert-MigrationAdvance $state 'baseline' } 'completed fixture cannot restart a baseline over migrated state'
$manifest.candidate_path = '/outside/candidate'
foreach ($scenario in @('telemetry', 'readonly', 'child_extensions', 'fanout', 'vm')) {
  $manifest.scenario = $scenario
  $manifest.phase = 'baseline'
  $baseline = Get-MigrationWorkload $templates $manifest
  Assert-Test ($baseline.Contains('version = "0.2.0"') -and -not $baseline.Contains('capacity_reservations =')) "$scenario released shape has no new-feature fiction"
  $manifest.phase = 'candidate'
  $candidate = Get-MigrationWorkload $templates $manifest
  Assert-Test ($candidate.Contains('capacity_reservations = {}') -and $candidate.Contains('for_each = { retained = true }') -and -not $candidate.Contains('version =')) "$scenario immutable candidate shape preserves standalone caller"
}
$leaf = @{ resources = @(@{ mode = 'managed'; address = 'leaf.resource' }, @{ mode = 'data'; address = 'leaf.lookup' }) }
$tree = @{ resources = @(@{ mode = 'managed'; address = 'root.resource' }); child_modules = @($leaf, $null) }
$walked = @(Get-MigrationResources $tree)
Assert-Test ($walked.Count -eq 2 -and $walked[0].address -eq 'root.resource' -and $walked[1].address -eq 'leaf.resource') 'resource walker terminates on omitted leaf child_modules and ignores data/null entries'
Assert-Test (@(Get-MigrationResources $null).Count -eq 0) 'resource walker terminates on null module'
Assert-Test (@(Get-MigrationResources @{}).Count -eq 0) 'resource walker terminates on empty module'
foreach ($code in @('ResourceNotFound', 'ResourceGroupNotFound', 'DeploymentNotFound', 'RoleAssignmentNotFound', 'LockNotFound', 'NotFound')) {
  Assert-Test (Test-MigrationAbsence "ERROR: Not Found({`"error`":{`"code`":`"$code`"}})" 1) "structured ARM $code proves absence"
}
Assert-Test (-not (Test-MigrationAbsence '{"error":{"code":"AuthorizationFailed","message":"ResourceNotFound 404"}}' 1)) 'denied GET mentioning NotFound is not absence'
Assert-Test (-not (Test-MigrationAbsence '{"error":{"code":"ResourceNotFound"}}' 0)) 'successful GET is never absence'
Assert-Test (-not (Test-MigrationAbsence 'transport failed: 404 NotFound' 1)) 'unstructured transport failure is not absence'
"PASS: $script:passed offline safety assertions. No Azure operations; no migration/deployment proof."
