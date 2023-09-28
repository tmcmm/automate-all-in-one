## GENERAL VARIABLES
PURPOSE="default"
AKS_RG_LOCATION="westeurope"
AKS_VERSION="1.24.9"
AKS_VNET_2_OCTETS="10.4"   # Define the fisrt 2 octets for Vnet
LINUX_VNET_2_OCTETS="10.5" # Define the fisrt 2 octets for Linux Vnet
WINDOWS_VNET_2_OCTETS="10.6" # Define the fisrt 2 octets for Windows Vnet
APPGTW_VNET_2_OCTETS="10.7" # Define the fisrt 2 octets for Windows Vnet
AKS_ZONES="1 2 3"          # Define AKS Zones
AKS_2ND_NP_ZONES="1 2 3"   # Defines NP Zones

## AKS Vnet Settings
AKS_VNET_CIDR="$AKS_VNET_2_OCTETS.0.0/16"
AKS_SNET_CIDR="$AKS_VNET_2_OCTETS.0.0/23"
AKS_CLUSTER_SRV_CIDR="$AKS_VNET_2_OCTETS.2.0/24"
AKS_CLUSTER_DNS="$AKS_VNET_2_OCTETS.2.10"
AKS_CLUSTER_DOCKER_BRIDGE="172.17.0.1/16"

## APP Gateway Vnet Settings
APPGTW_VNET_CIDR="$APPGTW_VNET_2_OCTETS.0.0/16"
APPGTW_SNET_CIDR="$APPGTW_VNET_2_OCTETS.0.0/23"
APPGTW_VNET_NAME="appgateway-vnet"
APPGTW_SNET_NAME="appgateway-snet"

## APP Gateway General
APPGTW_PIP_NAME="appgtw-pip"
APPGTW_NAME="appgtw"

## AKS Add-ons and other options
AKS_HAS_AZURE_MONITOR="0"     # 1 = AKS has Az Mon enabled
AKS_HAS_AUTO_SCALER="0"       # 1 = AKS has Auto Scaler enabled
AKS_HAS_MANAGED_IDENTITY="1"  # 1 = AKS has Managed Identity enabled
AKS_HAS_NETWORK_POLICY="0"    # 1 = AKS has Azure Net Pol enabled
AKS_HAS_2ND_NODEPOOL="1"      # 1 = AKS has second npool
AKS_CREATE_JUMP_SERVER="1"    # 1 = If we need to create a JS from Other Vnet 
AKS_HAS_JUMP_SERVER="0"       # 1 = If we already have a Jump Server from Other Vnet, with Peered Vnet 

#########################################################################
## If AKS_HAS_JUMP_SERVER="1" then we need to define the setting below
#########################################################################
EXISTING_JUMP_SERVER_VNET_NAME="vnet-vm-jpsrv"

## AKS Specifics
AKS_RG_NAME="rg-aks"
AKS_CLUSTER_NAME="aks"
AKS_NODE_RESOURCE_GROUP="MC_NODERG-"$AKS_RG_LOCATION
AKS_SYS_NP_NODE_SIZE="Standard_D4s_v3"
AKS_USR_NP_NODE_SIZE="Standard_D4s_v3"
AKS_SYS_NP_NODE_COUNT="1"
AKS_USR_NP_NODE_COUNT="2"
AKS_SYS_NP_NODE_DISK_SIZE="90"
AKS_USR_NP_NODE_DISK_SIZE="100"
AKS_NP_VM_TYPE="VirtualMachineScaleSets"
AKS_MAX_PODS_PER_NODE="30"
ADMIN_USERNAME_SSH_KEYS_PUB=/home/$USER/.ssh/id_rsa.pub
SSH_PRIV_KEY=/home/$USER/.ssh/id_rsa
GENERIC_ADMIN_USERNAME="azureuser"

# OS SKU
OS_SKU="Ubuntu"   # CBLMariner, Ubuntu, Windows2019, Windows2022

## AKS Networking
AKS_CNI_PLUGIN="azure"
AKS_VNET="vnet-"$AKS_CLUSTER_NAME
AKS_SNET="snet-"$AKS_CLUSTER_NAME
AKS_NET_NPOLICY="azure"   # calico or azure

## My ISP PIP
MY_HOME_PUBLIC_IP=$(curl -s -4 ifconfig.io)

## VM Settings for Jump Server
CONTEXT="networking"
LINUX_VM_LOCATION="$AKS_RG_LOCATION"
LINUX_VM_VNET="vnet-users"
LINUX_VM_RG="rg-vm-$AKS_CLUSTER_NAME"
LINUX_VM_VNET_CIDR="$LINUX_VNET_2_OCTETS.6.0/24"
LINUX_VM_SUBNET_NAME="subnet-users"
LINUX_VM_SNET_CIDR_CNI="$AKS_VNET_2_OCTETS.6.0/28"
LINUX_VM_SNET_CIDR="$LINUX_VNET_2_OCTETS.6.0/28"
LINUX_VM_PRIV_IP_CNI="$AKS_VNET_2_OCTETS.6.4/32"
LINUX_VM_PRIV_IP="$LINUX_VNET_2_OCTETS.6.4/32"
LINUX_VM_NAME="sshclient-"$CONTEXT
LINUX_VM_NAME_SUBNET="ssh-troubleshooting-subnet"
LINUX_DISK_NAME_SUBNET="$LINUX_VM_NAME_SUBNET""_disk01"
LINUX_VM_SUBNET_NIC_NAME="$LINUX_VM_NAME_SUBNET""_nic01"
LINUX_VM_INTERNAL_NAME="netdebug-vm"
LINUX_VM_NSG_NAME="$LINUX_VM_NAME""_nsg"
LINUX_GENERIC_ADMIN_USERNAME="azureuser"
LINUX_SSH_PRIV_KEY="/home/$USER/.ssh/id_rsa"
LINUX_VM_DEFAULT_IP_CONFIG="ipconfig1"
LINUX_AUTH_TYPE="ssh"
LINUX_VM_PUBLIC_IP_NAME="$LINUX_VM_NAME""-pip"
LINUX_SUBNET_VM_PUBLIC_IP_NAME="$LINUX_VM_NAME_SUBNET""-pip"
LINUX_VM_IMAGE_PROVIDER="Canonical"
LINUX_VM_IMAGE_OFFER="0001-com-ubuntu-server-focal"
LINUX_VM_IMAGE_SKU="20_04-lts-gen2"
LINUX_VM_IMAGE_VERSION="latest"
# For Ubuntu 18_04 Gen1 Machine ##############################
#LINUX_VM_IMAGE_PROVIDER="Canonical"
#LINUX_VM_IMAGE_OFFER="UbuntuServer"
#LINUX_VM_IMAGE_SKU="18.04-LTS"
#LINUX_VM_IMAGE_VERSION="latest"
##############################################################
LINUX_VM_IMAGE="$LINUX_VM_IMAGE_PROVIDER:$LINUX_VM_IMAGE_OFFER:$LINUX_VM_IMAGE_SKU:$LINUX_VM_IMAGE_VERSION"
LINUX_VM_SIZE="Standard_D2s_v3"
LINUX_VM_STORAGE_SKU="Standard_LRS"
LINUX_VM_OS_DISK_SIZE="40"
LINUX_VM_OS_DISK_NAME="$LINUX_VM_NAME""_disk01"
LINUX_VM_NIC_NAME="$LINUX_VM_NAME""_nic01"
LINUX_TAGS="env=kubernetes"




## Windows DNS Parameters
WINDOWS_DNS_LOCATION="westeurope"
WINDOWS_VM_VNET_NAME="windows-vnet-dns"
WINDOWS_VM_VNET_CIDR="$WINDOWS_VNET_2_OCTETS.6.0/24"
WINDOWS_VM_SUBNET_NAME="windows-subnet-dns"
WINDOWS_VM_SNET_CIDR="$WINDOWS_VNET_2_OCTETS.6.0/28"
WINDOWS_VM_PRIV_IP="$WINDOWS_VNET_2_OCTETS.6.4"
WINDOWS_DNS_PUBLIC_IP_NAME="windows-dns-pip"
WINDOWS_NSG_NAME="windows-dns-nsg"
WINDOWS_DNS_NIC_NAME="windows-dns-nic01"
WINDOWS_VM_NAME="windows-brownbag-dns"
WINDOWS_VM_INTERNAL_NAME="windows-dns"
WINDOWS_VM_OS_DISK_NAME="windows-dns_disk_01"
WINDOWS_VM_IMAGE_PROVIDER="MicrosoftWindowsServer"
WINDOWS_VM_IMAGE_OFFER="WindowsServer"
WINDOWS_VM_IMAGE_SKU="2019-Datacenter"
WINDOWS_VM_IMAGE_VERSION="latest"
#WINDOWS_VM_IMAGE="$WIN_VM_IMAGE_PROVIDER:$WIN_VM_IMAGE_OFFER:$WIN_VM_IMAGE_SKU:$WIN_VM_IMAGE_VERSION"
WINDOWS_VM_IMAGE="MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest"
WINDOWS_VM_SIZE="Standard_D4s_v3"
WINDOWS_VM_STORAGE_SKU="Standard_LRS"
WINDOWS_VM_OS_DISK_SIZE="130"
WINDOWS_VM_TAGS="dns=brownbag"
WIN_ZONE="emeabrownbag-win.containers"
WIN_A_RECORD_IP="104.214.228.93"


## Linux DNS Parameters


## Public IP Name
VM_DNS_PUBLIC_IP_NAME="$DNS_VM_NAME""-pip"
VM_DNS_DEFAULT_IP_CONFIG="ipconfig1"
CONTEXT="dns"
LINUX_DNS_VM_NAME="linux"-$CONTEXT
LINUX_DNS_INTERNAL_VM_NAME="linux-dns-internal"
LINUX_DNS_VNET_NAME="linux-dns-vnet"
LINUX_DNS_SUBNET_NAME="linux-dns-subnet"
LINUX_DNS_VNET_CIDR="$LINUX_VNET_2_OCTETS.7.0/24"
LINUX_DNS_SNET_CIDR="$LINUX_VNET_2_OCTETS.7.0/28"
LINUX_DNS_NSG_NAME="$LINUX_DNS_VM_NAME""-nsg"
LINUX_DNS_PUBLIC_IP_NAME="linux-dns-pip"
LINUX_DNS_NIC_NAME="$LINUX_DNS_VM_NAME""-nic01"
LINUX_DNS_DISK_NAME="$LINUX_DNS_VM_NAME""_disk_01"
LINUX_DNS_VM_TAGS="purpose=dns-server"
LINUX_VM_DNS_PRIV_IP="$LINUX_VNET_2_OCTETS.7.4"

## Bind9 Forwarders
VM_BIND_FORWARDERS_01="168.63.129.16"
VM_BIND_FORWARDERS_02="1.1.1.1"

## Zone parameters
LIN_BIND_CONFIG_FILE_NAME="named.conf.options"
LIN_ZONE_NAME="emeabrownbag-lin.containers"
LIN_BIND_DNS_FILE_NAME="$LIN_ZONE_NAME.zone"
LIN_ZONE_LOCAL_FILE="named.conf.local"

