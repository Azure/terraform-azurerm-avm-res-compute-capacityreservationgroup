## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "~> 0.1"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}
## End of section to provide a random Azure region for the resource group

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.3"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = module.regions.regions[random_integer.region_index.result].name
  name     = module.naming.resource_group.name_unique
}

# This is the module call for capacity reservation group
module "capacity_reservation_group" {
  source = "../../"

  capacity_reservation_group_name = local.capacity_reservation_group_name
  location                        = azurerm_resource_group.this.location
  resource_group_id               = azurerm_resource_group.this.id
  subscription_id                 = local.subscription_id
  tags                            = local.tags
}



# This is the module call for capacity reservation
module "capacity_reservation" {
  source = "../../modules/capacity_reservation"

  capacity_reservation_group_id = module.capacity_reservation_group.capacity_reservation_group_id
  capacity_reservation_name     = local.capacity_reservation_name
  location                      = azurerm_resource_group.this.location
  sku                           = local.sku
  tags                          = local.tags
  zones                         = local.zones
}
