[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FixturePath,
  [Parameter(Mandatory)][string]$TerraformPath,
  [Parameter(Mandatory)][string]$CandidateSha,
  [ValidateSet('telemetry', 'readonly', 'child_extensions', 'fanout', 'vm')]
  [string[]]$Scenarios = @('telemetry', 'readonly', 'child_extensions', 'fanout', 'vm')
)
. "$PSScriptRoot/Migration.Helpers.ps1"
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Assert-MigrationExternalPath $FixturePath $repository
if (Test-Path $FixturePath) { throw 'Offline validation needs a new external directory.' }
New-Item -ItemType Directory -Path $FixturePath | Out-Null
Protect-MigrationDirectory $FixturePath
$scope = @{
  subscription_id = '00000000-0000-0000-0000-000000000000'
  tenant_id = '11111111-1111-1111-1111-111111111111'
  parent_id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/offline'
  location = 'eastus'; group_name = 'offline'; zone = '1'; zones = @('1', '2')
  sku_name = 'Standard_D2s_v5'; fanout_sku_name = 'Standard_D4s_v5'
  reader_principal_id = '22222222-2222-2222-2222-222222222222'; reader_principal_type = 'Group'
  ssh_public_key = 'mock-public-key-never-sent-to-Azure'
}
$scopeFile = Join-Path $FixturePath 'dummy-scope.json'
Write-MigrationJson $scopeFile $scope
$results = @()
foreach ($scenario in $Scenarios) {
  $fixture = Join-Path $FixturePath $scenario
  & "$PSScriptRoot/Invoke-Migration.ps1" -Operation Prepare -FixturePath $fixture -Scenario $scenario -CandidateSha $CandidateSha -ScopePath $scopeFile -TerraformPath $TerraformPath
  $consumer = Join-Path $fixture 'consumer'
  # This is deliberately not the live runner's phase ledger: only mocked schema/graph checks.
  $manifest = Get-Content (Join-Path $fixture 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
  $manifest.offline_only = $true
  Write-MigrationJson (Join-Path $fixture 'manifest.json') $manifest
  New-Item -ItemType Directory -Path (Join-Path $consumer 'tests/offline') -Force | Out-Null
  foreach ($phase in Get-MigrationPhases $scenario) {
    if ($phase -eq 'cleanup') { continue } # Normal Azure destroy is never simulated as cleanup proof.
    $manifest.phase = $phase
    [IO.File]::WriteAllText((Join-Path $consumer 'workload/main.tf'), (Get-MigrationWorkload (Join-Path $PSScriptRoot 'templates') $manifest))
    if ($scenario -eq 'vm') {
      $vm = Get-Content (Join-Path $consumer 'main.vm.tf') -Raw
      $vm = $vm.Replace('true ? module.estate', 'ENABLED ? module.estate').Replace('false ? module.estate', 'ENABLED ? module.estate')
      $vm = $vm.Replace('ENABLED', $(if ($phase -eq 'vm-disassociate') { 'false' } else { 'true' }))
      [IO.File]::WriteAllText((Join-Path $consumer 'main.vm.tf'), $vm)
    }
    $groupLabel = if ($phase.StartsWith('baseline')) { 'capacity_reservation_group' } else { 'this' }
    $childLabel = if ($phase.StartsWith('baseline')) { 'capacity_reservation' } else { 'this' }
    $test = @'
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id = "11111111-1111-1111-1111-111111111111"
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/offline"
      output = { properties = { reservationId = "mock-platform-id" } }
    }
  }
  mock_data "azapi_resource_list" {
    override_during = plan
    defaults = {
      output = {
        value = [{
          id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          properties = { roleName = "Reader" }
        }]
      }
    }
  }
}
mock_provider "azurerm" {}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "tls" {}
mock_provider "terraform" {}
run "schema_and_graph_only" {
  command = apply
  __VM_ASSERTIONS__
  override_resource {
    target = module.estate["existing"].module.group.azapi_resource.__GROUP__
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/offline/providers/Microsoft.Compute/capacityReservationGroups/offline" }
  }
  override_resource {
    target = module.estate["existing"].module.reservation["retained"].azapi_resource.__CHILD__
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/offline/providers/Microsoft.Compute/capacityReservationGroups/offline/capacityReservations/retained"
      output = { properties = { reservationId = "mock-platform-id" } }
    }
  }
  assert {
    condition = output.identities.platform_id == "mock-platform-id"
    error_message = "Standalone output compatibility failed in mocked fixture."
  }
}
run "mocked_normal_plan" {
  command = plan
}
'@
    $vmAssertions = ''
    if ($scenario -eq 'vm') {
      $association = if ($phase -eq 'vm-disassociate') {
        'module.virtual_machine.resource.body.properties.capacityReservation == null'
      } else {
        'module.virtual_machine.resource.body.properties.capacityReservation.capacityReservationGroup.id == output.identities.group_id'
      }
      $vmAssertions = @"
  assert {
    condition = $association
    error_message = "Released VM must retain the direct group ID, or explicit null only in the disassociation phase."
  }
  assert {
    condition = (
      module.virtual_machine.resource.body.properties.hardwareProfile.vmSize == var.sku_name &&
      module.virtual_machine.resource.body.zones[0] == var.zone &&
      module.virtual_machine.admin_generated_ssh_private_key == "no_key"
    )
    error_message = "Released VM must match approved reservation SKU/zone without generating private credentials."
  }
"@
    }
    [IO.File]::WriteAllText((Join-Path $consumer 'tests/offline/fixture.tftest.hcl'), $test.Replace('__GROUP__', $groupLabel).Replace('__CHILD__', $childLabel).Replace('__VM_ASSERTIONS__', $vmAssertions))
    $prefix = Join-Path $fixture "audit/offline-$phase"
    Invoke-MigrationCommand $TerraformPath @("-chdir=$consumer", 'init', '-input=false', '-no-color', '-upgrade=false') "$prefix-init.json" | Out-Null
    if ($scenario -eq 'vm') { Assert-MigrationVmSource $consumer $manifest | Out-Null }
    if ($phase.StartsWith('baseline')) { Assert-MigrationBaseline $consumer $repository $manifest.baseline_sha }
    Invoke-MigrationCommand $TerraformPath @("-chdir=$consumer", 'validate', '-no-color') "$prefix-validate.json" | Out-Null
    $eventsText = Invoke-MigrationCommand $TerraformPath @("-chdir=$consumer", 'test', '-test-directory=tests/offline', '-no-color', '-json', '-verbose') "$prefix-mocks.json"
    $events = @($eventsText -split "`n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
    $mockPlan = @($events | Where-Object { $_.type -eq 'test_plan' -and $_.'@testrun' -eq 'mocked_normal_plan' })[-1].test_plan
    if (-not $mockPlan) { throw 'Mock plan event missing; do not infer saved-plan inspection from apply success.' }
    $classifications = @(Assert-MigrationPlan $mockPlan $manifest -Noop)
    Write-MigrationJson "$prefix-mock-plan-classifications.json" $classifications
    $results += @{ scenario = $scenario; phase = $phase; result = 'mock-init-validate-apply-plan-guard-only'; azure_tested = $false }
    "$scenario/$phase offline schema/graph PASS"
  }
}
Write-MigrationJson (Join-Path $FixturePath 'offline-results.json') $results
"PASS: $($results.Count) isolated offline phase checks. Not applied released-state migration, persisted Azure behavior, HTTP serialization, normal cleanup or E2E proof."
