param(
  [Parameter(Mandatory)]
  [string] $TerraformPath
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$relative = ".terraform\d$([guid]::NewGuid().ToString('N').Substring(0, 6))"
$directory = Join-Path $repository $relative
[void][IO.Directory]::CreateDirectory($directory)
$roles = @(
  'module.m.azapi_resource.role_assignments["reader"]',
  'module.m.module.capacity_reservation["1:c:regional"].azapi_resource.role_assignments["reader"]'
)
$roleId = '/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
$version = & $TerraformPath version -json
if ($LASTEXITCODE -ne 0) { throw 'Terraform version query failed.' }
$terraformVersion = ($version | ConvertFrom-Json).terraform_version
try {
  # Terraform test safely creates and cleans up only mocked Azure state.
  # The real AzAPI runs are plan-only, with refresh disabled and dummy auth.
  $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'local/rdep.tftest.hcl'))
  [IO.File]::WriteAllText((Join-Path $directory 'd.tftest.hcl'), $template)
  & $TerraformPath "-chdir=$repository" init -backend=false -input=false "-test-directory=$relative" -no-color
  if ($LASTEXITCODE -ne 0) { throw "Dependency test init exited $LASTEXITCODE." }
  $lines = & $TerraformPath "-chdir=$repository" test -json -verbose "-test-directory=$relative"
  if ($LASTEXITCODE -ne 0) { throw "Dependency test exited $LASTEXITCODE." }
  $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
  $summary = $events | Where-Object type -EQ 'test_summary' | Select-Object -Last 1
  if ($summary.test_summary.passed -ne 2 -or $summary.test_summary.status -ne 'pass') {
    throw 'Exactly two dependency test runs must pass; zero discovered tests is not success.'
  }
  $seed = ($events | Where-Object type -EQ 'test_state' | Select-Object -First 1).test_state
  $plan = ($events | Where-Object type -EQ 'test_plan' | Select-Object -Last 1).test_plan

  function Assert-DependencyPlan($Plan, [string] $Label) {
    foreach ($address in $roles) {
      $change = $Plan.resource_changes | Where-Object address -EQ $address
      if (-not $change -or @($change.change.actions | Where-Object { $_ -in @('delete', 'create') }).Count -gt 0 -or
          @($change.change.replace_paths | Where-Object { $null -ne $_ }).Count -gt 0) {
        throw "$Label replaced $address : $($change.change | ConvertTo-Json -Depth 20 -Compress)"
      }
      if ($change.change.before.name -ne $change.change.after.name) { throw "$Label changed the assignment GUID." }
      if ($change.change.before.replace_triggers_external_values.role_definition_id -ne $change.change.after.replace_triggers_external_values.role_definition_id -or
          $change.change.after_unknown.replace_triggers_external_values.role_definition_id) {
        throw "$Label changed or deferred the configured/frozen role trigger."
      }
      if ($change.change.before.body.properties.roleDefinitionId -ne $roleId -or
          -not $change.change.after_unknown.body.properties.roleDefinitionId) {
        throw "$Label must retain the resolved ARM ID in prior state and defer the new body ID, not send Reader."
      }
      $lookup = $address.Replace('azapi_resource.role_assignments["reader"]', 'data.azapi_resource_list.role_definitions[0]')
      $read = $Plan.resource_changes | Where-Object address -EQ $lookup
      if ($read.change.actions -notcontains 'read' -or -not $read.change.after_unknown.output) {
        throw "$Label did not exercise a deferred named-role lookup."
      }
      $guard = $Plan.resource_changes | Where-Object address -EQ $address.Replace('azapi_resource.role_assignments', 'terraform_data.role_assignment_identity')
      if (($guard.change.actions -join ',') -ne 'no-op') { throw "$Label changed the frozen guard." }
    }
    if (@($Plan.resource_changes | Where-Object { $_.change.actions -contains 'delete' }).Count -ne 0) {
      throw "$Label unexpectedly deletes resources."
    }
    Write-Output "PASS: $Label; two deferred Reader lookups, zero replacements/deletes, stable GUIDs and guards."
  }
  Assert-DependencyPlan $plan 'real AzAPI Terraform test plan'

  # Build an explicitly synthetic local state from that mocked seed for CLI
  # plan-only checks, including the older resolved-ID guard/trigger shape.
  # This is NOT an applied Azure baseline or released upgrade.
  $schema = & $TerraformPath "-chdir=$repository" providers schema -json
  if ($LASTEXITCODE -ne 0) { throw 'Provider schema failed.' }
  $schemas = ($schema | ConvertFrom-Json -Depth 100).provider_schemas
  function Get-DynamicType($Value, [bool] $Guard = $false) {
    if ($null -eq $Value -or $Value -is [string]) { return 'string' }
    if ($Value -is [bool]) { return 'bool' }
    if ($Value -is [ValueType]) { return 'number' }
    if ($Value -is [array]) {
      $types = @($Value | ForEach-Object { ,(Get-DynamicType $_) })
      return ,@('tuple', $types)
    }
    $fields = @{}
    foreach ($property in $Value.PSObject.Properties) {
      # The guard's conditional delegation expression returns an untyped null.
      # Its canonical optional(string) fields retain typed string nulls.
      $fields[$property.Name] = if ($Guard -and $property.Name -eq 'delegated_managed_identity_resource_id' -and $null -eq $property.Value) {
        'dynamic'
      } else { Get-DynamicType $property.Value }
    }
    return ,@('object', $fields)
  }
  function Get-Resources($Module) {
    foreach ($resource in $Module.resources) { $resource }
    foreach ($child in $Module.child_modules) { Get-Resources $child }
  }
  function New-SyntheticState([bool] $Legacy) {
    $resources = foreach ($original in (Get-Resources $seed.root_module)) {
      $resource = $original | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
      $values = $resource.values
      if ($resource.type -eq 'azapi_resource') {
        # Normalize mock-only defaults, not drift from any real Azure object.
        $values.ignore_missing_property = $true
        $values.schema_validation_enabled = $true
        if ($resource.name -in @('lock', 'role_assignments')) {
          $values.location = ''
          $values.output = [pscustomobject]@{}
          $values.id = "$($values.parent_id)/providers/Microsoft.Authorization/$(if ($resource.name -eq 'lock') { 'locks' } else { 'roleAssignments' })/$($values.name)"
        }
        if ($Legacy -and $resource.name -eq 'role_assignments') {
          $values.replace_triggers_external_values.role_definition_id = $roleId.ToLowerInvariant()
        }
      }
      if ($Legacy -and $resource.type -eq 'terraform_data' -and $resource.name -eq 'role_assignment_identity') {
        foreach ($field in @('input', 'output')) {
          $values.$field.PSObject.Properties.Remove('role_definition_id_or_name')
          $values.$field | Add-Member -NotePropertyName role_definition_id -NotePropertyValue $roleId.ToLowerInvariant()
        }
      }
      $providerSchema = $schemas.($resource.provider_name)
      $kindSchema = if ($resource.mode -eq 'data') { $providerSchema.data_source_schemas.($resource.type) } else { $providerSchema.resource_schemas.($resource.type) }
      $attributes = @{}
      foreach ($property in $values.PSObject.Properties) {
        $attribute = $kindSchema.block.attributes.($property.Name)
        if ($attribute.write_only) { continue }
        if ($attribute.type -is [string] -and $attribute.type -eq 'dynamic' -and $null -ne $property.Value) {
          $guard = $resource.type -eq 'terraform_data' -and $resource.name -eq 'role_assignment_identity'
          $attributes[$property.Name] = @{ value = $property.Value; type = Get-DynamicType $property.Value $guard }
        } else {
          $attributes[$property.Name] = $property.Value
        }
      }
      $instance = @{ schema_version = $resource.schema_version; attributes = $attributes; sensitive_attributes = @() }
      if ($null -ne $resource.index) { $instance.index_key = $resource.index }
      $raw = @{
        mode = $resource.mode; type = $resource.type; name = $resource.name
        provider = "provider[`"$($resource.provider_name)`"]"; instances = @($instance)
      }
      $tail = "$($resource.type).$($resource.name)"
      if ($resource.mode -eq 'data') { $tail = "data.$tail" }
      $position = $resource.address.LastIndexOf($tail)
      if ($position -gt 0) {
        $raw.module = $resource.address.Substring(0, $position).TrimEnd('.')
      }
      $raw
    }
    return @{ version = 4; terraform_version = $terraformVersion; serial = 1; lineage = [guid]::NewGuid().ToString(); outputs = @{}; resources = @($resources) }
  }
  $fixture = Join-Path $directory 'f'
  [void][IO.Directory]::CreateDirectory($fixture)
  # This generated fixture is also three directories below the repository.
  $provider = [regex]::Match($template, '(?s)provider "azapi" \{.*?\n\}').Value
  foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot 'fixtures/rdep') -Filter '*.tf' -File) {
    [IO.File]::Copy($file.FullName, (Join-Path $fixture $file.Name))
  }
  [IO.File]::WriteAllText((Join-Path $fixture 'offline.tf'), $provider)
  [IO.File]::Copy((Join-Path $repository '.terraform.lock.hcl'), (Join-Path $fixture '.terraform.lock.hcl'))
  & $TerraformPath "-chdir=$fixture" init -backend=false -input=false -no-color
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic plan fixture init failed.' }
  foreach ($legacy in @($false, $true)) {
    $state = New-SyntheticState $legacy
    [IO.File]::WriteAllText((Join-Path $fixture 'terraform.tfstate'), ($state | ConvertTo-Json -Depth 100))
    $lines = & $TerraformPath "-chdir=$fixture" plan -refresh=false -input=false -no-color "-var=dependency=after" "-var=role=rEaDeR" "-var=child_role=rEaDeR" "-out=dep.tfplan"
    if ($LASTEXITCODE -ne 0) { throw "Synthetic legacy=$legacy plan failed: $($lines -join "`n")" }
    $json = & $TerraformPath "-chdir=$fixture" show -json dep.tfplan
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic plan JSON failed.' }
    $cliPlan = $json | ConvertFrom-Json -Depth 100
    Assert-DependencyPlan $cliPlan "synthetic legacy=$legacy CLI plan"
    if (-not $legacy) {
      $moduleConfig = $cliPlan.configuration.root_module.module_calls.m.module
      $rootLock = $moduleConfig.resources | Where-Object address -EQ 'azapi_resource.lock'
      $childLock = $moduleConfig.module_calls.capacity_reservation.module.resources | Where-Object address -EQ 'azapi_resource.lock'
      if (@($rootLock.depends_on).Count -ne 3 -or $rootLock.depends_on -notcontains 'azapi_resource.this' -or
          $rootLock.depends_on -notcontains 'azapi_resource.role_assignments' -or $rootLock.depends_on -notcontains 'module.capacity_reservation' -or
          (@($childLock.depends_on) -join ',') -ne 'azapi_resource.role_assignments') {
        throw 'Root/child lock creation and reverse teardown dependencies changed.'
      }
      Write-Output 'PASS: root/child explicit lock ordering unchanged (configuration graph, not live lock propagation).'
    }
    foreach ($lock in ($cliPlan.resource_changes | Where-Object { $_.type -eq 'azapi_resource' -and $_.name -eq 'lock' })) {
      if (($lock.change.actions -join ',') -ne 'no-op') { throw "Synthetic legacy=$legacy changed an unchanged lock." }
    }
    foreach ($edit in @(
      'principal=44444444-4444-4444-8444-444444444444',
      'role=/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c',
      'child_principal=44444444-4444-4444-8444-444444444444',
      'child_role=/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
    )) {
      $lines = & $TerraformPath "-chdir=$fixture" plan -refresh=false -input=false -json "-var=dependency=after" "-var=$edit"
      if ($LASTEXITCODE -ne 1) { throw "Expected guard rejection for legacy=$legacy $edit." }
      $diagnostics = @($lines | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 } | Where-Object type -EQ 'diagnostic')
      $errors = @($diagnostics | Where-Object { $_.diagnostic.severity -eq 'error' })
      $expectedFile = if ($edit.StartsWith('child_')) { 'modules\capacity_reservation\main.interfaces.tf' } else { '..\..\..\main.interfaces.tf' }
      if ($errors.Count -ne 1 -or $errors[0].diagnostic.detail -notmatch 'Role assignment inputs cannot change under an existing key' -or
          -not $errors[0].diagnostic.range.filename.EndsWith($expectedFile)) {
        throw "Expected only the targeted guard failure: $($errors | ConvertTo-Json -Depth 20)"
      }
      Write-Output "PASS: synthetic legacy=$legacy $edit rejected by its guard."
    }
  }
  # Separately exercise an adopted root GUID before the new local guard/UUID
  # exist and with a null external trigger. This is not a provider state move.
  $state = New-SyntheticState $false
  $state.resources = @($state.resources | Where-Object {
    -not ($_.module -eq 'module.m' -and $_.type -eq 'terraform_data' -and $_.name -eq 'role_assignment_identity') -and
    -not ($_.module -eq 'module.m.module.avm_interfaces' -and $_.type -eq 'random_uuid' -and $_.name -eq 'role_assignment_name')
  })
  $adopted = $state.resources | Where-Object { $_.module -eq 'module.m' -and $_.name -eq 'role_assignments' }
  $adopted.instances[0].attributes.name = '11111111-1111-4111-8111-111111111111'
  $adopted.instances[0].attributes.id = "$($adopted.instances[0].attributes.parent_id)/providers/Microsoft.Authorization/roleAssignments/11111111-1111-4111-8111-111111111111"
  $adopted.instances[0].attributes.replace_triggers_external_values = $null
  [IO.File]::WriteAllText((Join-Path $fixture 'terraform.tfstate'), ($state | ConvertTo-Json -Depth 100))
  $lines = & $TerraformPath "-chdir=$fixture" plan -refresh=false -input=false -no-color "-var=dependency=after" "-out=adopt.tfplan"
  if ($LASTEXITCODE -ne 0) { throw "Adopted GUID plan failed: $($lines -join "`n")" }
  $json = & $TerraformPath "-chdir=$fixture" show -json adopt.tfplan
  if ($LASTEXITCODE -ne 0) { throw 'Adopted plan JSON failed.' }
  $adoptPlan = $json | ConvertFrom-Json -Depth 100
  $change = $adoptPlan.resource_changes | Where-Object address -EQ $roles[0]
  if ($change.change.actions -contains 'delete' -or $change.change.actions -contains 'create' -or
      $change.change.after.name -ne '11111111-1111-4111-8111-111111111111' -or
      $change.change.after.replace_triggers_external_values.role_definition_id -ne 'reader') {
    throw 'Initializing the configured trigger/local guard must not replace an adopted root GUID.'
  }
  Write-Output 'PASS: synthetic adopted root GUID retained while initializing the configured trigger and local guard.'
  Write-Output 'PASS: real AzAPI replacement planning only; mocked/synthetic state, no Azure persistence, lock-delete or migration proof.'
}
finally {
  Remove-Item -LiteralPath $directory -Recurse -Force
}
