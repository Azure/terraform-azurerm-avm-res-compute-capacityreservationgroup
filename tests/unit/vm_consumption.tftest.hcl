mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit"
      output = { properties = { reservationId = "unit" } }
    }
  }
  mock_resource "azapi_resource_action" {
    defaults = { output = { publicKey = "mock-public-key-not-an-Azure-credential" } }
  }
}
mock_provider "random" {}
mock_provider "terraform" {}

variables {
  enable_telemetry = false
}

run "vm_owner_opts_in_and_matches_reserved_shape" {
  command = apply
  module { source = "./examples/vm_consumption" }
  override_resource {
    target = module.capacity_reservation_group.azapi_resource.this
    values = { id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/unit/providers/Microsoft.Compute/capacityReservationGroups/vm-consumption" }
  }
  assert {
    condition = (
      azapi_resource.virtual_machine.body.properties.capacityReservation.capacityReservationGroup.id == output.capacity_reservation_group_id &&
      azapi_resource.virtual_machine.body.properties.hardwareProfile.vmSize == var.vm_size &&
      azapi_resource.virtual_machine.body.zones == [var.zone] &&
      keys(output.capacity_reservation_resource_ids) == ["2:vm:zone-${var.zone}"]
    )
    error_message = "The VM must opt in using the group ARM ID and the same size/zone as the reservation definition."
  }
  assert {
    condition = (
      azapi_resource.virtual_machine.body.properties.osProfile.linuxConfiguration.disablePasswordAuthentication &&
      azapi_resource.virtual_machine.body.properties.osProfile.linuxConfiguration.ssh.publicKeys[0].keyData == azapi_resource_action.ssh_key_pair[0].output.publicKey &&
      azapi_resource_action.ssh_key_pair[0].response_export_values == ["publicKey"] &&
      !can(azapi_resource.virtual_machine.body.properties.osProfile.adminPassword) &&
      !can(azapi_resource.network_interface.body.properties.ipConfigurations[0].properties.publicIPAddress) &&
      !azapi_resource.subnet.body.properties.defaultOutboundAccess &&
      azapi_resource.network_security_group.body.properties.securityRules[0].properties.access == "Deny" &&
      azapi_resource.virtual_machine.body.properties.storageProfile.osDisk.managedDisk.storageAccountType == "Premium_LRS" &&
      azapi_resource.virtual_machine.body.properties.storageProfile.osDisk.deleteOption == "Delete"
    )
    error_message = "The example must use generated public-key authentication, no public IP/password/default outbound access, deny inbound, and clean up its disk."
  }
}

run "vm_owner_explicitly_disables_association" {
  command = apply
  module { source = "./examples/vm_consumption" }
  variables {
    capacity_reservation_enabled = false
    ssh_public_key               = "mock-public-key-provided-by-unit-test"
  }
  assert {
    condition = (
      azapi_resource.virtual_machine.body.properties.capacityReservation.capacityReservationGroup.id == null &&
      length(azapi_resource.ssh_public_key) == 0 &&
      length(azapi_resource_action.ssh_key_pair) == 0 &&
      azapi_resource.virtual_machine.body.properties.osProfile.linuxConfiguration.ssh.publicKeys[0].keyData == var.ssh_public_key
    )
    error_message = "Opt-out must send an explicit null association and a provided public key must avoid key generation. This mock is not proof of live disassociation."
  }
}
