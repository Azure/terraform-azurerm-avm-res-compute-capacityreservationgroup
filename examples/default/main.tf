## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.13.0"

  location         = var.location
  enable_telemetry = var.enable_telemetry
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}

## End of section to provide a random Azure region for the resource group

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/avm-utl-naming/azure"
  version = "0.2.0"
}

# This is required for resource modules
data "azapi_client_config" "this" {}

resource "azapi_resource" "resource_group" {
  location               = module.regions.regions[random_integer.region_index.result].name
  name                   = module.naming.resource_group.name_unique
  parent_id              = data.azapi_client_config.this.subscription_resource_id
  type                   = "Microsoft.Resources/resourceGroups@2024-03-01"
  response_export_values = []
}

moved {
  from = azurerm_resource_group.this
  to   = azapi_resource.resource_group
}

# This is the module call for capacity reservation group
module "capacity_reservation_group" {
  source = "../../"

  capacity_reservation_group_name = local.capacity_reservation_group_name
  location                        = azapi_resource.resource_group.location
  parent_id                       = azapi_resource.resource_group.id
  enable_telemetry                = var.enable_telemetry
  subscription_id                 = var.subscription_id
  tags                            = local.tags
  zones                           = [local.zone]
}

# This is the module call for capacity reservation
module "capacity_reservation" {
  source = "../../modules/capacity_reservation"

  capacity_reservation_name = local.capacity_reservation_name
  location                  = azapi_resource.resource_group.location
  parent_id                 = module.capacity_reservation_group.capacity_reservation_group_id
  sku                       = local.sku
  zone                      = local.zone
  enable_telemetry          = var.enable_telemetry
  tags                      = local.tags
}
