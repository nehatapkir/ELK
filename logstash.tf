# Set up Logstash node
# Terraform code based on documentation https://www.terraform.io/docs/providers/azurerm/r/virtual_machine.html
resource "azurerm_network_security_group" "nsg_logstash" {
  name                = "elk-logstash"
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

resource "azurerm_network_interface" "logstash_nic" {
  name                = "weu-elk-logstash1"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  ip_configuration {
    name                          = "weu-elk-logstash1"
    subnet_id                     = "${azurerm_subnet.network.id}"
    private_ip_address_allocation = "Dynamic"
     public_ip_address_id         = "${azurerm_public_ip.logstash.id}"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_logstash_asscoitaion" {
  network_interface_id      = azurerm_network_interface.logstash_nic.id
  network_security_group_id = azurerm_network_security_group.nsg_logstash.id
}

resource "tls_private_key" "pk_logstash" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "pk_logstash"{
 filename = "pk_logstash.pem"
 content = tls_private_key.pk_logstash.private_key_pem
}


resource "azurerm_virtual_machine" "logstash" {
  name                  = "weu-elk-logstash1"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.logstash_nic.id}"]
  vm_size               = "Standard_A2_v2"
  delete_os_disk_on_termination = true
  depends_on            = [ "azurerm_virtual_machine.jumpbox",
  tls_private_key.pk_logstash ]

    provisioner "file" {
      source      = "chef"
      destination = "/tmp/"

      connection {
        type     = "ssh"
        user     = "${var.ssh_user}"
        host = "weu-elk-logstash1"
        private_key = tls_private_key.pk_logstash.private_key_pem
        agent    = false
      #  key_file = "${file("~/.ssh/id_rsa")}"
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
    name              = "weu-elk-logstash1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

os_profile {
     computer_name  = "weu-elk-logstash1"
     admin_username = "${var.ssh_user}"
     admin_password = var.admin_password
   }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.ssh_user}/.ssh/authorized_keys"
      key_data = tls_private_key.pk_logstash.public_key_openssh
    }
  }

  tags = {
    environment = "development"
  }
}

resource "azurerm_virtual_machine_extension" "logstash" {
  name                 = "weu-elk-logstash1" 
  publisher            = "Microsoft.Azure.Extensions"
  virtual_machine_id    = "${azurerm_virtual_machine.logstash.id}"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  depends_on           = ["azurerm_virtual_machine.logstash"]

  settings = <<SETTINGS
    {
        "commandToExecute": "curl -L https://omnitruck.chef.io/install.sh | sudo bash; chef-solo --chef-license accept-silent -c /tmp/chef/solo.rb -o elk-stack::repo-setup,elk-stack::logstash"
    }
SETTINGS
}

resource "azurerm_public_ip" "logstash" {
  name                         = "elk-stack-log-pip"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method   = "Static"
}

data "azurerm_public_ip" "logstash" {
  name                = "${azurerm_public_ip.logstash.name}"
  resource_group_name = "${azurerm_virtual_machine.logstash.resource_group_name}"
}

output "logstash_public_ip_address" {
  value = "${data.azurerm_public_ip.logstash.ip_address}"
}

output "tls_private_key" {
  value     = tls_private_key.pk_logstash.private_key_pem
  sensitive = true
}