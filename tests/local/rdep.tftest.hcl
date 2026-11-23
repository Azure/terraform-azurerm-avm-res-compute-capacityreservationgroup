# Seed only with mocked Azure. Later runs use the real AzAPI planner with
# refresh disabled and pending module depends_on: no Azure read or write.
provider "azapi" {
  subscription_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  tenant_id       = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  client_id       = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  client_secret   = "offline-placeholder-not-a-credential"
  use_cli         = false
}

provider "random" {}
provider "terraform" {}

mock_provider "azapi" {
  alias = "seed"
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        value = [{
          id         = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
          properties = { roleName = "Reader" }
        }]
      }
    }
  }
  mock_resource "azapi_resource" {
    defaults = { output = { properties = { reservationId = "offline-reservation" } } }
  }
}

override_resource {
  target = module.m.azapi_resource.this
  values = {
    id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit"
  }
}

override_resource {
  target = module.m.module.capacity_reservation["1:c:regional"].azapi_resource.this
  values = {
    id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/unit/capacityReservations/child-regional"
    output = { properties = { reservationId = "offline-reservation" } }
  }
}

run "seed" {
  command = apply
  module {
    source = "./tests/fixtures/rdep"
  }
  providers = {
    azapi     = azapi.seed
    random    = random
    terraform = terraform
  }
}
run "dep" {
  command = plan
  module {
    source = "./tests/fixtures/rdep"
  }
  plan_options {
    refresh = false
  }
  variables {
    dependency = "after"
    role       = "rEaDeR"
    child_role = "rEaDeR"
  }
  providers = {
    azapi     = azapi
    random    = random
    terraform = terraform
  }
}
