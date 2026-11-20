param(
  [Parameter(Mandatory)]
  [string] $TerraformPath
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$separator = [IO.Path]::DirectorySeparatorChar
$testDirectory = "tests${separator}unit"
$filters = @('fanout', 'interfaces', 'child_interfaces', 'rbac_fanout', 'child_validation', 'default', 'complete', 'vm_consumption') | ForEach-Object {
  "-filter=${testDirectory}${separator}${_}.tftest.hcl"
}
$lines = & $TerraformPath "-chdir=$repository" test -json -verbose "-test-directory=$testDirectory" @filters
if ($LASTEXITCODE -ne 0) { throw "Terraform mock tests exited $LASTEXITCODE." }
$events = @($lines | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
$summary = $events | Where-Object type -EQ 'test_summary' | Select-Object -Last 1
if ($summary.test_summary.status -ne 'pass') { throw 'Mock test summary was not pass.' }

$script:assertions = 0
function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
  $script:assertions++
}
function Get-TestRecord([string] $Type, [string] $Run) {
  $record = $events | Where-Object { $_.type -eq $Type -and $_.'@testrun' -eq $Run } | Select-Object -Last 1
  if (-not $record) { throw "Missing $Type for $Run." }
  return $record.$Type
}
function Get-ChildResource($State, [string] $Key, [string] $Label = 'this') {
  $address = "module.capacity_reservation[`"$Key`"]"
  $module = $State.root_module.child_modules | Where-Object address -EQ $address
  $resource = $module.resources | Where-Object { $_.address -eq "$address.azapi_resource.$Label" }
  if (-not $resource) { throw "Missing child resource: $address.azapi_resource.$Label" }
  return $resource.values
}
function Get-StateResources($Module) {
  $Module.resources
  foreach ($child in $Module.child_modules) { Get-StateResources $child }
}

$rootBefore = Get-TestRecord 'test_state' 'read_only_custom_lock_and_explicit_principal_type'
$rootAfter = Get-TestRecord 'test_state' 'recreate_root_grant'
$childBefore = Get-TestRecord 'test_state' 'standalone_child_scoped_extensions'
$childAfter = Get-TestRecord 'test_state' 'recreate'
foreach ($pair in @(
  @{ before = $rootBefore; after = $rootAfter; principal = '33333333-3333-4333-8333-333333333333' },
  @{ before = $childBefore; after = $childAfter; principal = '44444444-4444-4444-8444-444444444444' }
)) {
  $oldRole = $pair.before.root_module.resources | Where-Object address -EQ 'azapi_resource.role_assignments["reader"]'
  $newRole = $pair.after.root_module.resources | Where-Object address -EQ 'azapi_resource.role_assignments["reader"]'
  $guard = $pair.after.root_module.resources | Where-Object address -EQ 'terraform_data.role_assignment_identity["reader"]'
  Assert-True ($oldRole.values.name -ne $newRole.values.name) 'Staged recreation must generate a fresh UUID, not reuse the previous grant name.'
  Assert-True ($newRole.values.body.properties.principalId -eq $pair.principal -and $guard.values.input.principal_id -eq $pair.principal) 'Recreated assignment and guard must accept the new principal together.'
}
foreach ($run in @('unchanged_grant_retains_guard', 'unchanged')) {
  $plan = Get-TestRecord 'test_plan' $run
  $protected = @($plan.resource_changes | Where-Object { $_.address -in @('azapi_resource.role_assignments["reader"]', 'terraform_data.role_assignment_identity["reader"]') })
  Assert-True ($protected.Count -eq 2 -and @($protected | Where-Object { ($_.change.actions -join ',') -ne 'no-op' }).Count -eq 0) 'Unchanged assignment inputs must preserve both grant and guard without replacement.'
}
$generated = Get-TestRecord 'test_state' 'generated_multizone_guids'
$zoneOne = Get-ChildResource $generated '5:multi:zone-1' 'role_assignments["reader"]'
$zoneTwo = Get-ChildResource $generated '5:multi:zone-2' 'role_assignments["reader"]'
Assert-True ($zoneOne.name -ne $zoneTwo.name) 'Mock UUID values must be distinct across expanded reservations.'
$explicit = Get-TestRecord 'test_state' 'distinct_single_zone_guids'
$one = Get-ChildResource $explicit '3:one:zone-1' 'role_assignments["reader"]'
$two = Get-ChildResource $explicit '3:two:zone-2' 'role_assignments["reader"]'
Assert-True ($one.name -eq '11111111-1111-4111-8111-111111111111' -and $two.name -eq '33333333-3333-4333-8333-333333333333') 'Per-zone explicit GUIDs must reach their separate child grants unchanged.'

$zonal = Get-TestRecord 'test_state' 'zonal_fanout'
$first = Get-ChildResource $zonal '9:appliance:zone-1'
$second = Get-ChildResource $zonal '9:appliance:zone-2'
$override = Get-ChildResource $zonal '8:override:zone-1'
$empty = Get-ChildResource $zonal '5:empty:zone-1'
Assert-True ($first.body.zones.Count -eq 1 -and $first.body.zones[0] -eq '1' -and $second.body.zones[0] -eq '2') 'Root fan-out failed to forward one zone per child.'
Assert-True ($first.name -eq 'shared-z1' -and $second.name -eq 'shared-z2') 'Expanded names were not forwarded.'
Assert-True ($first.body.sku.name -eq 'Standard_D2s_v5' -and $first.body.sku.capacity -eq 1 -and $second.body.sku.capacity -eq 1) 'SKU/quantity must reach both child bodies unchanged.'
Assert-True ($first.tags.inherited -eq 'yes' -and $second.tags.inherited -eq 'yes') 'Null child tags must inherit root tags.'
Assert-True ($override.tags.own -eq 'yes' -and -not $override.tags.PSObject.Properties['inherited']) 'Explicit child tags must replace, not merge.'
Assert-True (@($empty.tags.PSObject.Properties).Count -eq 0) 'Explicit empty tags must clear inheritance.'

$regional = Get-TestRecord 'test_state' 'regional_zero_boundary_and_delimiter_safe_keys'
$child = Get-ChildResource $regional '8:a:zone-1:regional'
Assert-True (-not $child.body.PSObject.Properties['zones'] -and $child.body.sku.capacity -eq 0) 'Regional child must omit zones and forward zero.'

$reorder = Get-TestRecord 'test_plan' 'reordered_zones_preserve_keys_and_ids'
$changes = @($reorder.resource_changes | Where-Object { ($_.change.actions -join ',') -ne 'no-op' })
Assert-True ($changes.Count -eq 0) 'Zone reorder must be a complete mock-plan no-op, not merely equal mock IDs.'
$zero = Get-TestRecord 'test_plan' 'resize_to_zero_keeps_identity'
$resize = $zero.resource_changes | Where-Object address -EQ 'azapi_resource.this'
Assert-True (($resize.change.actions -join ',') -eq 'update' -and $resize.change.after.body.sku.capacity -eq 0) 'Resize to zero must be an in-place mock-plan update, not replacement.'

$scoped = Get-TestRecord 'test_state' 'parent_owns_child_cardinality'
$reservation = Get-ChildResource $scoped '5:first:zone-1'
$lock = Get-ChildResource $scoped '5:first:zone-1' 'lock[0]'
$role = Get-ChildResource $scoped '5:first:zone-1' 'role_assignments["reader"]'
Assert-True ($lock.parent_id -eq $reservation.id -and $role.parent_id -eq $reservation.id) 'Expanded child extensions must be reservation-scoped.'
Assert-True ($lock.body.properties.notes -eq 'Nested lock' -and $role.body.properties.principalType -eq 'Group') 'Nested extension properties must survive root forwarding.'
Assert-True ($reservation.type -eq 'Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-11-01' -and $lock.type -eq 'Microsoft.Authorization/locks@2016-09-01') 'Nested resource type overrides must be forwarded.'
Assert-True ($reservation.retry.interval_seconds -eq 5 -and $lock.retry.interval_seconds -eq 5 -and $role.retry.interval_seconds -eq 5) 'Retries must reach every expanded child-owned resource.'
Assert-True ($reservation.timeouts.create -eq '30m' -and $lock.timeouts.delete -eq '10m' -and $role.timeouts.delete -eq '10m') 'Timeouts must reach the reservation and its extensions.'

$complete = Get-TestRecord 'test_state' 'composition'
$parent = $complete.root_module.child_modules | Where-Object address -EQ 'module.capacity_reservation_group'
$nested = @{ root_module = @{ child_modules = @($parent.child_modules | ForEach-Object {
  @{
    address = $_.address.Replace('module.capacity_reservation_group.', '')
    resources = @($_.resources | ForEach-Object {
      @{ address = $_.address.Replace('module.capacity_reservation_group.', ''); values = $_.values }
    })
  }
}) } }
$primary = Get-ChildResource $nested '7:primary:zone-1'
$primarySecondZone = Get-ChildResource $nested '7:primary:zone-2'
$replacement = Get-ChildResource $nested '11:replacement:zone-1'
$untagged = Get-ChildResource $nested '8:untagged:zone-1'
Assert-True ($primary.tags.environment -eq 'example' -and $primarySecondZone.tags.environment -eq 'example') 'Complete example primary reservations must inherit root tags in both zones.'
Assert-True ($replacement.tags.workload -eq 'explicit-replacement' -and -not $replacement.tags.PSObject.Properties['environment']) 'Complete example replacement tags must not inherit environment.'
Assert-True (@($untagged.tags.PSObject.Properties).Count -eq 0) 'Complete example empty tags must clear inheritance.'
Assert-True ($primary.body.sku.capacity -eq 1 -and $primarySecondZone.body.sku.capacity -eq 1 -and $replacement.body.sku.capacity -eq 1 -and $untagged.body.sku.capacity -eq 1) 'Complete example must reserve exactly four default VM slots.'

$unlocked = Get-TestRecord 'test_state' 'unlocked'
$unlockedParent = $unlocked.root_module.child_modules | Where-Object address -EQ 'module.capacity_reservation_group'
$rootLock = @($unlockedParent.resources | Where-Object { $_.address -like '*.azapi_resource.lock*' })
$rootRoles = @($unlockedParent.resources | Where-Object { $_.address -like '*.azapi_resource.role_assignments*' })
$primaryModule = $unlockedParent.child_modules | Where-Object address -EQ 'module.capacity_reservation_group.module.capacity_reservation["7:primary:zone-1"]'
$childLock = @($primaryModule.resources | Where-Object { $_.address -like '*.azapi_resource.lock*' })
$childRoles = @($primaryModule.resources | Where-Object { $_.address -like '*.azapi_resource.role_assignments*' })
$primaryResource = ($primaryModule.resources | Where-Object { $_.address.EndsWith('.azapi_resource.this') }).values
Assert-True ($rootLock.Count -eq 0 -and $childLock.Count -eq 0) 'Staged unlock must remove both RG and reservation locks.'
Assert-True ($rootRoles.Count -eq 1 -and $childRoles.Count -eq 1) 'Staged unlock must retain both Reader bindings.'
Assert-True ($primaryResource.tags.environment -eq 'mutation' -and $primaryResource.tags.owner -eq 'parent') 'Metadata mutation must reach inherited reservation tags.'

foreach ($example in @(
  @{ run = 'live_regions'; count = 2; timeout = '10m' },
  @{ run = 'composition'; count = 5; timeout = '30m' },
  @{ run = 'opt_in'; count = 2; timeout = '10m' }
)) {
  $state = Get-TestRecord 'test_state' $example.run
  $compute = @(Get-StateResources $state.root_module | Where-Object {
    $_.type -eq 'azapi_resource' -and $_.values.type -match '^Microsoft.Compute/capacityReservationGroups(/capacityReservations)?@'
  })
  Assert-True ($compute.Count -eq $example.count) "$($example.run): expected all group and reservation resources."
  foreach ($resource in $compute) {
    $values = $resource.values
    Assert-True ($values.retry.error_message_regex -contains 'Cannot delete resource while nested resources exist') "$($resource.address): nested-resource delete retry missing."
    Assert-True ($values.retry.interval_seconds -eq 15 -and $values.retry.max_interval_seconds -eq 60 -and $values.timeouts.delete -eq $example.timeout) "$($resource.address): delete retries must retain bounded backoff and timeout."
  }
}

"PASS: $script:assertions nested mock-state/plan assertions; $($summary.test_summary.passed) Terraform runs. No HTTP request, Azure persistence or migration proof."
