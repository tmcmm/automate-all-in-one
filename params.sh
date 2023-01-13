## GENERAL VARIABLES
PURPOSE="default"
AKS_RG_LOCATION="westeurope"
AKS_VERSION="1.24.6"
AKS_VNET_2_OCTETS="10.4"   # Define the fisrt 2 octets for Vnet
AKS_ZONES="1 2 3"          # Define AKS Zones
AKS_2ND_NP_ZONES="1 2 3"   # Defines NP Zones

## AKS Vnet Settings
AKS_VNET_CIDR="$AKS_VNET_2_OCTETS.0.0/16"
AKS_SNET_CIDR="$AKS_VNET_2_OCTETS.0.0/23"
AKS_CLUSTER_SRV_CIDR="$AKS_VNET_2_OCTETS.2.0/24"
AKS_CLUSTER_DNS="$AKS_VNET_2_OCTETS.2.10"
AKS_CLUSTER_DOCKER_BRIDGE="172.17.0.1/16"


## AKS Add-ons and other options
AKS_HAS_AZURE_MONITOR="0"     # 1 = AKS has Az Mon enabled
AKS_HAS_AUTO_SCALER="0"       # 1 = AKS has Auto Scaler enabled
AKS_HAS_MANAGED_IDENTITY="0"  # 1 = AKS has Managed Identity enabled
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
AKS_SYS_NP_NODE_SIZE="Standard_D4s_v3"
AKS_USR_NP_NODE_SIZE="Standard_D4s_v3"
AKS_SYS_NP_NODE_COUNT="1"
AKS_USR_NP_NODE_COUNT="2"
AKS_SYS_NP_NODE_DISK_SIZE="90"
AKS_USR_NP_NODE_DISK_SIZE="100"
AKS_NP_VM_TYPE="VirtualMachineScaleSets"
AKS_MAX_PODS_PER_NODE="30"
ADMIN_USERNAME_SSH_KEYS_PUB=/home/$USER/.ssh/id_rsa.pub
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
LINUX_VM_VNET_CIDR="$AKS_VNET_2_OCTETS.6.0/24"
LINUX_VM_SUBNET_NAME="subnet-users"
LINUX_VM_SNET_CIDR="$AKS_VNET_2_OCTETS.7.0/28"
LINUX_VM_PRIV_IP="$AKS_VNET_2_OCTETS.7.4/32"
LINUX_VM_NSG_NAME="$LINUX_VM_NAME""_nsg"
LINUX_GENERIC_ADMIN_USERNAME="azureuser"
LINUX_SSH_PRIV_KEY="/home/$USER/.ssh/id_rsa"
LINUX_VM_DEFAULT_IP_CONFIG="ipconfig1"
LINUX_AUTH_TYPE="ssh"
LINUX_VM_NAME="sshclient-"$CONTEXT
LINUX_VM_INTERNAL_NAME="netdebug-vm"
LINUX_VM_PUBLIC_IP_NAME="$LINUX_VM_NAME""-publicip"
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
LINUX_VM_OS_DISK_NAME="$LINUX_VM_NAME""_disk_01"
LINUX_VM_NIC_NAME="$LINUX_VM_NAME""_nic01"
LINUX_TAGS="env=kubernetes"


## VM Settings for Jump Server - Private
LJ_LOCATION="$AKS_RG_LOCATION"
LJ_VNET="vnet-users"
LJ_RG="rg-vm-$AKS_CLUSTER_NAME"
LJ_VNET_CIDR="$AKS_VNET_2_OCTETS.6.0/24"
LJ_SNET="subnet-users"
LJ_SNET_CIDR="$AKS_VNET_2_OCTETS.7.0/28"
LJ_PRIV_IP="$AKS_VNET_2_OCTETS.7.4/32"
LJ_NAME="lclt-"$AKS_CLUSTER_NAME
LJ_INTERNAL_NAME="lclt-"$AKS_CLUSTER_NAME
LJ_IMAGE_PROVIDER="Canonical"
LJ_IMAGE_OFFER="UbuntuServer"
LJ_IMAGE_SKU="18.04-LTS"
LJ_IMAGE_VERSION="latest"

LJ_IMAGE="$LJ_IMAGE_PROVIDER:$LJ_IMAGE_OFFER:$LJ_IMAGE_SKU:$LJ_IMAGE_VERSION"
LJ_SIZE="Standard_D2s_v3"
LJ_OS_DISK_SIZE="40"
LJ_PIP="$LJ_NAME-pip"
LJ_DEFAULT_IP_CONFIG="ipconfig1"
LJ_STORAGE_SKU="Standard_LRS"
LJ_AUTH_TYPE="ssh"
LJ_NSG_NAME="$LJ_NAME""_nsg"
LJ_NIC_NAME="$LJ_NAME""nic01"
LJ_OS_DISK_NAME="$LJ_NAME""_disk_01"
LJ_TAGS="env=jump-server"

## DNS Parameters
DNS_RG_LOCATION="westeurope"
DNS_VNET_NAME="dns-vnet"
VM_DNS_SUBNET_NAME="dns-subnet"

## Running Options
JUST_BIND="0"              # 1 - If we just want to deploy Bind server
ALL="1"                    # 1 - If we want to deploy all, VM + Bind
AKS_VNET_PREFIX="10.3"     # Having in mind Vnet Peering, we need to make sure no Vnet overlaps
AKS_NAME="bcc"

## Core Networking
MAIN_VNET_RG="rg-aks-$AKS_NAME"
MAIN_VNET_NAME="vnet-aks-$AKS_NAME"
MAIN_VNET_LOCATION="westeurope"

## AKS SubNet details
AKS_SUBNET_CIDR="$AKS_VNET_PREFIX.0.0/23"

## Bind9 Forwarders
VM_BIND_FORWARDERS_01="168.63.129.16"
VM_BIND_FORWARDERS_02="1.1.1.1"

## VM Specific Networking
VM_DNS_SUBNET_NAME="snet-dns-server"
VM_DNS_SNET_CIDR="$AKS_VNET_PREFIX.10.0/28"
VM_DNS_PRIV_IP="$AKS_VNET_PREFIX.10.4/32"

## Local ISP PIP
VM_MY_ISP_IP=$(curl -s -4 ifconfig.io)

## Public IP Name
VM_DNS_PUBLIC_IP_NAME="dnssrvpip"
VM_DNS_DEFAULT_IP_CONFIG="ipconfig1"

## VM SSH Client
VM_RG_LOCATION=$MAIN_VNET_LOCATION
VM_AUTH_TYPE="ssh"
VM_NAME="dns-srv"
VM_INTERNAL_NAME="dns-srv"
VM_IMAGE_PROVIDER="Canonical"
VM_IMAGE_OFFER="UbuntuServer"
VM_IMAGE_SKU="18.04-LTS"
VM_IMAGE_VERSION="latest"
VM_IMAGE="$VM_IMAGE_PROVIDER:$VM_IMAGE_OFFER:$VM_IMAGE_SKU:$VM_IMAGE_VERSION"
VM_PUBLIC_IP="" 
VM_SIZE="Standard_D2s_v3"
VM_STORAGE_SKU="Standard_LRS"
VM_OS_DISK_SIZE="40"
VM_OS_DISK_NAME="$VM_NAME""_disk_01"
VM_NSG_NAME="$VM_NAME""_nsg"
VM_NIC_NAME="$VM_NAME""nic01"
VM_TAGS="purpose=dns-server"