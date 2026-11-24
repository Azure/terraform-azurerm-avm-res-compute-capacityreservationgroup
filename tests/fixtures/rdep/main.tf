resource "terraform_data" "dep" {
  input = var.dependency
}

module "m" {
  source = "../../.."

  capacity_reservation_group_name = "unit"
  location                        = "westeurope"
  parent_id                       = var.parent_id
  capacity_reservations = {
    c = {
      name  = "child"
      sku   = { name = "Standard_D2s_v5", capacity = 1 }
      zones = []
      lock  = { kind = "CanNotDelete" }
      role_assignments = {
        reader = {
          role_definition_id_or_name = var.child_role
          principal_id               = var.child_principal
        }
      }
    }
  }
  enable_telemetry = false
  lock             = { kind = "CanNotDelete" }
  role_assignments = {
    reader = {
      role_definition_id_or_name = var.role
      principal_id               = var.principal
    }
  }
  zones = []

  depends_on = [terraform_data.dep]
}
