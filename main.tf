# Terraform runtime requirements

terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  # Leave the features block empty to accept all defaults
  features {}
}

provider "cloudinit" {
  # Configuration options

}


data "cloudinit_config" "init"{

  gzip =false
  base64_encode=true

  part {
    filename     = "init.sh"
    content_type = "text/x-shellscript"

    content = file("${path.module}/init.sh")
  }
}


# Variables
variable "labelPrefix" {
  default = "dhuk0001"
}

variable "region" {
  default = "East US"
}

variable "admin_username" {
  default = "adminuser"
}

# Resource Group
resource "azurerm_resource_group" "A05" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

# Public IP Address
resource "azurerm_public_ip" "A05" {
  name                = "${var.labelPrefix}-publicip"
  resource_group_name = azurerm_resource_group.A05.name
  location            = azurerm_resource_group.A05.location
  allocation_method  = "Dynamic"
}

# Virtual Network
resource "azurerm_virtual_network" "A05" {
  name                = "${var.labelPrefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.A05.location
  resource_group_name = azurerm_resource_group.A05.name
}

# Subnet
resource "azurerm_subnet" "A05" {
  name                 = "${var.labelPrefix}-subnet"
  resource_group_name  = azurerm_resource_group.A05.name
  virtual_network_name = azurerm_virtual_network.A05.name
  address_prefixes    = ["10.0.1.0/24"]
}

# Security Group
resource "azurerm_network_security_group" "A05" {
  name                = "${var.labelPrefix}-nsg"
  location            = azurerm_resource_group.A05.location
  resource_group_name = azurerm_resource_group.A05.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Virtual Network Interface Card (NIC)
resource "azurerm_network_interface" "A05" {
  name                = "${var.labelPrefix}-nic"
  location            = azurerm_resource_group.A05.location
  resource_group_name = azurerm_resource_group.A05.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.A05.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Apply the security group to the NIC
resource "azurerm_network_interface_security_group_association" "A05" {
  network_interface_id      = azurerm_network_interface.A05.id
  network_security_group_id = azurerm_network_security_group.A05.id
}


# Virtual Machine
resource "azurerm_linux_virtual_machine" "A05" {
  name                = "${var.labelPrefix}-vm"
  resource_group_name = azurerm_resource_group.A05.name
  location            = azurerm_resource_group.A05.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.A05.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") 
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data=data.cloudinit_config.init.rendered
}


# Output Values
output "resource_group_name" {
  value = azurerm_resource_group.A05.name
}

output "public_ip_address" {
  value = azurerm_public_ip.A05.ip_address
}