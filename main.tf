# Configuration for the provider
provider "azurerm" {
  skip_provider_registration = "true"
  features {}
  subscription_id = "497d9fe5-65d5-4fc3-9b62-b12b3fe26d24"
}

# Configuration for creating the resource group in azure portal
resource "azurerm_resource_group" "kafka-cluster-rg" {
  name     = "kafka-cluster-rg"
  location = "Central India"
}

# Configuration for creating the virtual network under the resource group
resource "azurerm_virtual_network" "kafka-zookeeper-virtual-network" {
  name                = "kafka-zookeeper-virtual-network"
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name
  location            = azurerm_resource_group.kafka-cluster-rg.location
  address_space       = ["10.0.0.0/16"]
}

# Configuration for creating the subnet for the virtual network under the resource group
resource "azurerm_subnet" "kafka-zookeeper-subnet" {
  name                 = "kafka-zookeeper-subnet"
  resource_group_name  = azurerm_resource_group.kafka-cluster-rg.name
  virtual_network_name = azurerm_virtual_network.kafka-zookeeper-virtual-network.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Configuration for creating the security group along with the security rules under the resource group
resource "azurerm_network_security_group" "kafka-zookeeper-sg" {
  name                = "ssh_nsg"
  location            = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name

  security_rule {
    name                       = "allow_ssh_sg"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_zookeeper_sg"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2181"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_kafka9000_sg"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  /* security_rule {
     name                       = "allow_kafka9091_sg"
     priority                   = 130
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_range     = "9091"
     source_address_prefix      = "*"
     destination_address_prefix = "*"
   }

   security_rule {
     name                       = "allow_kafka9092_sg"
     priority                   = 140
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_range     = "9092"
     source_address_prefix      = "*"
     destination_address_prefix = "*"
   }*/
}

# Configuration for creating the public ips for zookeeper VM
resource "azurerm_public_ip" "kafka_public_ip" {
  count               = 1
  name                = "kafkaPublicIP${count.index}"
  location            = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "kafka-nic" {
  count               = 1
  name                = "kafka-nic${count.index}"
  location            = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name

  ip_configuration {
    name                          = "kafka-ip-config"
    subnet_id                     = azurerm_subnet.kafka-zookeeper-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.kafka_public_ip.*.id, count.index)}"
  }
}

resource "azurerm_network_interface_security_group_association" "kafka_broker_association" {
  count                     = length(azurerm_network_interface.kafka-nic.*.id)
  network_interface_id      = element(azurerm_network_interface.kafka-nic.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.kafka-zookeeper-sg.id
}

resource "azurerm_virtual_machine" "kafka" {
  count                 = 1
  name                  = "kafka${count.index}"
  location              = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name   = azurerm_resource_group.kafka-cluster-rg.name
  vm_size               = "Standard_B1s"
  network_interface_ids = [element(azurerm_network_interface.kafka-nic.*.id, count.index)]
  delete_data_disks_on_termination = true


  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "kafkadisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "kafka${count.index}"
    admin_username = "kafkauser"
    admin_password = "Password123!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  provisioner "remote-exec" {

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y openjdk-11-jdk",
      "wget https://downloads.apache.org/kafka/3.0.0/kafka_2.13-3.0.0.tgz",
      "chmod 777 kafka_2.13-3.8.0.tgz",
      "tar -xzf kafka_2.13-3.0.0.tgz"
    ]
  }

  connection {
    type     = "ssh"
    user     = "kafkauser"
    password = "Password123!"
    port = "22"
    timeout = "5m"
    host = element(azurerm_public_ip.kafka_public_ip.*.ip_address, count.index)
  }
}

output "kafka_ips" {
  value = [for i in azurerm_network_interface.kafka-nic : i.private_ip_address]
}

# Configuration for creating the public ips for zookeeper VM
/*resource "azurerm_public_ip" "zookeeper1_public_ip" {
  name                = "zookeeper1PublicIP"
  location            = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name
  allocation_method   = "Static"
}

data "azurerm_public_ip" "zookeeper1_public_ips" {
  name  = azurerm_public_ip.zookeeper1_public_ip.name
  resource_group_name = azurerm_public_ip.zookeeper1_public_ip.resource_group_name
}

# Configuration for creating the network interface for zookeeper
resource "azurerm_network_interface" "zookeeper-nic" {
  name                = "zookeeper-nic"
  location            = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name = azurerm_resource_group.kafka-cluster-rg.name

  ip_configuration {
    name                          = "zookeeper-ip-config"
    subnet_id                     = azurerm_subnet.kafka-zookeeper-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.zookeeper1_public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "zookeeper_association" {
  network_interface_id      = azurerm_network_interface.zookeeper-nic.id
  network_security_group_id = azurerm_network_security_group.kafka-zookeeper-sg.id
}

# Configuration for creating the virtual machines for zookeeper under the network and subnet in the resource group
resource "azurerm_virtual_machine" "zookeeper1" {
  name                  = "zookeeper1"
  location              = azurerm_resource_group.kafka-cluster-rg.location
  resource_group_name   = azurerm_resource_group.kafka-cluster-rg.name
  network_interface_ids = [azurerm_network_interface.zookeeper-nic.id,]
  vm_size               = "Standard_B1s"
  delete_data_disks_on_termination = true
  
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "zookeeperdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "zookeeper1"
    admin_username = "zookeeperuser"
    admin_password = "Password123!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}


resource "null_resource" "zookeeper_installation" {
  depends_on = [azurerm_virtual_machine.zookeeper1]
  provisioner "remote-exec" {

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y openjdk-11-jdk",
      "wget https://downloads.apache.org/kafka/3.0.0/kafka_2.13-3.0.0.tgz",
      "chmod 777 kafka_2.13-3.8.0.tgz",
      "tar -xzf kafka_2.13-3.0.0.tgz",
      "ssh kafkauser@"
    ]
  }

  connection {
    type     = "ssh"
    user     = "zookeeperuser"
    password = "Password123!"
    port = "22"
    timeout = "5m"
    host     = data.azurerm_public_ip.zookeeper1_public_ips.ip_address
  }
}


output "zookeeper_ip" {
  value = azurerm_network_interface.zookeeper-nic.private_ip_address
}


output "zookeeper1_public_ip" {
  description = "The public IP of the Zookeeper VM"
  value       = azurerm_public_ip.zookeeper1_public_ip.ip_address
}*/




