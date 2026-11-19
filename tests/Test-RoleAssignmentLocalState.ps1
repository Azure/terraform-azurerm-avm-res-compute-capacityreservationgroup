param(
  [Parameter(Mandatory)]
  [string] $TerraformPath
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
# Generated test inputs only; all module sources remain in the current worktree.
# Short names avoid Windows Git module-cache path limits.
$relative = ".terraform/r$([guid]::NewGuid().ToString('N').Substring(0, 6))"
$directory = Join-Path $repository $relative
[void][IO.Directory]::CreateDirectory($directory)
try {
  $files = @{
    'i' = 'interfaces'
    'c' = 'child_interfaces'
    'f' = 'rbac_fanout'
  }
  $labels = @{}
  $runIndex = 0
  foreach ($entry in $files.GetEnumerator()) {
    $source = Join-Path $PSScriptRoot "unit/$($entry.Value).tftest.hcl"
    $test = [IO.File]::ReadAllText($source)
    foreach ($provider in @('random', 'terraform')) {
      $mock = 'mock_provider "' + $provider + '" {}'
      if (-not $test.Contains($mock)) { throw "Expected empty $provider mock in $source." }
      $test = $test.Replace($mock, ('provider "' + $provider + '" {}'))
    }
    if (-not $test.Contains('mock_provider "azapi"') -or $test -match '(?m)^provider "azapi"') {
      throw "Azure must remain mocked in $source."
    }
    foreach ($match in [regex]::Matches($test, '(?m)^run "([^"]+)"')) {
      $name = $match.Groups[1].Value
      $label = "r$runIndex"
      $runIndex++
      $labels[$name] = $label
      $test = $test.Replace(('run "' + $name + '"'), ('run "' + $label + '"')).Replace("run.$name.", "run.$label.")
    }
    [IO.File]::WriteAllText((Join-Path $directory "$($entry.Key).tftest.hcl"), $test)
  }
  & $TerraformPath "-chdir=$repository" init -backend=false -input=false "-test-directory=$relative" -no-color
  if ($LASTEXITCODE -ne 0) { throw "Local-state test init exited $LASTEXITCODE." }
  $lines = & $TerraformPath "-chdir=$repository" test -json -verbose "-test-directory=$relative"
  if ($LASTEXITCODE -ne 0) { throw "Local-state tests exited $LASTEXITCODE." }
  $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
  $summary = $events | Where-Object type -EQ 'test_summary' | Select-Object -Last 1
  if ($summary.test_summary.status -ne 'pass') { throw 'Local-state summary was not pass.' }

  function Get-State([string] $Run) {
    $record = $events | Where-Object { $_.type -eq 'test_state' -and $_.'@testrun' -eq $labels[$Run] } | Select-Object -Last 1
    if (-not $record) { throw "Missing state for $Run." }
    return $record.test_state.root_module
  }
  $assertions = 0
  foreach ($pair in @(
    @{ before = 'read_only_custom_lock_and_explicit_principal_type'; after = 'recreate_root_grant' },
    @{ before = 'standalone_child_scoped_extensions'; after = 'recreate' }
  )) {
    $before = Get-State $pair.before
    $after = Get-State $pair.after
    $oldRole = $before.resources | Where-Object address -EQ 'azapi_resource.role_assignments["reader"]'
    $newRole = $after.resources | Where-Object address -EQ 'azapi_resource.role_assignments["reader"]'
    $guard = $after.resources | Where-Object address -EQ 'terraform_data.role_assignment_identity["reader"]'
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($oldRole.values.name, [ref]$parsed) -or
        -not [guid]::TryParse($newRole.values.name, [ref]$parsed) -or
        $oldRole.values.name -eq $newRole.values.name) { throw 'Staged recreation must use a fresh real UUID.' }
    $assertions++
    if ($guard.values.input.principal_id -ne $guard.values.output.principal_id -or
        $guard.values.input.principal_id -ne $newRole.values.body.properties.principalId) {
      throw 'Real builtin state must retain the recreated grant inputs and output.'
    }
    $assertions++
  }
  $fanout = Get-State 'generated_multizone_guids'
  $names = @($fanout.child_modules | Where-Object { $_.address.StartsWith('module.capacity_reservation[') } | ForEach-Object {
    $_.resources | Where-Object type -EQ 'azapi_resource' | Where-Object name -EQ 'role_assignments' | ForEach-Object { $_.values.name }
  })
  if ($names.Count -ne 2 -or @($names | Sort-Object -Unique).Count -ne 2) { throw 'Fan-out must generate two distinct real UUIDs.' }
  foreach ($name in $names) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($name, [ref]$parsed)) { throw 'Fan-out UUID is not a GUID.' }
  }
  $assertions++
  Write-Output "PASS: $assertions real-local-provider assertions; $($summary.test_summary.passed) Terraform runs. Azure remained mocked; no Azure persistence or migration proof."
}
finally {
  Remove-Item -LiteralPath $directory -Recurse -Force
}
