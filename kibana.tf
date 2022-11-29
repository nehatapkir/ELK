# Set up Kibana nodes
# Terraform code based on documentation https://www.terraform.io/docs/providers/azurerm/r/virtual_machine.html

# Create Public ip for Kibana dashboard

resource "azurerm_public_ip" "kibana" {
  name                = "elk-stack-kibana-pip"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method = "Dynamic"
}

resource "azurerm_network_interface_security_group_association" "nsg_kibana_asscoitaion" {
  network_interface_id      = azurerm_network_interface.kibana_nic.id
  network_security_group_id = azurerm_network_security_group.kibana.id
}

resource "tls_private_key" "pk_kibana" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "pk_kibana"{
 filename = "pk_kibana.pem"
 content = tls_private_key.pk_kibana.private_key_pem
}

# Network security group for limiting access to Kibana public dashboard
resource "azurerm_network_security_group" "kibana" {
  name                = "elk-kibana"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  security_rule {
    name                       = "allowtcp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5601"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface, attach public ip that we have created
resource "azurerm_network_interface" "kibana_nic" {
  name                = "weu-elk-kibana1"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"  

  ip_configuration {
    name                          = "weu-elk-kibana1"
    subnet_id                     = "${azurerm_subnet.network.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.kibana.id}"

  }
}

# Create VM
resource "azurerm_virtual_machine" "kibana" {
  name                  = "weu-elk-kibana1"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.kibana_nic.id}"]
  vm_size               = "Standard_A2_v2"
  delete_os_disk_on_termination = true
  depends_on            = ["azurerm_virtual_machine.jumpbox", "azurerm_virtual_machine.elastic" ,
  tls_private_key.pk_kibana ]
# Upload Chef cookbook/recipes
  provisioner "file" {
    source      = "chef"
    destination = "/tmp/"

    connection {
      type     = "ssh"
      user     = "${var.ssh_user}"
      host = "weu-elk-kibana1"
      private_key = tls_private_key.pk_kibana.private_key_pem
      agent    = false
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
    name              = "weu-elk-kibana1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

   os_profile {
     computer_name  = "weu-elk-kibana1"
     admin_username = "${var.ssh_user}"
     admin_password = var.admin_password
   }

  os_profile_linux_config {
    disable_password_authentication = false
    ssh_keys {
      path     = "/home/${var.ssh_user}/.ssh/authorized_keys"
      key_data = tls_private_key.pk_kibana.public_key_openssh
    }
  }

  tags = {
    environment = "development"
  }
}

# Install chef-solo, start chef bootstrap
resource "azurerm_virtual_machine_extension" "kibana" {
  name                 = "weu-elk-kibana1"
  virtual_machine_id    = "${azurerm_virtual_machine.kibana.id}"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  depends_on           = ["azurerm_virtual_machine.kibana"]


  settings = <<SETTINGS
    {
        "commandToExecute": "curl -L https://omnitruck.chef.io/install.sh | sudo bash; chef-solo --chef-license accept-silent -c /tmp/chef/solo.rb -o elk-stack::repo-setup,elk-stack::kibana"
    }
SETTINGS
}

data "azurerm_public_ip" "kibana" {
  name                = "${azurerm_public_ip.kibana.name}"
  resource_group_name = "${azurerm_virtual_machine.kibana.resource_group_name}"
}

output "kibana_public_ip_address" {
  value = "${data.azurerm_public_ip.kibana.ip_address}"
}
