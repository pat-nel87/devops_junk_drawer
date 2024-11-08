output "vm_id" {
  value = azurerm_virtual_machine.rhel7_vm.id
}

output "vm_private_ip" {
  value = azurerm_network_interface.vm_nic.private_ip_address
}
