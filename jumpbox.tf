# Set up JB for accessing ELK stack VM
# Terraform code based on https://www.terraform.io/docs/providers/azurerm/r/virtual_machine.html

# Create NSG for limiting access to JB

resource "azurerm_network_security_group" "nsg_jumpbox" {
  name                = "elk-jumpbox"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  security_rule {
    name                       = "allowtcp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "tls_private_key" "pk_jumpbox" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "azurerm_network_interface" "jumpbox_nic" {
  name                = "weu-elk-jumpbox1"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  ip_configuration {
    name                          = "weu-elk-jumpbox1"
    subnet_id                     = "${azurerm_subnet.network.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.jumpbox_public_ip.id}"

  }
}

resource "azurerm_network_interface_security_group_association" "nsg_jumpbox_asscoitaion" {
  network_interface_id      = azurerm_network_interface.jumpbox_nic.id
  network_security_group_id = azurerm_network_security_group.nsg_jumpbox.id
}

resource "azurerm_public_ip" "jumpbox_public_ip" {
  name                         = "elk-stack-jb-pip"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method   = "Static"
}

resource "azurerm_virtual_machine" "jumpbox" {
  name                  = "weu-elk-jumpbox1"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.jumpbox_nic.id}"]
  vm_size               = "Standard_D4s_v3"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "weu-elk-jumpbox1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

   os_profile {
     computer_name  = "weu-elk-jumpbox1"
     admin_username = "${var.ssh_user}"
     admin_password = var.admin_password
   }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.ssh_user}/.ssh/authorized_keys"
      key_data = tls_private_key.pk_jumpbox.public_key_openssh
    } 
  }

  tags = {
    environment = "development"
  }

}
  data "azurerm_public_ip" "jumpbox" {
  name                = "${azurerm_public_ip.jumpbox_public_ip.name}"
  resource_group_name = "${azurerm_virtual_machine.jumpbox.resource_group_name}"
}

output "jumpbox_public_ip_address" {
  value = "${data.azurerm_public_ip.jumpbox.ip_address}"
}