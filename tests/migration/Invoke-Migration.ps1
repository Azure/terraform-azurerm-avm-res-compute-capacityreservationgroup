[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Prepare', 'Stage', 'Init', 'Plan', 'Apply', 'Readback', 'Noop', 'Deallocate', 'VerifyCleanup')]
  [string]$Operation,
  [Parameter(Mandatory)][string]$FixturePath,
  [ValidateSet('telemetry', 'readonly', 'child_extensions', 'fanout', 'vm')][string]$Scenario,
  [string]$CandidateSha,
  [string]$ScopePath,
  [string]$Phase,
  [string]$ApprovalPath,
  [Parameter(Mandatory)][string]$TerraformPath
)

$audit = $null
. "$PSScriptRoot/Migration.Helpers.ps1"
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$FixturePath = [IO.Path]::GetFullPath($FixturePath)
Assert-MigrationExternalPath $FixturePath $repository
if (-not (Test-Path -LiteralPath $TerraformPath -PathType Leaf)) { throw 'Supply the installed Avm.Authoring-managed Terraform executable.' }
$manifestPath = Join-Path $FixturePath 'manifest.json'
$consumer = Join-Path $FixturePath 'consumer'
$templates = Join-Path $PSScriptRoot 'templates'
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($variable in Get-ChildItem Env: | Where-Object { $_.Name -like 'TF_CLI_ARGS*' -or $_.Name -in @('TF_WORKSPACE', 'TF_DATA_DIR') }) {
  if ($variable.Value) { throw 'Clear ambient Terraform CLI/workspace/data-directory overrides; this runner owns the exact command and local state boundary.' }
}

if ($Operation -eq 'Prepare') {
  if (Test-Path -LiteralPath $FixturePath) { throw 'Use a new fixture directory. Never overwrite another run/state.' }
  if ($CandidateSha -cnotmatch '^[0-9a-f]{40}$' -or -not $Scenario -or -not $ScopePath) { throw 'Prepare requires scenario, full immutable candidate SHA and explicit scope JSON.' }
  $resolved = & git -C $repository rev-parse "$CandidateSha^{commit}"
  if ($LASTEXITCODE -ne 0 -or $resolved -cne $CandidateSha) { throw 'Candidate commit unavailable.' }
  $scope = Get-Content -LiteralPath $ScopePath -Raw | ConvertFrom-Json -AsHashtable
  foreach ($key in @('subscription_id', 'tenant_id', 'parent_id', 'location', 'group_name', 'zone', 'zones', 'sku_name', 'fanout_sku_name', 'reader_principal_id', 'reader_principal_type')) {
    if (-not $scope[$key]) { throw "Required scope input: $key." }
  }
  if ($scope.parent_id -notmatch "^/subscriptions/$([regex]::Escape($scope.subscription_id))/resourceGroups/[^/]+$") { throw 'Scope must be an isolated RG in the explicit subscription.' }
  if ($scope.zone -notin $scope.zones -or @($scope.zones | Sort-Object -Unique).Count -ne @($scope.zones).Count) { throw 'Fixed group envelope must contain the standalone zone with no duplicates.' }
  if ($Scenario -eq 'fanout' -and (@($scope.zones).Count -lt 2 -or $scope.sku_name -eq $scope.fanout_sku_name)) { throw 'Fan-out needs at least two approved zones and a distinct SKU.' }
  if ($Scenario -eq 'vm' -and -not $scope.ssh_public_key) { throw 'VM scenario requires an operator-provided real public key.' }
  if ($scope.reader_principal_type -notin @('User', 'Group', 'ServicePrincipal')) { throw 'Invalid Reader principal type.' }
  New-Item -ItemType Directory -Path $FixturePath | Out-Null
  Protect-MigrationDirectory $FixturePath
  foreach ($dir in @('consumer', 'consumer/workload', 'candidate', 'audit')) { New-Item -ItemType Directory -Path (Join-Path $FixturePath $dir) | Out-Null }
  $archive = Join-Path $FixturePath 'candidate.zip'
  & git -C $repository archive --format=zip "--output=$archive" $CandidateSha
  if ($LASTEXITCODE -ne 0) { throw 'Immutable candidate archive failed.' }
  Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $FixturePath 'candidate')
  $manifest = [ordered]@{
    schema_version = 1; scenario = $Scenario; phase = 'baseline'
    baseline_release = '0.2.0'; baseline_sha = 'c1ca05054fa11ec5b18ba327210801c7a25d92cd'
    candidate_sha = $CandidateSha; candidate_path = (Join-Path $FixturePath 'candidate')
    scope = $scope; owned_ids = @(); owned_apis = @{}; completed = @(); noops = 0; readback = $false
    candidate_hashes = (Get-MigrationHashes (Join-Path $FixturePath 'candidate'))
    template_hashes = (Get-MigrationHashes $templates)
    vm_consumer_hashes = $(if ($Scenario -eq 'vm') { Get-MigrationHashes (Join-Path $repository 'examples/vm_consumption') '*.tf' } else { $null })
    upstream_vm_source = $(if ($Scenario -eq 'vm') { 'Azure/avm-res-compute-virtualmachine/azurerm' } else { $null })
    upstream_vm_version = $(if ($Scenario -eq 'vm') { '0.22.0' } else { $null })
    upstream_vm_sha = $(if ($Scenario -eq 'vm') { 'bac606921999710f478197474ed077c145e8c066' } else { $null })
    config_hashes = @{}; plan_hash = ''; plan_file = ''; plan_json = ''
  }
  foreach ($name in @('terraform', 'variables')) {
    Copy-Item (Join-Path $templates "$name.tf.tftpl") (Join-Path $consumer "$name.tf")
  }
  Copy-Item (Join-Path $templates 'root.tf.tftpl') (Join-Path $consumer 'main.tf')
  Copy-Item (Join-Path $templates 'workload.variables.tf.tftpl') (Join-Path $consumer 'workload/variables.tf')
  Copy-Item (Join-Path $templates 'workload.outputs.tf.tftpl') (Join-Path $consumer 'workload/outputs.tf')
  # Child configuration declares requirements only; provider configurations stay at root.
  $requirements = (Get-Content (Join-Path $templates 'terraform.tf.tftpl') -Raw).Split('provider "azapi"')[0]
  [IO.File]::WriteAllText((Join-Path $consumer 'workload/terraform.tf'), $requirements, $utf8)
  Write-MigrationJson (Join-Path $consumer 'scope.auto.tfvars.json') $scope
  Write-MigrationJson $manifestPath $manifest
} else {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
  if ($manifest.offline_only) { throw 'Offline validation artifacts cannot be promoted into live fixtures.' }
  Assert-MigrationHashes $manifest.candidate_path $manifest.candidate_hashes
  Assert-MigrationHashes $templates $manifest.template_hashes
  if ($manifest.vm_consumer_hashes) { Assert-MigrationHashes (Join-Path $repository 'examples/vm_consumption') $manifest.vm_consumer_hashes '*.tf' }
  if ($manifest.vm_runtime_hashes) { Assert-MigrationHashes $manifest.vm_module_path $manifest.vm_runtime_hashes '*.tf' }
  Assert-MigrationHashes $consumer $manifest.config_hashes '*.tf'
  $actualScope = Get-Content (Join-Path $consumer 'scope.auto.tfvars.json') -Raw | ConvertFrom-Json -AsHashtable
  if (($actualScope | ConvertTo-Json -Depth 100 -Compress) -cne ($manifest.scope | ConvertTo-Json -Depth 100 -Compress)) { throw 'Scope input drift.' }
  if ($manifest.lock_hash -and (Get-FileHash (Join-Path $consumer '.terraform.lock.hcl') -Algorithm SHA256).Hash -cne $manifest.lock_hash) { throw 'Dependency lock drift; do not silently re-resolve providers.' }
  $statePath = Join-Path $consumer 'terraform.tfstate'
  if ($manifest.state_hash) {
    if (-not (Test-Path $statePath) -or (Get-FileHash $statePath -Algorithm SHA256).Hash -cne $manifest.state_hash) { throw 'Local consumer state changed outside the approved apply; no copy/restore/state surgery is supported.' }
    $currentState = Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable
    if ($currentState.lineage -cne $manifest.state_lineage) { throw 'State lineage changed.' }
  } elseif (Test-Path $statePath) {
    throw 'Unexpected pre-existing state before the baseline apply.'
  }
}

$audit = Join-Path $FixturePath ("audit/{0}-{1}-{2}" -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'), $manifest.phase, $Operation)
trap {
  $auditVariable = Get-Variable -Name audit -ErrorAction SilentlyContinue
  if ($auditVariable -and $auditVariable.Value) {
    Write-MigrationJson "$($auditVariable.Value).failure.json" @{
      operation = $Operation; phase = $manifest.phase
      failed_utc = [DateTimeOffset]::UtcNow; error = $_.Exception.Message
    }
  }
  throw
}
function Invoke-Terraform([string[]]$Arguments, [string]$Suffix = '', [int[]]$Codes = @(0)) {
  Invoke-MigrationCommand $TerraformPath (@("-chdir=$consumer") + $Arguments) "$audit$Suffix.command.json" $Codes
}
function Save-Manifest { Write-MigrationJson $manifestPath $manifest }
function Assert-CurrentWorkspace {
  $workspace = (Invoke-Terraform @('workspace', 'show') '-workspace').Trim()
  if ($workspace -cne 'default') { throw 'Fixture must retain the default local workspace.' }
  if (Get-ChildItem $consumer -File -Filter '*backend*') { throw 'Do not change backend in this fixture.' }
}
function Assert-WriteApproval([string]$Kind, [string]$Hash = '') {
  if (-not $ApprovalPath) { throw 'No write without an explicit phase/operation/plan approval JSON.' }
  $approval = Get-Content -LiteralPath $ApprovalPath -Raw | ConvertFrom-Json -AsHashtable
  Assert-MigrationApproval $approval $manifest $Kind $Hash
  Assert-MigrationContext $manifest.scope
  Assert-CurrentWorkspace
}
function Write-Configuration {
  [IO.File]::WriteAllText((Join-Path $consumer 'workload/main.tf'), (Get-MigrationWorkload $templates $manifest), $utf8)
  if ($manifest.scenario -eq 'vm') {
    # Reuse the example's proven AzAPI VM/network shape, not a second VM writer.
    $vmPath = Join-Path $repository 'examples/vm_consumption/main.tf'
    $vmText = Get-Content $vmPath -Raw
    $vmText = $vmText.Substring($vmText.IndexOf('module "virtual_machine"'))
    $enabled = if ($manifest.phase -eq 'vm-disassociate') { 'false' } else { 'true' }
    $vmText = $vmText.Replace('var.capacity_reservation_enabled', $enabled).
      Replace('module.capacity_reservation_group.resource_id', 'module.estate["existing"].identities.group_id').
      Replace('module.capacity_reservation_group]', 'module.estate]').
      Replace('azapi_resource.resource_group.id', 'var.parent_id').Replace('var.vm_size', 'var.sku_name').
      Replace('var.resource_group_name', 'split("/", var.parent_id)[4]').Replace('var.enable_telemetry', 'false').
      Replace('var.ssh_public_key == null ? azapi_resource_action.ssh_key_pair[0].output.publicKey : var.ssh_public_key', 'var.ssh_public_key')
    [IO.File]::WriteAllText((Join-Path $consumer 'main.vm.tf'), $vmText, $utf8)
    $network = (Get-Content (Join-Path $repository 'examples/vm_consumption/main.network.tf') -Raw).
      Replace('azapi_resource.resource_group.id', 'var.parent_id')
    [IO.File]::WriteAllText((Join-Path $consumer 'main.network.tf'), $network, $utf8)
  }
  $manifest.config_hashes = Get-MigrationHashes $consumer '*.tf'
  $manifest.plan_hash = ''; $manifest.plan_file = ''; $manifest.plan_json = ''
  $manifest.noops = 0; $manifest.readback = $false
  Save-Manifest
}
function Get-AzureObject([string]$Id, [string]$ApiVersion) {
  # Read-only independent ARM surface; suppress CLI error bodies (may identify private scopes).
  $json = & az rest --method get --url "https://management.azure.com${Id}?api-version=$ApiVersion" --output json --only-show-errors 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Independent readback failed; no success recorded. Inspect this fixture privately." }
  return ($json | ConvertFrom-Json -AsHashtable)
}

switch ($Operation) {
  Prepare { Write-Configuration; 'Prepared protected external baseline fixture; no Azure call or write.' }
  Stage {
    Assert-CurrentWorkspace
    Assert-MigrationAdvance $manifest $Phase
    if ($Phase -in @('vm-disassociate', 'vm-reassociate')) {
      $manifest.deallocated = $false
    }
    $manifest.phase = $Phase
    Write-Configuration
    "Staged $Phase in the SAME consumer, default workspace and state. No Azure write."
  }
  Init {
    Assert-CurrentWorkspace
    $lock = Join-Path $consumer '.terraform.lock.hcl'
    $mode = if (Test-Path $lock) { '-lockfile=readonly' } else { '-upgrade=false' }
    Invoke-Terraform @('init', '-input=false', '-no-color', $mode) '-init' | Out-Null
    Invoke-Terraform @('validate', '-no-color') '-validate' | Out-Null
    if ($manifest.scenario -eq 'vm') {
      $manifest.vm_module_path = Assert-MigrationVmSource $consumer $manifest
      $vmHashes = Get-MigrationHashes $manifest.vm_module_path '*.tf'
      if ($manifest.vm_runtime_hashes) { Assert-MigrationHashes $manifest.vm_module_path $manifest.vm_runtime_hashes '*.tf' }
      else { $manifest.vm_runtime_hashes = $vmHashes }
    }
    # Keep both providers/checksums; never throw away the baseline lock during conversion.
    if ($manifest.phase.StartsWith('baseline')) { Assert-MigrationBaseline $consumer $repository $manifest.baseline_sha }
    Copy-Item $lock "$audit.lock.hcl"
    $manifest.lock_hash = (Get-FileHash $lock -Algorithm SHA256).Hash
    Save-Manifest
    'Initialized/validated only. No baseline apply or migration proof.'
  }
  Plan {
    Assert-CurrentWorkspace
    Assert-MigrationContext $manifest.scope
    if ($manifest.phase.StartsWith('baseline')) { Assert-MigrationBaseline $consumer $repository $manifest.baseline_sha }
    $manifest.plan_hash = ''; $manifest.plan_file = ''; $manifest.plan_json = ''
    Save-Manifest
    $planFile = "$audit.tfplan"
    $args = @('plan', '-input=false', '-no-color', "-out=$planFile")
    if ($manifest.phase -eq 'cleanup') { $args += '-destroy' }
    Invoke-Terraform $args '-plan' | Out-Null
    $plan = Invoke-Terraform @('show', '-json', $planFile) '-show' | ConvertFrom-Json -AsHashtable
    $classification = @(Assert-MigrationPlan $plan $manifest)
    Write-MigrationJson "$audit.classification.json" $classification
    Write-MigrationJson "$audit.plan.json" $plan
    $manifest.plan_file = $planFile; $manifest.plan_json = "$audit.plan.json"
    $manifest.plan_hash = (Get-FileHash $planFile -Algorithm SHA256).Hash
    Save-Manifest
    "Saved/guarded plan SHA256 $($manifest.plan_hash). Independently inspect bodies, unknowns, moves, scopes and classifications before authorizing it."
  }
  Apply {
    if (-not $manifest.plan_hash -or (Get-FileHash $manifest.plan_file -Algorithm SHA256).Hash -cne $manifest.plan_hash) { throw 'Saved plan missing/changed.' }
    # Decode the actual binary again, not a user-editable JSON surrogate.
    $plan = Invoke-Terraform @('show', '-json', $manifest.plan_file) '-reinspect' | ConvertFrom-Json -AsHashtable
    Assert-MigrationPlan $plan $manifest | Out-Null
    Assert-WriteApproval 'Apply' $manifest.plan_hash
    if ($manifest.phase.StartsWith('baseline')) { Assert-MigrationBaseline $consumer $repository $manifest.baseline_sha }
    if ($manifest.phase -eq 'baseline') {
      $objects = & az resource list --resource-group (($manifest.scope.parent_id -split '/')[-1]) --subscription $manifest.scope.subscription_id --output json --only-show-errors | ConvertFrom-Json
      if ($LASTEXITCODE -ne 0 -or @($objects).Count -ne 0) { throw 'Baseline requires an empty isolated RG; existing resources are not adopted.' }
    }
    if ($manifest.phase -in @('vm-disassociate', 'vm-reassociate')) {
      $vm = Get-AzureObject "$($manifest.scope.parent_id)/providers/Microsoft.Compute/virtualMachines/vm-consumption/instanceView" '2024-11-01'
      if ('PowerState/deallocated' -notin @($vm.statuses.code)) { throw 'Actual VM is not deallocated.' }
    }
    $manifest.readback = $false; $manifest.noops = 0
    $manifest.completed = @($manifest.completed | Where-Object { $_ -cne $manifest.phase })
    Save-Manifest
    try {
      Invoke-Terraform @('apply', '-input=false', '-no-color', $manifest.plan_file) '-apply' | Out-Null
    } finally {
      # Any retry needs a newly saved/inspected plan and exact-plan approval.
      $manifest.plan_hash = ''
      $statePath = Join-Path $consumer 'terraform.tfstate'
      if (Test-Path $statePath) {
        $appliedState = Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable
        $manifest.state_lineage = $appliedState.lineage
        $manifest.state_hash = (Get-FileHash $statePath -Algorithm SHA256).Hash
      }
      Save-Manifest
    }
    if ($manifest.phase -in @('baseline-unlock', 'cleanup-unlock')) {
      # Lock deletion propagation is distinct from Terraform's successful DELETE.
      Start-Sleep -Seconds 30
    }
    $manifest.completed = @($manifest.completed) + @($manifest.phase)
    $manifest.plan_hash = ''
    Save-Manifest
    'Applied only the inspected saved plan. Readback/convergence/cleanup are not implied.'
  }
  Readback {
    if ($manifest.phase -notin $manifest.completed -or $manifest.phase -eq 'cleanup') { throw 'Readback requires successful current-phase apply; use VerifyCleanup after destroy.' }
    Assert-MigrationContext $manifest.scope
    Assert-CurrentWorkspace
    $state = Invoke-Terraform @('show', '-json') '-state' | ConvertFrom-Json -AsHashtable
    $reads = [ordered]@{}
    $currentChildren = [ordered]@{}
    $expectedChildren = @()
    foreach ($r in @(Get-MigrationResources $state.values.root_module)) {
      if ($r.type -notin @('azapi_resource', 'azurerm_role_assignment', 'azurerm_management_lock')) { continue }
      $v = $r.values
      $api = if ($r.type -eq 'azurerm_role_assignment') { '2022-04-01' } elseif ($r.type -eq 'azurerm_management_lock') { '2016-09-01' } else { ($v.type -split '@')[1] }
      $object = Get-AzureObject $v.id $api
      if ($object.id -ine $v.id) { throw 'Independent GET identity differs from state.' }
      $reads[$v.id] = @{ api = $api; object = $object }
      if ($v.id -notin $manifest.owned_ids) { $manifest.owned_ids = @($manifest.owned_ids) + @($v.id) }
      $manifest.owned_apis[$v.id] = $api
      if ($r.type -eq 'azapi_resource' -and $v.type -like 'Microsoft.Compute/capacityReservationGroups/capacityReservations@*') {
        if ($object.sku.name -cne $v.body.sku.name -or $object.sku.capacity -ne $v.body.sku.capacity -or
            (($object.zones | ConvertTo-Json -Compress) -cne ($v.body.zones | ConvertTo-Json -Compress))) { throw 'Reservation SKU/capacity/zone did not persist.' }
        if (@($object.tags.Keys).Count -ne @($v.tags.Keys).Count) { throw 'Reservation tag set differs.' }
        foreach ($tag in $v.tags.Keys) { if ($object.tags[$tag] -cne $v.tags[$tag]) { throw 'Reservation tags did not persist.' } }
        $expectedChildren += $object.id.ToLowerInvariant()
        $currentChildren[$r.address] = @{ id = $object.id; platform_id = $object.properties.reservationId }
      }
      if ($r.address -eq 'module.virtual_machine.azapi_resource.this_linux_virtual_machine[0]') {
        $diskId = $object.properties.storageProfile.osDisk.managedDisk.id
        if (-not $diskId.StartsWith("$($manifest.scope.parent_id)/", [StringComparison]::OrdinalIgnoreCase)) { throw 'VM disk outside the isolated scope.' }
        $disk = Get-AzureObject $diskId '2024-03-02'
        if ($disk.id -ine $diskId) { throw 'Independent VM disk identity differs.' }
        $reads[$diskId] = @{ api = '2024-03-02'; object = $disk }
        if ($diskId -notin $manifest.owned_ids) { $manifest.owned_ids = @($manifest.owned_ids) + @($diskId) }
        $manifest.owned_apis[$diskId] = '2024-03-02'
      }
    }
    $identity = $state.values.outputs.identities.value
    $child = $reads[$identity.child_id].object
    $group = $reads[$identity.group_id].object
    if ($child.properties.reservationId -cne $identity.platform_id -or $identity.child_id -notin @($group.properties.capacityReservations.id)) { throw 'Standalone identity/platform GUID or group membership lost.' }
    $actualChildren = @($group.properties.capacityReservations.id | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
    if (($actualChildren -join '|') -cne (($expectedChildren | Sort-Object) -join '|')) { throw 'Group membership has missing/stale/externally added children. Inspect/reconcile, never hide drift.' }
    $childSnapshot = Join-Path $FixturePath 'previous-children.json'
    if (Test-Path $childSnapshot) {
      $previousChildren = Get-Content $childSnapshot -Raw | ConvertFrom-Json -AsHashtable
      foreach ($address in $currentChildren.Keys) {
        if ($previousChildren.Contains($address) -and (
            $currentChildren[$address].id -ine $previousChildren[$address].id -or
            $currentChildren[$address].platform_id -cne $previousChildren[$address].platform_id)) { throw 'Retained child identity/platform GUID changed across a phase.' }
      }
    }
    $baselineFile = Join-Path $FixturePath 'baseline-identities.json'
    if ($manifest.phase -eq 'baseline') {
      Write-MigrationJson $baselineFile $identity
    } else {
      $original = Get-Content $baselineFile -Raw | ConvertFrom-Json -AsHashtable
      foreach ($key in @('group_id', 'child_id', 'platform_id')) { if ($original[$key] -ine $identity[$key]) { throw "Retained identity changed: $key." } }
    }
    $role = @($reads.Values | Where-Object { $_.object.type -ieq 'Microsoft.Authorization/roleAssignments' })
    foreach ($assignment in $role) {
      if ($assignment.object.properties.principalId -ine $manifest.scope.reader_principal_id -or
          $assignment.object.properties.principalType -ine $manifest.scope.reader_principal_type -or
          $assignment.object.properties.roleDefinitionId -notlike '*/acdd72a7-3385-48ef-bd42-f606fba81ae7') { throw 'Reader principal/type/definition did not persist.' }
    }
    $rootRole = @($role | Where-Object { $_.object.id -like "$($manifest.scope.parent_id)/providers/Microsoft.Authorization/roleAssignments/*" })
    if ($rootRole.Count -ne 1) { throw 'Expected the one retained RG-scoped Reader.' }
    $roleIdentityFile = Join-Path $FixturePath 'baseline-reader.json'
    if ($manifest.phase -eq 'baseline') { Write-MigrationJson $roleIdentityFile $rootRole[0].object.id }
    elseif ((Get-Content $roleIdentityFile -Raw | ConvertFrom-Json) -ine $rootRole[0].object.id) { throw 'Retained Reader GUID/scope changed.' }
    if ($manifest.phase -eq 'child-extensions') {
      $childRoles = @($role | Where-Object { $_.object.id -like "$($identity.child_id)/providers/Microsoft.Authorization/roleAssignments/*" })
      $childLock = $reads["$($identity.child_id)/providers/Microsoft.Authorization/locks/migration-child"].object
      if ($childRoles.Count -ne 1 -or $childLock.properties.level -cne 'CanNotDelete' -or
          $childLock.properties.notes -cne 'Candidate-only reservation lock') { throw 'Child-scoped extensions absent or wrong scope/kind/notes.' }
    }
    if ($manifest.phase -in @('baseline-lock', 'relock')) {
      $rootLock = $reads["$($manifest.scope.parent_id)/providers/Microsoft.Authorization/locks/migration-readonly"].object
      if ($rootLock.properties.level -cne 'ReadOnly' -or
          $rootLock.properties.notes -cne 'Cannot delete or modify the resource or its child resources.') { throw 'ReadOnly lock kind/notes did not persist at the retained RG scope.' }
    }
    if ($manifest.phase -in @('baseline-unlock', 'cleanup-unlock')) {
      $lockId = "$($manifest.scope.parent_id)/providers/Microsoft.Authorization/locks/migration-readonly"
      $response = & az rest --method get --url "https://management.azure.com${lockId}?api-version=2016-09-01" --only-show-errors 2>&1
      if (-not (Test-MigrationAbsence $response $LASTEXITCODE)) { throw 'Unlocked lock absence not independently proved.' }
    }
    if ($manifest.scenario -eq 'vm') {
      $vmId = "$($manifest.scope.parent_id)/providers/Microsoft.Compute/virtualMachines/vm-consumption"
      $expected = if ($manifest.phase -eq 'vm-disassociate') { $null } else { $identity.group_id }
      $properties = $reads[$vmId].object.properties
      $association = $properties.capacityReservation.capacityReservationGroup.id
      if ($association -ine $expected) { throw 'VM-owned group association did not persist.' }
      if ($properties.hardwareProfile.vmSize -cne $manifest.scope.sku_name) { throw 'VM SKU no longer matches the reserved size.' }
      $vmZones = @($reads[$vmId].object.zones)
      if ($vmZones.Count -ne 1 -or $manifest.scope.zone -notin $vmZones) { throw 'VM zone no longer matches the retained reservation zone.' }
      $associated = @($group.properties.virtualMachinesAssociated.id)
      if (($expected -and $vmId -notin $associated) -or (-not $expected -and $vmId -in $associated)) { throw 'Group VM-association projection has not converged.' }
      $vmIdentity = @{
        arm_id = $reads[$vmId].object.id
        platform_id = $properties.vmId
        disk_id = $properties.storageProfile.osDisk.managedDisk.id
        nic_ids = @($properties.networkProfile.networkInterfaces.id)
      }
      if (-not $vmIdentity.platform_id -or $vmIdentity.nic_ids.Count -ne 1) { throw 'VM platform GUID or single-NIC footprint is missing.' }
      if ($reads[$vmIdentity.disk_id].object.sku.name -cne 'Premium_LRS' -or
          -not $properties.osProfile.linuxConfiguration.disablePasswordAuthentication -or
          $properties.storageProfile.osDisk.deleteOption -cne 'Delete' -or
          @($properties.storageProfile.dataDisks | Where-Object { $null -ne $_ }).Count -ne 0) { throw 'Approved VM/disk/authentication footprint differs.' }
      foreach ($nicId in $vmIdentity.nic_ids) {
        $nic = $reads[$nicId].object
        if (-not $nic -or @($nic.properties.ipConfigurations | Where-Object { $_.properties.publicIPAddress.id }).Count -gt 0) { throw 'VM NIC was not independently read or has a public IP.' }
      }
      $vmIdentityFile = Join-Path $FixturePath 'baseline-vm-identities.json'
      if ($manifest.phase -eq 'baseline') { Write-MigrationJson $vmIdentityFile $vmIdentity }
      else {
        $originalVm = Get-Content $vmIdentityFile -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in @('arm_id', 'platform_id', 'disk_id')) {
          if ($originalVm[$key] -ine $vmIdentity[$key]) { throw "Retained VM identity changed: $key." }
        }
        if (($originalVm.nic_ids -join '|') -ine ($vmIdentity.nic_ids -join '|')) { throw 'Retained VM NIC identity changed.' }
      }
    }
    Write-MigrationJson "$audit.readbacks.json" $reads
    Write-MigrationJson $childSnapshot $currentChildren
    $manifest.readback = $true
    Save-Manifest
    'Independent ARM readbacks captured; not a refreshed no-op or serialized-request proof.'
  }
  Noop {
    if (-not $manifest.readback -or $manifest.phase -notin $manifest.completed) { throw 'Readback must precede convergence.' }
    Assert-MigrationContext $manifest.scope
    Assert-CurrentWorkspace
    try {
      Invoke-Terraform @('plan', '-input=false', '-no-color', "-out=$audit.tfplan") '-plan' | Out-Null
      $plan = Invoke-Terraform @('show', '-json', "$audit.tfplan") '-show' | ConvertFrom-Json -AsHashtable
      $classification = @(Assert-MigrationPlan $plan $manifest -Noop)
    } catch {
      $manifest.noops = 0
      Save-Manifest
      throw
    }
    Write-MigrationJson "$audit.classification.json" $classification
    $manifest.noops++
    Save-Manifest
    "Normal refreshed convergence inspection $($manifest.noops); timestamp-only telemetry remains explicitly classified, not a literal Terraform no-op."
  }
  Deallocate {
    if ($manifest.scenario -ne 'vm' -or $manifest.phase -notin @('candidate', 'vm-disassociate') -or $manifest.noops -lt 2) { throw 'Deallocation is a separately approved post-upgrade VM phase only.' }
    Assert-WriteApproval 'Deallocate'
    $vmId = "$($manifest.scope.parent_id)/providers/Microsoft.Compute/virtualMachines/vm-consumption"
    if ($vmId -notin $manifest.owned_ids) { throw 'Cannot deallocate an uncaptured VM.' }
    Invoke-MigrationCommand 'az' @('rest', '--method', 'post', '--url', "https://management.azure.com$vmId/deallocate?api-version=2024-11-01", '--output', 'none', '--only-show-errors') "$audit.deallocate.json" | Out-Null
    # Do not assume a 202 means deallocated; bounded read-only polling, no repeat POST.
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(10)
    do {
      $view = Get-AzureObject "$vmId/instanceView" '2024-11-01'
      if ('PowerState/deallocated' -in @($view.statuses.code)) { break }
      Start-Sleep -Seconds 10
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    if ('PowerState/deallocated' -notin @($view.statuses.code)) { throw 'Deallocation not verified within ten minutes; preserve failure and inspect privately.' }
    $manifest.deallocated = $true
    Save-Manifest
    'Owned VM independently confirmed deallocated; association has not been changed.'
  }
  VerifyCleanup {
    if ($manifest.phase -ne 'cleanup' -or 'cleanup' -notin $manifest.completed) { throw 'Normal candidate destroy must succeed first.' }
    Assert-MigrationContext $manifest.scope
    Assert-CurrentWorkspace
    $addresses = (Invoke-Terraform @('state', 'list') '-state-list').Trim()
    if ($addresses) { throw 'State not empty after normal candidate destroy.' }
    foreach ($id in $manifest.owned_ids) {
      # Explicitly accept only ResourceNotFound/404; denied reads are NOT absence.
      $api = $manifest.owned_apis[$id]
      if (-not $api) { throw 'Missing independently exercised API version for a captured cleanup ID.' }
      $response = & az rest --method get --url "https://management.azure.com${id}?api-version=$api" --only-show-errors 2>&1
      if (-not (Test-MigrationAbsence $response $LASTEXITCODE)) { throw 'Captured object absence not proved. No broad RG cleanup is attempted.' }
    }
    Write-MigrationJson "$audit.final.json" @{ state_empty = $true; captured_objects_absent = $true; parent_rg_owned = $false; checked_utc = [DateTimeOffset]::UtcNow }
    'Normal candidate cleanup verified for captured IDs and empty state. External setup RG is not deleted.'
  }
}
