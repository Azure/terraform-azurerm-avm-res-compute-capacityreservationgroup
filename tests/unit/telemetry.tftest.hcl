mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id          = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      subscription_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      tenant_id                = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
}

mock_provider "azurerm" {}

mock_provider "terraform" {
  mock_resource "terraform_data" {
    override_during = plan
    defaults = {
      id = "11111111-1111-4111-8111-111111111111"
    }
  }
}

variables {
  location = "westeurope"
}

run "root_telemetry_enabled_by_default" {
  command = plan

  providers = {
    azapi     = azapi
    azurerm   = azurerm
    terraform = terraform
  }

  variables {
    capacity_reservation_group_name = "telemetry-unit"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
  }

  assert {
    condition     = length(azapi_resource.telemetry) == 1 && length(terraform_data.telemetry) == 1 && length(data.azapi_client_config.telemetry) == 1
    error_message = "Root telemetry must be enabled by default with one deployment, provider-free instance and client lookup."
  }

  assert {
    condition = (
      azapi_resource.telemetry[0].type == "Microsoft.Resources/deployments@2025-04-01" &&
      azapi_resource.telemetry[0].parent_id == "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" &&
      azapi_resource.telemetry[0].location == var.location &&
      azapi_resource.telemetry[0].body.properties.mode == "Incremental" &&
      length(azapi_resource.telemetry[0].body.properties.template.resources) == 0 &&
      azapi_resource.telemetry[0].body.properties.template.outputs.apply_id.value == plantimestamp() &&
      length(azapi_resource.telemetry[0].response_export_values) == 0 &&
      startswith(azapi_resource.telemetry[0].name, "${local.avm_metadata.telemetryIdPrefix}.") &&
      endswith(azapi_resource.telemetry[0].name, ".${substr(sha1("11111111-1111-4111-8111-111111111111"), 0, 4)}") &&
      length(azapi_resource.telemetry[0].name) <= 64
    )
    error_message = "Root telemetry must be an empty regional subscription deployment with metadata-backed identity, a stable instance suffix and no exported response values."
  }
}

run "root_telemetry_disabled" {
  command = plan

  providers = {
    azapi     = azapi
    azurerm   = azurerm
    terraform = terraform
  }

  variables {
    capacity_reservation_group_name = "telemetry-unit"
    resource_group_id               = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
    enable_telemetry                = false
  }

  assert {
    condition     = length(azapi_resource.telemetry) == 0 && length(terraform_data.telemetry) == 0 && length(data.azapi_client_config.telemetry) == 0
    error_message = "Disabling root telemetry must omit the deployment, provider-free instance and client lookup."
  }
}

run "child_telemetry_enabled_by_default" {
  command = plan

  module {
    source = "./modules/capacity_reservation"
  }

  providers = {
    azapi     = azapi
    terraform = terraform
  }

  variables {
    capacity_reservation_group_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
    capacity_reservation_name     = "telemetry-child"
    sku = {
      capacity = 1
      name     = "Standard_B2ms"
    }
  }

  assert {
    condition     = length(azapi_resource.telemetry) == 1 && length(terraform_data.telemetry) == 1 && length(data.azapi_client_config.telemetry) == 1
    error_message = "Child telemetry must be enabled by default with one deployment, provider-free instance and client lookup."
  }

  assert {
    condition = (
      azapi_resource.telemetry[0].type == "Microsoft.Resources/deployments@2025-04-01" &&
      azapi_resource.telemetry[0].parent_id == "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" &&
      azapi_resource.telemetry[0].location == var.location &&
      azapi_resource.telemetry[0].body.properties.mode == "Incremental" &&
      length(azapi_resource.telemetry[0].body.properties.template.resources) == 0 &&
      azapi_resource.telemetry[0].body.properties.template.outputs.apply_id.value == plantimestamp() &&
      length(azapi_resource.telemetry[0].response_export_values) == 0 &&
      startswith(azapi_resource.telemetry[0].name, "${local.avm_metadata.telemetryIdPrefix}.") &&
      endswith(azapi_resource.telemetry[0].name, ".${substr(sha1("11111111-1111-4111-8111-111111111111"), 0, 4)}") &&
      length(azapi_resource.telemetry[0].name) <= 64
    )
    error_message = "Child telemetry must use its own metadata, supplied region, active subscription, stable instance suffix and an empty incremental template without exported response values."
  }
}

run "child_telemetry_disabled" {
  command = plan

  module {
    source = "./modules/capacity_reservation"
  }

  providers = {
    azapi     = azapi
    terraform = terraform
  }

  variables {
    capacity_reservation_group_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
    capacity_reservation_name     = "telemetry-child"
    enable_telemetry              = false
    sku = {
      capacity = 1
      name     = "Standard_B2ms"
    }
  }

  assert {
    condition     = length(azapi_resource.telemetry) == 0 && length(terraform_data.telemetry) == 0 && length(data.azapi_client_config.telemetry) == 0
    error_message = "Disabling child telemetry must omit the deployment, provider-free instance and client lookup."
  }
}
