# JSON plans legitimately omit optional properties; retain undefined-variable checks.
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

function Write-MigrationJson($Path, $Value) {
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

function Get-MigrationPhases([string]$Scenario) {
  switch ($Scenario) {
    telemetry       { return @('baseline', 'candidate', 'cleanup') }
    readonly        { return @('baseline', 'baseline-lock', 'baseline-unlock', 'candidate', 'relock', 'cleanup-unlock', 'cleanup') }
    child_extensions { return @('baseline', 'candidate', 'child-extensions', 'cleanup') }
    fanout          { return @('baseline', 'candidate', 'fanout-add', 'fanout-reorder', 'fanout-subset', 'fanout-clear', 'fanout-restore', 'parent-tags', 'cleanup') }
    vm              { return @('baseline', 'candidate', 'vm-disassociate', 'vm-reassociate', 'cleanup') }
    default         { throw "Unknown scenario $Scenario." }
  }
}

function Assert-MigrationAdvance($Manifest, [string]$NextPhase) {
  $phases = Get-MigrationPhases $Manifest.scenario
  $index = [Array]::IndexOf($phases, $Manifest.phase)
  if ($index -lt 0 -or $index + 1 -ge $phases.Count -or $NextPhase -cne $phases[$index + 1]) { throw 'Only the next explicit scenario phase is allowed.' }
  if ($Manifest.phase -notin $Manifest.completed -or -not $Manifest.readback -or $Manifest.noops -lt 2) {
    throw 'Current phase needs a successful saved-plan apply, independent readback and two refreshed no-op inspections.'
  }
  if ($NextPhase -in @('vm-disassociate', 'vm-reassociate') -and -not $Manifest.deallocated) {
    throw 'Deallocate and independently verify the VM before changing its owner property.'
  }
}

function Assert-MigrationExternalPath([string]$Path, [string]$Repository) {
  $full = [IO.Path]::GetFullPath($Path)
  $repo = [IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
  if ($full -eq $repo -or $full.StartsWith("$repo$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixtures/state/plans must be outside the repository.'
  }
  $current = $full
  while ($current) {
    if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'Fixture paths must not traverse symlinks/junctions.'
    }
    $current = Split-Path $current -Parent
  }
}

function Protect-MigrationDirectory([string]$Path) {
  if ($IsWindows) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
      $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
  } else {
    & chmod 700 $Path
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect fixture directory.' }
  }
}

function Get-MigrationHashes([string]$Path, [string]$Filter = '*') {
  $result = [ordered]@{}
  Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $Filter |
    Where-Object { $_.FullName -notmatch '[\\/]\.terraform[\\/]' } |
    Sort-Object FullName | ForEach-Object {
      $result[[IO.Path]::GetRelativePath($Path, $_.FullName)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
  return $result
}

function Assert-MigrationHashes([string]$Path, $Expected, [string]$Filter = '*') {
  $actual = Get-MigrationHashes $Path $Filter
  if (($actual | ConvertTo-Json -Compress) -cne ($Expected | ConvertTo-Json -Compress)) {
    throw "Source/configuration drift at $Path."
  }
}

function Invoke-MigrationCommand([string]$Executable, [string[]]$Arguments, [string]$AuditPath, [int[]]$AllowedExitCodes = @(0)) {
  # Never persist raw HTTP/debug logs, environment variables, or CLI credentials.
  if ($env:TF_LOG -or $env:TF_LOG_PROVIDER -or $env:TF_LOG_PATH) { throw 'Disable Terraform debug logging first.' }
  $started = [DateTimeOffset]::UtcNow
  $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
  $exit = $LASTEXITCODE
  Write-MigrationJson $AuditPath ([ordered]@{
    arguments = $Arguments; started_utc = $started; completed_utc = [DateTimeOffset]::UtcNow
    exit_code = $exit; output = $lines
  })
  if ($exit -notin $AllowedExitCodes) { throw "Command failed ($exit); protected audit: $AuditPath" }
  return ($lines -join "`n")
}

function Assert-MigrationContext($Scope) {
  $account = (& az account show --output json --only-show-errors | ConvertFrom-Json -AsHashtable)
  if ($LASTEXITCODE -ne 0 -or $account.id -ine $Scope.subscription_id -or $account.tenantId -ine $Scope.tenant_id -or $account.environmentName -ne 'AzureCloud') {
    throw 'Explicit approved AzureCloud subscription/tenant differs from current CLI context.'
  }
  foreach ($pair in @(@('ARM_SUBSCRIPTION_ID', $Scope.subscription_id), @('ARM_TENANT_ID', $Scope.tenant_id))) {
    $value = [Environment]::GetEnvironmentVariable($pair[0])
    if ($value -and $value -ine $pair[1]) { throw "Conflicting $($pair[0])." }
  }
}

function Assert-MigrationApproval($Approval, $Manifest, [string]$Operation, [string]$PlanHash = '') {
  foreach ($key in @('subscription_id', 'tenant_id', 'parent_id')) {
    if ($Approval[$key] -ine $Manifest.scope[$key]) { throw "Approval $key mismatch." }
  }
  if ($Approval.candidate_sha -cne $Manifest.candidate_sha -or $Approval.scenario -cne $Manifest.scenario -or
      $Approval.phase -cne $Manifest.phase -or $Approval.operation -cne $Operation -or
      [DateTimeOffset]::Parse($Approval.expires_utc) -le [DateTimeOffset]::UtcNow -or
      $Approval.plan_sha256 -cne $PlanHash -or $Approval.telemetry_enabled -ne ($Manifest.scenario -eq 'telemetry') -or
      $Approval.cost_and_cleanup_approved -ne $true) {
    throw 'Missing, expired, wrong-phase, wrong-plan or incomplete explicit approval.'
  }
}

function Test-MigrationTelemetryResource($Change, $Scope) {
  # Address AND type AND exact subscription scope AND empty template must match.
  $g = 'module.estate["existing"].module.group'
  $c = 'module.estate["existing"].module.reservation["retained"]'
  $allowed = @($g, $c, "$g.module.avm_interfaces", "$c.module.avm_interfaces") | ForEach-Object { "$_.azapi_resource.telemetry[0]" }
  if ($Change.type -ne 'azapi_resource' -or $Change.address -cnotin $allowed) { return $false }
  foreach ($v in @($Change.change.before, $Change.change.after) | Where-Object { $null -ne $_ }) {
    if ($v.type -cne 'Microsoft.Resources/deployments@2025-04-01' -or
        $v.parent_id -ine "/subscriptions/$($Scope.subscription_id)" -or
        $v.body.properties.mode -cne 'Incremental' -or @($v.body.properties.template.resources).Count -ne 0) { return $false }
  }
  return $true
}

function Assert-MigrationTimestampOnly($Change, $Scope) {
  if (-not (Test-MigrationTelemetryResource $Change $Scope) -or ($Change.change.actions -join ',') -ne 'update') {
    throw 'Not an in-place telemetry timestamp write.'
  }
  $before = $Change.change.before
  $after = $Change.change.after
  foreach ($key in @('id', 'name', 'type', 'parent_id', 'location')) {
    if ($before[$key] -cne $after[$key]) { throw "Telemetry $key changed; not timestamp-only." }
  }
  foreach ($key in @($before.Keys + $after.Keys | Sort-Object -Unique)) {
    if ($key -in @('body', 'output')) { continue }
    if (($before[$key] | ConvertTo-Json -Depth 100 -Compress) -cne ($after[$key] | ConvertTo-Json -Depth 100 -Compress)) {
      throw "Telemetry $key changed; not timestamp-only."
    }
  }
  $oldBody = $before.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
  $newBody = $after.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
  $oldBody.properties.template.outputs.apply_id.value = '<timestamp>'
  $newBody.properties.template.outputs.apply_id.value = '<timestamp>'
  if (($oldBody | ConvertTo-Json -Depth 100 -Compress) -cne ($newBody | ConvertTo-Json -Depth 100 -Compress)) {
    throw 'Telemetry body changed outside outputs.apply_id.value.'
  }
}

function Assert-MigrationPlan($Plan, $Manifest, [switch]$Noop) {
  if (@($Plan.action_invocations | Where-Object { $null -ne $_ }).Count -gt 0) { throw 'Unapproved Terraform action invocation.' }
  $g = 'module.estate["existing"].module.group'
  $c = 'module.estate["existing"].module.reservation["retained"]'
  $moves = @{
    "$g.azapi_resource.this" = "$g.azapi_resource.capacity_reservation_group"
    "$c.azapi_resource.this" = "$c.azapi_resource.capacity_reservation"
    "$g.azapi_resource.role_assignments[`"reader`"]" = "$g.azurerm_role_assignment.this[`"reader`"]"
  }
  $localTypes = @('random_uuid', 'terraform_data', 'modtm_telemetry')
  $classification = @()
  foreach ($r in @($Plan.resource_changes | Where-Object { $null -ne $_ })) {
    if ($r.mode -eq 'data') { continue }
    $actions = $r.change.actions -join ','
    if ($Manifest.scenario -eq 'vm' -and $r.type -notin @('azapi_resource', 'azurerm_role_assignment', 'random_uuid', 'terraform_data')) {
      throw "Unexpected VM fixture resource kind (including generated credentials): $($r.type)."
    }
    if ($actions -eq 'no-op') { continue }
    $telemetry = Test-MigrationTelemetryResource $r $Manifest.scope
    if ($telemetry -and $Manifest.scenario -ne 'telemetry') { throw 'Unexpected enabled telemetry.' }
    if ($Noop) {
      if ($telemetry) { Assert-MigrationTimestampOnly $r $Manifest.scope } else { throw "Not converged: $($r.address)." }
      $classification += @{ address = $r.address; classification = 'telemetry-timestamp-only' }
      continue
    }
    if ($r.change.importing) { throw 'No imports are expected on this standard moved path.' }
    if ($r.previous_address -and ($Manifest.phase -ne 'candidate' -or $moves[$r.address] -cne $r.previous_address)) {
      throw "Unexpected move: $($r.address)."
    }
    $allowed = $false
    $kind = $actions
    if ($Manifest.phase -eq 'baseline') {
      $allowed = $actions -eq 'create'
    } elseif ($Manifest.phase -eq 'candidate') {
      $allowed = ($moves.ContainsKey($r.address) -and $actions -eq 'update' -and $r.previous_address -ceq $moves[$r.address])
      $allowed = $allowed -or ($r.address -eq "$g.module.avm_interfaces.random_uuid.role_assignment_name[`"reader`"]" -and $actions -eq 'create')
      if ($Manifest.scenario -eq 'telemetry') {
        $allowed = $allowed -or ($telemetry -and $actions -in @('create', 'update', 'delete,create', 'create,delete'))
        $allowed = $allowed -or ($r.address -match '\.(modtm_telemetry|random_uuid)\.telemetry(\[0\])?$' -and $actions -eq 'forget')
        $allowed = $allowed -or ($r.address -match '\.terraform_data\.telemetry\[0\]$' -and $actions -eq 'create')
        $kind = if ($telemetry) { "telemetry-$actions" } else { $kind }
      }
    } elseif ($Manifest.phase -in @('baseline-lock', 'baseline-unlock', 'relock', 'cleanup-unlock')) {
      $lockAddress = if ($Manifest.phase.StartsWith('baseline')) { "$g.azurerm_management_lock.this[0]" } else { "$g.azapi_resource.lock[0]" }
      $expected = if ($Manifest.phase -in @('baseline-unlock', 'cleanup-unlock')) { 'delete' } else { 'create' }
      $allowed = $r.address -ceq $lockAddress -and $actions -eq $expected
    } elseif ($Manifest.phase -eq 'child-extensions') {
      $allowed = $actions -eq 'create' -and $r.address -in @(
        "$c.azapi_resource.lock[0]", "$c.azapi_resource.role_assignments[`"reader`"]",
        "$c.module.avm_interfaces.random_uuid.role_assignment_name[`"reader`"]"
      )
    } elseif ($Manifest.phase -like 'fanout-*') {
      $child = $r.address.StartsWith("$g.module.capacity_reservation[`"6:fanout:zone-", [StringComparison]::Ordinal)
      $expected = switch ($Manifest.phase) {
        'fanout-add' { 'create' }; 'fanout-restore' { 'create' }
        'fanout-subset' { 'delete' }; 'fanout-clear' { 'delete' }
        default { 'no-op' }
      }
      $allowed = $child -and $r.address.EndsWith('.azapi_resource.this') -and $actions -eq $expected
    } elseif ($Manifest.phase -eq 'parent-tags') {
      $allowed = $actions -eq 'update' -and ($r.address -ceq "$g.azapi_resource.this" -or $r.address.StartsWith("$g.module.capacity_reservation[`"6:fanout:zone-"))
    } elseif ($Manifest.phase -in @('vm-disassociate', 'vm-reassociate')) {
      $allowed = $r.address -ceq 'module.virtual_machine.azapi_resource.this_linux_virtual_machine[0]' -and $actions -eq 'update'
    } elseif ($Manifest.phase -eq 'cleanup') {
      $allowed = $actions -eq 'delete'
    }
    if (-not $allowed) { throw "Unapproved $actions at $($r.address) in $($Manifest.phase)." }
    if ($Manifest.phase -eq 'parent-tags' -and
        ($r.change.before.body | ConvertTo-Json -Depth 100 -Compress) -cne ($r.change.after.body | ConvertTo-Json -Depth 100 -Compress)) {
      throw 'Parent metadata phase changed an ARM body, not only tags.'
    }
    if ($Manifest.phase -in @('vm-disassociate', 'vm-reassociate')) {
      $oldBody = $r.change.before.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
      $newBody = $r.change.after.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
      $expectedGroup = "$($Manifest.scope.parent_id)/providers/Microsoft.Compute/capacityReservationGroups/$($Manifest.scope.group_name)"
      $reference = $newBody.properties.capacityReservation.capacityReservationGroup.id
      if (($Manifest.phase -eq 'vm-disassociate' -and $null -ne $newBody.properties.capacityReservation) -or
          ($Manifest.phase -eq 'vm-reassociate' -and $reference -ine $expectedGroup)) { throw 'Unexpected VM group reference.' }
      if ($Manifest.phase -eq 'vm-reassociate' -and
          (@($newBody.properties.capacityReservation.Keys).Count -ne 1 -or
           @($newBody.properties.capacityReservation.capacityReservationGroup.Keys).Count -ne 1)) { throw 'Unexpected VM association body shape.' }
      $oldBody.properties.capacityReservation = '<association>'
      $newBody.properties.capacityReservation = '<association>'
      if (($oldBody | ConvertTo-Json -Depth 100 -Compress) -cne ($newBody | ConvertTo-Json -Depth 100 -Compress)) {
        throw 'Association phase changed other VM-owned properties.'
      }
    }
    if ($r.type -notin $localTypes -and -not $telemetry) {
      foreach ($v in @($r.change.before, $r.change.after) | Where-Object { $null -ne $_ }) {
        $scope = @($v.id, $v.parent_id, $v.scope) | Where-Object { $_ }
        foreach ($id in $scope) {
          if ($id -ine $Manifest.scope.parent_id -and -not $id.StartsWith("$($Manifest.scope.parent_id)/", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Out-of-scope Azure operation at $($r.address)."
          }
        }
      }
    }
    if ($r.previous_address -and $r.change.before.id -ine $r.change.after.id) { throw 'Move changed ARM identity.' }
    if ('delete' -in $r.change.actions -and $r.type -notin $localTypes -and
        $r.change.before.id -notin $Manifest.owned_ids) { throw 'Lifecycle deletion includes an uncaptured Azure object (including subscription telemetry).' }
    $classification += @{ address = $r.address; classification = $kind }
  }
  if ($Noop) {
    foreach ($output in $Plan.output_changes.Values) {
      if (($output.actions -join ',') -ne 'no-op') { throw 'Output drift is not convergence.' }
    }
  }
  return $classification
}

function Get-MigrationResources($Module) {
  if ($null -eq $Module) { return }
  foreach ($resource in @($Module.resources | Where-Object { $null -ne $_ })) { if ($resource.mode -eq 'managed') { $resource } }
  foreach ($child in @($Module.child_modules | Where-Object { $null -ne $_ })) { Get-MigrationResources $child }
}

function Test-MigrationAbsence($Response, [int]$ExitCode) {
  if ($ExitCode -eq 0) { return $false }
  $text = (@($Response) | ForEach-Object { "$_" }) -join "`n"
  # ARM services use distinct structured codes; text mentioning a missing object
  # inside an authorization/transport failure must not be accepted as absence.
  return $text -match '"code"\s*:\s*"(ResourceNotFound|ResourceGroupNotFound|DeploymentNotFound|RoleAssignmentNotFound|LockNotFound|NotFound)"'
}

function Assert-MigrationVmSource([string]$Consumer, $Manifest) {
  # Registry archives need not contain .git. Verify resolved metadata AND immutable
  # release runtime bytes, including every local submodule, rather than rev-parse.
  if ($Manifest.upstream_vm_source -cne 'Azure/avm-res-compute-virtualmachine/azurerm' -or
      $Manifest.upstream_vm_version -cne '0.22.0' -or
      $Manifest.upstream_vm_sha -cne 'bac606921999710f478197474ed077c145e8c066') {
    throw 'VM release identity differs from the frozen Registry release.'
  }
  $modules = Get-Content (Join-Path $Consumer '.terraform/modules/modules.json') -Raw | ConvertFrom-Json -AsHashtable
  $vm = @($modules.Modules | Where-Object { $_.Key -ceq 'virtual_machine' })
  if ($vm.Count -ne 1 -or $vm[0].Source -cne "registry.terraform.io/$($Manifest.upstream_vm_source)" -or $vm[0].Version -cne $Manifest.upstream_vm_version) {
    throw 'VM dependency is not the exact Registry source/version.'
  }
  $interfaces = @($modules.Modules | Where-Object { $_.Key -ceq 'virtual_machine.avm_utl_interfaces' })
  if ($interfaces.Count -ne 1 -or $interfaces[0].Source -cne 'registry.terraform.io/Azure/avm-utl-interfaces/azure' -or $interfaces[0].Version -cne '0.10.0') {
    throw 'VM interfaces dependency differs from the released selection.'
  }
  $path = [IO.Path]::GetFullPath((Join-Path $Consumer $vm[0].Dir))
  $lines = @(Get-ChildItem $path -Recurse -File -Filter '*.tf' | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($path, $_.FullName).Replace('\', '/')
    if ($relative -notmatch '^(examples|tests|\.terraform)/') {
      "$relative $((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
  } | Sort-Object -CaseSensitive)
  $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))).ToLowerInvariant()
  # 50 runtime .tf files from the immutable bac6069 release archive, not main.
  if ($lines.Count -ne 50 -or $fingerprint -cne '68b7e9722e07e57538823c8bbab1e713930bca7bfe9c28e202d1930e38ada5a4') {
    throw 'Downloaded VM runtime differs from the immutable v0.22.0 release.'
  }
  return $path
}

function Assert-MigrationBaseline([string]$Consumer, [string]$Repository, [string]$Sha) {
  $modules = Get-Content (Join-Path $Consumer '.terraform/modules/modules.json') -Raw | ConvertFrom-Json -AsHashtable
  $matched = 0
  foreach ($module in $modules.Modules | Where-Object { $_.Source -like '*Azure/avm-res-compute-capacityreservationgroup/azurerm*' }) {
    if ($module.Version -cne '0.2.0') { throw 'Baseline did not resolve exactly release 0.2.0.' }
    $prefix = if ($module.Source -like '*//modules/capacity_reservation') { 'modules/capacity_reservation/' } else { '' }
    $paths = & git -C $Repository ls-tree -r --name-only $Sha
    if ($LASTEXITCODE -ne 0) { throw 'Pinned release commit unavailable for baseline byte verification.' }
    foreach ($path in $paths) {
      if (-not $path.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
      $relative = $path.Substring($prefix.Length)
      if ($relative.Contains('/') -or ($relative -notlike '*.tf' -and $relative -ne 'metadata.json')) { continue }
      $file = Join-Path $Consumer (Join-Path $module.Dir $relative)
      $actual = & git -C $Repository hash-object --no-filters $file
      if ($LASTEXITCODE -ne 0) { throw 'Could not hash downloaded release runtime file.' }
      $expected = & git -C $Repository rev-parse "${Sha}:$path"
      if ($LASTEXITCODE -ne 0 -or $actual -cne $expected) { throw "Registry release runtime differs from pinned release: $relative." }
    }
    $matched++
  }
  if ($matched -ne 2) { throw 'Expected both released root and standalone child calls.' }
}

function Get-MigrationWorkload([string]$TemplatePath, $Manifest) {
  $phase = $Manifest.phase
  $baseline = $phase.StartsWith('baseline')
  $name = if ($baseline) { 'baseline.tf.tftpl' } else { 'candidate.tf.tftpl' }
  $text = Get-Content (Join-Path $TemplatePath $name) -Raw
  $rootLock = if ($phase -in @('baseline-lock', 'relock')) { '{ kind = "ReadOnly", name = "migration-readonly" }' } else { 'null' }
  $childLock = if ($phase -eq 'child-extensions' -or ($Manifest.scenario -eq 'child_extensions' -and $phase -eq 'cleanup')) {
    '{ kind = "CanNotDelete", name = "migration-child", notes = "Candidate-only reservation lock" }'
  } else { 'null' }
  $childRbac = if ($childLock -ne 'null') {
    '{ reader = { role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7", principal_id = var.reader_principal_id, principal_type = var.reader_principal_type } }'
  } else { '{}' }
  $fanout = '{}'
  if ($Manifest.scenario -eq 'fanout' -and $phase -in @('fanout-add', 'fanout-reorder', 'fanout-subset', 'fanout-restore', 'parent-tags', 'cleanup')) {
    $zones = switch ($phase) {
      'fanout-reorder' { 'reverse(var.zones)' }; 'fanout-subset' { '[var.zones[0]]' }; default { 'var.zones' }
    }
    $fanout = "{ fanout = { name = `"fanout`", sku = { name = var.fanout_sku_name, capacity = 1 }, zones = $zones } }"
  }
  return $text.Replace('__CANDIDATE__', $Manifest.candidate_path.Replace('\', '/')).
    Replace('__TELEMETRY__', ($Manifest.scenario -eq 'telemetry').ToString().ToLowerInvariant()).
    Replace('__ROOT_LOCK__', $rootLock).Replace('__CHILD_LOCK__', $childLock).
    Replace('__CHILD_RBAC__', $childRbac).Replace('__FANOUT__', $fanout).
    Replace('__TAG__', $(if ($phase -eq 'parent-tags' -or ($Manifest.scenario -eq 'fanout' -and $phase -eq 'cleanup')) { 'metadata-change' } else { 'baseline' }))
}
