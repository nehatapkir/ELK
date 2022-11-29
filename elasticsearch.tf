# Set up elasticsearch nodes
# Terraform code based on documentation https://www.terraform.io/docs/providers/azurerm/r/virtual_machine.html
resource "azurerm_network_security_group" "nsg_elastic" {
  name                = "elk-elastic"
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

resource "azurerm_network_interface" "elastic_nic" {
  name                = "weu-elk-elastic1"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  ip_configuration {
    name                          = "weu-elk-elastic1"
    subnet_id                     = "${azurerm_subnet.network.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id         = "${azurerm_public_ip.elastic.id}"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_elastic_asscoitaion" {
  network_interface_id      = azurerm_network_interface.elastic_nic.id
  network_security_group_id = azurerm_network_security_group.nsg_elastic.id
}

resource "tls_private_key" "pk_elastic" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "pk_elastic"{
 filename = "pk_elastic.pem"
 content = tls_private_key.pk_elastic.private_key_pem
}

# For better availability, create availability set
resource "azurerm_availability_set" "avset" {
  name                         = "weu-elk-elastic"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

# Create 3 VMs for elasticsearch nodes
resource "azurerm_virtual_machine" "elastic" {
  name                  = "weu-elk-elastic1"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.elastic_nic.id}"]
  availability_set_id   = "${azurerm_availability_set.avset.id}"
  vm_size               = "Standard_A2_v2"
  delete_os_disk_on_termination = true
   depends_on            = [ "azurerm_virtual_machine.jumpbox",
  tls_private_key.pk_elastic ]

# Upload Chef recipes
  provisioner "file" {
    source      = "chef"
    destination = "/tmp/"

    connection {
      type     = "ssh"
      user     = "${var.ssh_user}"
      host = "weu-elk-elastic1"
      private_key = tls_private_key.pk_elastic.private_key_pem
      agent    = false
    # Using Jumpbox for accessing VMs as I don't have VPN solution for these networks in test subscription
      bastion_user     = "${var.ssh_user}"
      bastion_host     = "${data.azurerm_public_ip.jumpbox.ip_address}"
      bastion_private_key = tls_private_key.pk_jumpbox.private_key_pem
      timeout = "6m"
    }
  }

    provisioner "file" {
    source      = "chef/cookbooks/elk-stack/templates/default"
    destination = "/tmp/"

    connection {
      type     = "ssh"
      user     = "${var.ssh_user}"
      host = "weu-elk-elastic1"
      private_key = tls_private_key.pk_elastic.private_key_pem
      agent    = false
    # Using Jumpbox for accessing VMs as I don't have VPN solution for these networks in test subscription
      bastion_user     = "${var.ssh_user}"
      bastion_host     = "${data.azurerm_public_ip.jumpbox.ip_address}"
      bastion_private_key = tls_private_key.pk_jumpbox.private_key_pem
      timeout = "6m"
    }
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "weu-elk-elastic1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

   os_profile {
     computer_name  = "weu-elk-elastic1"
     admin_username = "${var.ssh_user}"
     admin_password = var.admin_password
   }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.ssh_user}/.ssh/authorized_keys"
      key_data = tls_private_key.pk_elastic.public_key_openssh
    }
  }

  tags = {
    environment = "development"
  }
}

# Using azure custom script extension, same can be achieved using terraform's
# remote-exec provisioner. Bootstrap node(s) with Chef.
resource "azurerm_virtual_machine_extension" "elastic" {
  name                 = "weu-elk-elastic1"
  virtual_machine_id    = "${azurerm_virtual_machine.elastic.id}"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"  
  depends_on           = ["azurerm_virtual_machine.elastic"]

  settings = <<SETTINGS
    {
        "commandToExecute": "curl -L https://omnitruck.chef.io/install.sh | sudo bash; chef-solo --chef-license accept-silent -c /tmp/chef/solo.rb -o elk-stack::repo-setup,elk-stack::elastic"
    }
SETTINGS
}

resource "azurerm_public_ip" "elastic" {
  name                         = "elk-stack-elastic-pip"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method   = "Static"
}

data "azurerm_public_ip" "elastic" {
  name                = "${azurerm_public_ip.elastic.name}"
  resource_group_name = "${azurerm_virtual_machine.elastic.resource_group_name}"
}

output "elastic_public_ip_address" {
  value = "${data.azurerm_public_ip.elastic.ip_address}"
}
