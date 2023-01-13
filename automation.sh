#!/bin/bash -e
clear
echo "============================================"
echo " EMEA - AZURE CLI - ALL IN ONE              "
echo "============================================"

banner(){
  echo "+------------------------------------------+"
  printf "| %-40s |\n" "`date`"
  echo "|                                          |"
  printf "|`tput bold` %-40s `tput sgr0`|\n" "$@"
  echo "+------------------------------------------+"
}
banner "Azure Containers Chat Team - EMEA"
printf "|`tput bold` %-40s `tput sgr0`|\n" "Pre-requisites:"
printf "|`tput bold` %-40s `tput sgr0`|\n" "Install JQuery/JQ"
printf "|`tput bold` %-40s `tput sgr0`|\n" "Change params.sh - specific scenarios"
printf "|`tput bold` %-40s `tput sgr0`|\n" "Generate ssh key pair with"
printf "|`tput bold` %-40s `tput sgr0`|\n" "ssh-keygen -o -t rsa -b 4096 -C email"
printf "|`tput bold` %-40s `tput sgr0`|\n" "export ADMIN_USERNAME_SSH_KEYS_PUB"

sleep 2
showHelp() {
cat << EOF  
bash $SCRIPT_NAME --help/-h  [for help]
bash $SCRIPT_NAME --version/-v  [for version]
bash $SCRIPT_NAME -g/--group <aks-rg-name> -n/--name <aks-name> -k/--aks-version -l/--location 

-h,        --help                           Display Help

-g,        --resource-group                 AKS Resource Group Name

-n,        --name                           AKS Name			

-k,        --aks-version                    K8S Version

-l,        --location                       AKS Resource Group Location

-v,        --version                        Display Version

EOF
}
# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v1.0 20220204"

# Load parameters
set -e
. ./params.sh
# read the options
TEMP=`getopt -o g:n:k:l:hv --long resource-group:,name:,aks-version:,location:,help,version -n ${SCRIPT_NAME} -- "$@"`
eval set -- "$TEMP"
while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) AKS_RG_NAME="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) AKS_CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -k|--aks-version) case "$2" in
            "") shift 2;;
            *) AKS_VERSION="$2"; shift 2;;
            esac;;
        -l|--location) case "$2" in
            "") shift 2;;
            *) AKS_RG_LOCATION="$2"; shift 2;;
            esac;;
        -v|--version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 6 ;;
    esac
done
#if -h | --help option is selected usage will be displayed
if [[ $HELP -eq 1 ]]
then
    showHelp
	exit 0
fi

if [[ $VERSION -eq 1 ]]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\n--> Warning: You have to login first with the 'az login' command before you can run this automation script\n"
        az login -o table
    fi
}

# Check k8s version exists on location
function check_k8s_version () {
VERSION_EXIST=$(az aks get-versions -l $AKS_RG_LOCATION -ojson --query orchestrators[*].orchestratorVersion | jq -r ".[]" | grep $AKS_VERSION &>/dev/null; echo $?)
echo -e "\n--> Creating ${PURPOSE} cluster with Kubernetes version ${AKS_VERSION} on location ${AKS_RG_LOCATION}...\n"
if [ $VERSION_EXIST -ne 0 ]
then
    echo -e "\n--> Kubernetes version ${AKS_VERSION} does not exist on location ${AKS_RG_LOCATION}...\n"
    echo -e "\n--> Kubernetes version available version on ${AKS_VERSION} are:\n"
    az aks get-versions -l $AKS_RG_LOCATION -o table
    exit 0
fi
}

function destroy() {
  echo -e "\n--> Warning: You are about to delete the whole environment\n"
  AKS_GROUP_EXIST=$(az group show -g $AKS_RG_NAME &>/dev/null; echo $?)
  VM_GROUP_EXIST=$(az group show -g $LINUX_VM_RG &>/dev/null; echo $?)
  if [[ $AKS_GROUP_EXIST -eq 0 ]]
   then
      echo -e "\n--> Warning: Deleting $AKS_RG_NAME resource group ...\n"
      az group delete --name $AKS_RG_NAME
  elif [[ $VM_GROUP_EXIST -eq 0 ]]
   then
      echo -e "\n--> Warning: Deleting $LINUX_VM_RG resource group ...\n"
      az group delete --name $LINUX_VM_RG
      exit 5
   else
   echo -e "\n--> Info: Resource Groups $AKS_RG_NAME OR $LINUX_VM_RG don't exist in this subscription ...\n"
  fi
  
}

## Coundown function
function countdown() {
   IFS=:
   set -- $*
   secs=$(( ${1#0} * 3600 + ${2#0} * 60 + ${3#0} ))
   while [ $secs -gt 0 ]
   do
     sleep 1 &
     printf "\r%02d:%02d:%02d" $((secs/3600)) $(( (secs/60)%60)) $((secs%60))
     secs=$(( $secs - 1 ))
     wait
   done
   echo
 }


function azure_cluster() {
AKS_RG_NAME=$AKS_RG_NAME-$PURPOSE
AKS_CLUSTER_NAME=$AKS_CLUSTER_NAME-$PURPOSE
AKS_VNET="vnet-"$AKS_CLUSTER_NAME
AKS_SNET="snet-"$AKS_CLUSTER_NAME

## Create Resource Group for Cluster VNet
echo "Create RG for Cluster Vnet"
az group create \
  --name $AKS_RG_NAME \
  --location $AKS_RG_LOCATION \
  --tags env=$AKS_CLUSTER_NAME \
  --debug

## Create  VNet and Subnet
echo "Create Vnet and Subnet for AKS Cluster"
az network vnet create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_VNET \
  --address-prefix $AKS_VNET_CIDR \
  --subnet-name $AKS_SNET \
  --subnet-prefix $AKS_SNET_CIDR \
  --debug

## Get Subnet Info
echo "Getting Subnet ID"
AKS_SNET_ID=$(az network vnet subnet show \
  --resource-group $AKS_RG_NAME \
  --vnet-name $AKS_VNET \
  --name $AKS_SNET \
  --query id -o tsv)

## Create AKS Cluster
echo "Creating AKS Cluster"
if [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler, Managed Idenity and Network Policy = $AKS_NET_NPOLICY"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --network-policy $AKS_NET_NPOLICY \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug 
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler, Managed Identity and Net Pol $AKS_NET_NPOLICY"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, Managed Idenity and Net Pol $AKS_NET_NPOLICY"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug  
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Managed Identity and Net Pol $AKS_NET_NPOLICY"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Managed Identity and Network Policy = $AKS_NET_NPOLICY" 
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-managed-identity \
  --network-policy $AKS_NET_NPOLICY \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor" 
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with AutoScaler"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with AutoScaler MSI and Network Policy $AKS_NET_NPOLICY"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-cluster-autoscaler \
  --enable-managed-identity \
  --network-policy $AKS_NET_NPOLICY \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --yes \
  --os-sku $OS_SKU \
  --debug
else
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS without Monitor"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --api-server-authorized-ip-ranges $MY_HOME_PUBLIC_IP"/32" \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --zones $AKS_ZONES \
  --os-sku $OS_SKU \
  --debug
fi

## Logic for VMASS only
if [[ "$AKS_NP_VM_TYPE" == "AvailabilitySet" ]]; then
  echo "Skip second Nodepool - VMAS dont have it"
else
  if [[ "$AKS_HAS_2ND_NODEPOOL"  == "1" ]]; then
  ## Add User nodepooll
  echo 'Add Node pool type User'
  az aks nodepool add \
    --resource-group $AKS_RG_NAME \
    --name usrnp \
    --cluster-name $AKS_CLUSTER_NAME \
    --node-osdisk-type Ephemeral \
    --node-osdisk-size $AKS_USR_NP_NODE_DISK_SIZE \
    --kubernetes-version $AKS_VERSION \
    --tags "env=userpool" \
    --mode User \
    --node-count $AKS_USR_NP_NODE_COUNT \
    --node-vm-size $AKS_USR_NP_NODE_SIZE \
    --max-pods $AKS_MAX_PODS_PER_NODE \
    --zones $AKS_2ND_NP_ZONES \
    --os-sku $OS_SKU \
    --debug
  fi
fi


if [[ "$AKS_HAS_JUMP_SERVER" == "1" ]] 
then

  ## VM Jump Client subnet Creation
  echo "Create VM Subnet"
  az network vnet subnet create \
    --resource-group $AKS_RG_NAME \
    --vnet-name $AKS_VNET \
    --name $LINUX_VM_SUBNET_NAME \
    --address-prefixes $LINUX_VM_SNET_CIDR \
    --debug
  
  
  ## VM NSG Create
  echo "Create NSG"
  az network nsg create \
    --resource-group $AKS_RG_NAME \
    --name $LINUX_VM_NSG_NAME \
    --debug
  
  ## Public IP Create
  echo "Create Public IP"
  az network public-ip create \
    --name $LINUX_VM_PUBLIC_IP_NAME \
    --resource-group $AKS_RG_NAME \
    --debug
  
  
  ## VM Nic Create
  echo "Create VM Nic"
  az network nic create \
    --resource-group $AKS_RG_NAME \
    --vnet-name $LINUX_VNET_NAME \
    --subnet $LINUX_VM_SUBNET_NAME \
    --name $LINUX_VM_NIC_NAME \
    --network-security-group $LINUX_VM_NSG_NAME \
    --debug 
  
  ## Attache Public IP to VM NIC
  echo "Attach Public IP to VM NIC"
  az network nic ip-config update \
    --name $LINUX_VM_DEFAULT_IP_CONFIG \
    --nic-name $LINUX_VM_NIC_NAME \
    --resource-group $AKS_RG_NAME \
    --public-ip-address $LINUX_VM_PUBLIC_IP_NAME \
    --debug
  
  ## Update NSG in VM Subnet
  echo "Update NSG in VM Subnet"
  az network vnet subnet update \
    --resource-group $AKS_RG_NAME \
    --name $LINUX_VM_SUBNET_NAME \
    --vnet-name $AKS_VNET \
    --network-security-group $LINUX_VM_NSG_NAME \
    --debug

  ## Create VM
  echo "Create VM"
  az vm create \
    --resource-group $AKS_RG_NAME \
    --authentication-type $LINUX_AUTH_TYPE \
    --name $LINUX_VM_NAME \
    --computer-name $LINUX_VM_INTERNAL_NAME \
    --image $LINUX_VM_IMAGE \
    --size $LINUX_VM_SIZE \
    --admin-username $GENERIC_ADMIN_USERNAME \
    --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
    --storage-sku $LINUX_VM_STORAGE_SKU \
    --os-disk-size-gb $LINUX_VM_OS_DISK_SIZE \
    --os-disk-name $LINUX_VM_OS_DISK_NAME \
    --nics $LINUX_VM_NIC_NAME \
    --tags $LINUX_TAGS \
    --debug
  
  echo "Sleeping 45s - Allow time for Public IP"
  sleep 45
  
  ## Output Public IP of VM
  echo "Getting Public IP of VM"
  VM_PUBLIC_IP=$(az network public-ip list \
    --resource-group $AKS_RG_NAME \
    --output json | jq -r ".[] | select ( .name == \"$LINUX_VM_PUBLIC_IP_NAME\" ) | [ .ipAddress ] | @tsv")
  echo "Public IP of VM is:" 
  echo $VM_PUBLIC_IP

  ## Allow SSH from my Home
  echo "Update VM NSG to allow SSH"
  az network nsg rule create \
    --nsg-name $LINUX_VM_NSG_NAME \
    --resource-group $AKS_RG_NAME \
    --name ssh_allow \
    --priority 100 \
    --source-address-prefixes $MY_HOME_PUBLIC_IP \
    --source-port-ranges '*' \
    --destination-address-prefixes $LINUX_VM_PRIV_IP \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --description "Allow from MY ISP IP"
  
  ## Input Key Fingerprint
  echo "Input Key Fingerprint" 
  FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)
  
  while [[ "$FINGER_PRINT_CHECK" = "0" ]]
  do
    echo "not good to go: $FINGER_PRINT_CHECK"
    echo "Sleeping for 5s..."
    sleep 5
    FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)
  done
  
  echo "Go to go with Input Key Fingerprint"
  ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP >> ~/.ssh/known_hosts
  
  ## Copy to VM AKS SSH Priv Key
  echo "Copy to VM priv Key of AKS Cluster"
  scp  -o 'StrictHostKeyChecking no' -i $SSH_PRIV_KEY $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP:/home/$GENERIC_ADMIN_USERNAME/id_rsa
  
  ## Set Correct Permissions on Priv Key
  echo "Set good Permissions on AKS Priv Key"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "chmod 700 /home/$GENERIC_ADMIN_USERNAME/id_rsa"
  
  ## Install and update software
  echo "Updating VM and Stuff"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "sudo apt update && sudo apt upgrade -y"
  
  ## VM Install software
  echo "VM Install software"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo apt install tcpdump wget snap dnsutils -y

  ## Add Az Cli
  echo "Add Az Cli"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  
  ## Install Kubectl
  echo "Install Kubectl"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo snap install kubectl --classic
  
  ## Install JQ
  echo "Install JQ"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo snap install jq
  
  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "source <(kubectl completion bash)"

  ## Add Win password
  echo "Add Win password"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "touch ~/win-pass.txt && echo "$WINDOWS_AKS_ADMIN_PASSWORD" > ~/win-pass.txt"
  
  ## Create the SSH into Node Helper file
  echo "Process SSH into Node into SSH VM"
  AKS_1ST_NODE_IP=$(kubectl get nodes -o=wide | awk 'FNR == 2 {print $6}')
  AKS_STRING_TO_DO_SSH='ssh -o ServerAliveInterval=180 -o ServerAliveCountMax=2 -i id_rsa'
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP echo "$AKS_STRING_TO_DO_SSH $GENERIC_ADMIN_USERNAME@$AKS_1ST_NODE_IP >> gtno.sh"

  echo "Public IP of the VM"
  echo $VM_PUBLIC_IP

fi

## Get Credentials
echo "Getting Cluster Credentials"
az aks get-credentials --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME --overwrite-existing
}
function private_cluster () {
AKS_RG_NAME=$AKS_RG_NAME-$PURPOSE
AKS_CLUSTER_NAME=$AKS_CLUSTER_NAME-$PURPOSE
AKS_VNET="vnet-"$AKS_CLUSTER_NAME
AKS_SNET="snet-"$AKS_CLUSTER_NAME
LINUX_VM_RG=$LINUX_VM_RG-$PURPOSE

## Create Resource Group for Cluster VNet
echo "Create RG for Cluster Vnet"
az group create \
  --name $AKS_RG_NAME \
  --location $AKS_RG_LOCATION \
  --tags env=$AKS_CLUSTER_NAME \
  --debug


## Create  VNet and Subnet
echo "Create Vnet and Subnet for AKS Cluster"
az network vnet create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_VNET \
  --address-prefix $AKS_VNET_CIDR \
  --subnet-name $AKS_SNET \
  --subnet-prefix $AKS_SNET_CIDR \
  --debug


## Get Subnet Info
echo "Getting Subnet ID"
AKS_SNET_ID=$(az network vnet subnet show \
  --resource-group $AKS_RG_NAME \
  --vnet-name $AKS_VNET \
  --name $AKS_SNET \
  --query id \
  --output tsv)


## Create AKS Cluster
echo "Creating AKS Cluster"
if [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler, Managed Idenity and Network Policy = Azure"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --network-policy $AKS_NET_NPOLICY \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug 
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler, Managed Idenity"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, Managed Idenity"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug  
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor Enabled, AutoScaler"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Managed Identity"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-managed-identity \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Managed Identityi and Network Policy = Azure" 
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-managed-identity \
  --network-policy $AKS_NET_NPOLICY \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 1 && $AKS_HAS_AUTO_SCALER -eq 0 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with Monitor" 
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-addons monitoring \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 0 && $AKS_HAS_NETWORK_POLICY -eq 0 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with AutoScaler"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug
elif [[ $AKS_HAS_AZURE_MONITOR -eq 0 && $AKS_HAS_AUTO_SCALER -eq 1 && $AKS_HAS_MANAGED_IDENTITY -eq 1 && $AKS_HAS_NETWORK_POLICY -eq 1 ]]; then
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS with AutoScaler MSI and Network Policy"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --enable-cluster-autoscaler \
  --enable-managed-identity \
  --network-policy $AKS_NET_NPOLICY \
  --min-count 1 \
  --max-count 3 \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --yes \
  --debug
else
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  echo "Creating AKS without Monitor"
  echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  az aks create \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --service-principal $SP \
  --client-secret $SPPASS \
  --node-count $AKS_SYS_NP_NODE_COUNT \
  --node-vm-size $AKS_SYS_NP_NODE_SIZE \
  --location $AKS_RG_LOCATION \
  --load-balancer-sku standard \
  --vnet-subnet-id $AKS_SNET_ID \
  --vm-set-type $AKS_NP_VM_TYPE \
  --kubernetes-version $AKS_VERSION \
  --network-plugin $AKS_CNI_PLUGIN \
  --service-cidr $AKS_CLUSTER_SRV_CIDR \
  --dns-service-ip $AKS_CLUSTER_DNS \
  --docker-bridge-address $AKS_CLUSTER_DOCKER_BRIDGE \
  --ssh-key-value $ADMIN_USERNAME_SSH_KEYS_PUB \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --nodepool-name sysnp \
  --nodepool-tags "env=sysnp" \
  --max-pods $AKS_MAX_PODS_PER_NODE \
  --enable-private-cluster \
  --debug
fi

## Logic for VMASS only
if [[ "$AKS_NP_VM_TYPE" == "AvailabilitySet" ]]; then
  echo "Skip second Nodepool - VMAS dont have it"
else
  if [[ "$AKS_HAS_2ND_NODEPOOL"  == "1" ]]; then
  ## Add User nodepoll
  echo 'Add Node pool type User'
  az aks nodepool add \
    --resource-group $AKS_RG_NAME \
    --name usrnp \
    --cluster-name $AKS_CLUSTER_NAME \
    --node-osdisk-type Ephemeral \
    --node-osdisk-size $AKS_USR_NP_NODE_DISK_SIZE \
    --kubernetes-version $AKS_VERSION \
    --tags "env=usrnpool" \
    --mode User \
    --node-count $AKS_USR_NP_NODE_COUNT \
    --node-vm-size $AKS_USR_NP_NODE_SIZE \
    --max-pods $AKS_MAX_PODS_PER_NODE \
    --debug
  fi
fi


## If we already have an Jump Server with Peer Vnet
## Just do the Priv DNS setup
if [[ "$AKS_HAS_JUMP_SERVER" == "1" ]]
then
  ## Get Jump Server Vnet ID
  echo "Get Jump Server Vnet ID"
  LINUX_VM_VNET_ID=$(az network vnet list -o json | jq -r ".[] | select( .name == \"$EXISTING_JUMP_SERVER_VNET_NAME\" ) | [ .id ] | @tsv" | column -t)
  LINUX_VM_VNET_RG=$(az network vnet list -o json | jq -r ".[] | select( .name == \"$EXISTING_JUMP_SERVER_VNET_NAME\" ) | [ .resourceGroup ] | @tsv" | column -t)


  ## Configure Private DNS Link to Jumpbox VM
  echo "Configuring Private DNS Link to Jumpbox VM"
  echo "Get AKS Node RG"
  AKS_INFRA_RG=$(az aks show \
    --name $AKS_CLUSTER_NAME \
    --resource-group $AKS_RG_NAME \
    --query 'nodeResourceGroup' \
    --output tsv)


  echo "Get AKS Priv DNS Zone"
  AKS_INFRA_RG_PRIV_DNS_ZONE=$(az network private-dns zone list \
    --resource-group $AKS_INFRA_RG \
    --query [0].name \
    --output tsv)


  echo "Create Priv Dns Link to Jump Server Vnet"
  az network private-dns link vnet create \
    --name "${EXISTING_JUMP_SERVER_VNET_NAME}-in-${LINUX_VM_VNET_RG}" \
    --resource-group $AKS_INFRA_RG \
    --virtual-network $LINUX_VM_VNET_ID \
    --zone-name $AKS_INFRA_RG_PRIV_DNS_ZONE \
    --registration-enabled false \
    --debug 

fi


## If we want to have a Jump Server on a Diff Vnet to access
## The priv AKS Cluster, the next part is for it
if [[ "$AKS_CREATE_JUMP_SERVER" == "1" ]] 
then
  
  ## Create Resource Group for Jump AKS VNet
  echo "Configuring Networking for Jump AKS Vnet"
  az group create \
    --name $LINUX_VM_RG \
    --location $LINUX_VM_LOCATION \
    --debug

  ## Create Jump VNet and SubNet
  echo "Create Jump Box Vnet and Subnet"
  az network vnet create \
    --resource-group $LINUX_VM_RG \
    --name $LINUX_VM_VNET \
    --address-prefix $LINUX_VM_VNET_CIDR \
    --subnet-name $LINUX_VM_SUBNET_NAME \
    --subnet-prefix $LINUX_VM_SNET_CIDR \
    --debug

  
  ## VM NSG Create
  echo "Create NSG"
  az network nsg create \
    --resource-group $LINUX_VM_RG \
    --name $LINUX_VM_NSG_NAME \
    --debug
  
  ## Public IP Create
  echo "Create Public IP"
  az network public-ip create \
    --name $LINUX_VM_PUBLIC_IP_NAME \
    --resource-group $LINUX_VM_RG \
    --allocation-method dynamic \
    --sku basic \
    --debug
  
  ## VM Nic Create
  echo "Create VM Nic"
  az network nic create \
    --resource-group $LINUX_VM_RG \
    --vnet-name $LINUX_VM_VNET \
    --subnet $LINUX_VM_SUBNET_NAME \
    --name $LINUX_VM_NIC_NAME \
    --network-security-group $LINUX_VM_NSG_NAME \
    --debug 
  
  ## Attache Public IP to VM NIC
  echo "Attach Public IP to VM NIC"
  az network nic ip-config update \
    --name $LJ_DEFAULT_IP_CONFIG \
    --nic-name $LINUX_VM_NIC_NAME \
    --resource-group $LINUX_VM_RG \
    --public-ip-address $LINUX_VM_PUBLIC_IP_NAME \
    --debug
  
  ## Update NSG in VM Subnet
  echo "Update NSG in VM Subnet"
  az network vnet subnet update \
    --resource-group $LINUX_VM_RG \
    --name $LINUX_VM_SUBNET_NAME \
    --vnet-name $LINUX_VM_VNET \
    --network-security-group $LINUX_VM_NSG_NAME \
    --debug

  ## Create VM
  echo "Create VM"
  az vm create \
    --resource-group $LINUX_VM_RG \
    --authentication-type $LJ_AUTH_TYPE \
    --name $LINUX_VM_NAME \
    --computer-name $LINUX_VM_INTERNAL_NAME \
    --image $LINUX_VM_IMAGE \
    --size $LINUX_VM_SIZE \
    --admin-username $GENERIC_ADMIN_USERNAME \
    --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
    --storage-sku $LINUX_VM_STORAGE_SKU \
    --os-disk-size-gb $LINUX_VM_OS_DISK_SIZE \
    --os-disk-name $LINUX_VM_OS_DISK_NAME \
    --nics $LINUX_VM_NIC_NAME \
    --tags $LINUX_TAGS \
    --debug
  
  ## Output Public IP of VM
  echo "Getting Public IP of VM"
  VM_PUBLIC_IP=$(az network public-ip list \
    --resource-group $LINUX_VM_RG \
    --output json | jq -r ".[] | select ( .name == \"$LINUX_VM_PUBLIC_IP_NAME\" ) | [ .ipAddress ] | @tsv")
  echo "Public IP of VM is:" 
  echo $VM_PUBLIC_IP

  ## Allow SSH from my Home
  echo "Update VM NSG to allow SSH"
  az network nsg rule create \
    --nsg-name $LINUX_VM_NSG_NAME \
    --resource-group $LINUX_VM_RG \
    --name ssh_allow \
    --priority 100 \
    --source-address-prefixes $MY_HOME_PUBLIC_IP \
    --source-port-ranges '*' \
    --destination-address-prefixes $LINUX_VM_PRIV_IP \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --description "Allow from MY ISP IP"
 
  ## Peering Part
  echo "Configuring Peering - GET ID's"
  AKS_VNET_ID=$(az network vnet show \
    --resource-group $AKS_RG_NAME \
    --name $AKS_VNET \
    --query id \
    --output tsv)

  LINUX_VM_VNET_ID=$(az network vnet show \
    --resource-group $LINUX_VM_RG \
    --name $LINUX_VM_VNET \
    --query id \
    --output tsv)

  echo "Peering VNet - AKS-JBOX"
  az network vnet peering create \
    --resource-group $AKS_RG_NAME \
    --name "${AKS_VNET}-to-${LINUX_VM_VNET}" \
    --vnet-name $AKS_VNET \
    --remote-vnet $LINUX_VM_VNET_ID \
    --allow-vnet-access \
    --debug

  echo "Peering Vnet - JBOX-AKS"
  az network vnet peering create \
    --resource-group $LINUX_VM_RG \
    --name "${LINUX_VM_VNET}-to-${AKS_VNET}" \
    --vnet-name $LINUX_VM_VNET \
    --remote-vnet $AKS_VNET_ID \
    --allow-vnet-access \
    --debug

  ## Configure Private DNS Link to Jumpbox VM
  echo "Configuring Private DNS Link to Jumpbox VM"
  echo "Get AKS Node RG"
  AKS_INFRA_RG=$(az aks show \
    --name $AKS_CLUSTER_NAME \
    --resource-group $AKS_RG_NAME \
    --query 'nodeResourceGroup' \
    --output tsv) 
  
  echo "Get AKS Priv DNS Zone"
  AKS_INFRA_RG_PRIV_DNS_ZONE=$(az network private-dns zone list \
    --resource-group $AKS_INFRA_RG \
    --query [0].name \
    --output tsv)
  
  echo "Create Priv Dns Link to Jump Server Vnet"
  az network private-dns link vnet create \
    --name "${LINUX_VM_VNET}-${LINUX_VM_RG}" \
    --resource-group $AKS_INFRA_RG \
    --virtual-network $LINUX_VM_VNET_ID \
    --zone-name $AKS_INFRA_RG_PRIV_DNS_ZONE \
    --registration-enabled false \
    --debug  
  
    ## Input Key Fingerprint
    echo "Input Key Fingerprint" 
  FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)
  
  while [[ "$FINGER_PRINT_CHECK" = "0" ]]
  do
    echo "Not Good to Go: $FINGER_PRINT_CHECK"
    echo "Sleeping for 2s..."
    sleep 2
    FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)
  done
  
  echo "Go to go with Input Key Fingerprint"
  ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP >> ~/.ssh/known_hosts
  
  ## Copy to VM AKS SSH Priv Key
  echo "Copy to VM priv Key of AKS Cluster"
  scp  -o 'StrictHostKeyChecking no' -i $SSH_PRIV_KEY $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP:/home/$GENERIC_ADMIN_USERNAME/id_rsa
  
  ## Set Correct Permissions on Priv Key
  echo "Set good Permissions on AKS Priv Key"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "chmod 700 /home/$GENERIC_ADMIN_USERNAME/id_rsa"
  
  ## Install and update software
  echo "Updating VM and Stuff"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "sudo apt update && sudo apt upgrade -y"
 
  ## VM Install software
  echo "VM Install software"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo apt install tcpdump wget snap dnsutils -y

  ## Add Az Cli
  echo "Add Az Cli"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  
  ## Install Kubectl
  echo "Install Kubectl"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo snap install kubectl --classic
  
  ## Install JQ
  echo "Install JQ"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo snap install jq
  
  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "source <(kubectl completion bash)"

  ## Add Win password
  echo "Add Win password"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "touch ~/win-pass.txt && echo "$WINDOWS_AKS_ADMIN_PASSWORD" > ~/win-pass.txt"
  
  echo "Public IP of the VM"
  echo $VM_PUBLIC_IP

fi

## Get Credentials
echo "Getting Cluster Credentials"
az aks get-credentials \
  --resource-group $AKS_RG_NAME \
  --name $AKS_CLUSTER_NAME \
  --overwrite-existing
}


linux_dns () {

echo "On which Resource Group you want to install the DNS server"
read -e DNS_RG_NAME

## Create Resource Group for DNS Server
echo "Create RG for DNS Server"
az group create \
  --name $DNS_RG_NAME \
  --location $DNS_RG_LOCATION \
  --tags env=dns \
  --debug

## VM DNS Server Subnet Creation
echo "Create VM DNS Server Subnet"
az network vnet subnet create \
  --resource-group $DNS_RG_NAME \
  --vnet-name $DNS_VNET_NAME \
  --name $VM_DNS_SUBNET_NAME \
  --address-prefixes $VM_DNS_SNET_CIDR \
  --debug


## VM NSG Create
echo "Create NSG"
az network nsg create \
  --resource-group $MAIN_VNET_RG \
  --name $VM_NSG_NAME \
  --debug


## Public IP Create
echo "Create Public IP"
az network public-ip create \
  --name $VM_DNS_PUBLIC_IP_NAME \
  --resource-group $MAIN_VNET_RG \
  --debug


## VM Nic Create
echo "Create VM Nic"
az network nic create \
  --resource-group $MAIN_VNET_RG \
  --vnet-name $MAIN_VNET_NAME \
  --subnet $VM_DNS_SUBNET_NAME \
  --name $VM_NIC_NAME \
  --network-security-group $VM_NSG_NAME \
  --debug 


## Attach Public IP to VM NIC
echo "Attach Public IP to VM NIC"
az network nic ip-config update \
  --name $VM_DNS_DEFAULT_IP_CONFIG \
  --nic-name $VM_NIC_NAME \
  --resource-group $MAIN_VNET_RG \
  --public-ip-address $VM_DNS_PUBLIC_IP_NAME \
  --debug


## Update NSG in VM Subnet
echo "Update NSG in VM Subnet"
az network vnet subnet update \
  --resource-group $MAIN_VNET_RG \
  --name $VM_DNS_SUBNET_NAME \
  --vnet-name $MAIN_VNET_NAME \
  --network-security-group $VM_NSG_NAME \
  --debug


## Create VM
echo "Create VM"
az vm create \
  --resource-group $MAIN_VNET_RG \
  --authentication-type $VM_AUTH_TYPE \
  --name $VM_NAME \
  --computer-name $VM_INTERNAL_NAME \
  --image $VM_IMAGE \
  --size $VM_SIZE \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
  --storage-sku $VM_STORAGE_SKU \
  --os-disk-size-gb $VM_OS_DISK_SIZE \
  --os-disk-name $VM_OS_DISK_NAME \
  --nics $VM_NIC_NAME \
  --tags $VM_TAGS \
  --debug

echo "Sleeping 45s - Allow time for Public IP"
sleep 45

## Output Public IP of VM
echo "Public IP of VM is:"
VM_PUBLIC_IP=$(az network public-ip list \
  --resource-group $MAIN_VNET_RG \
  --output json | jq -r ".[] | select (.name==\"$VM_DNS_PUBLIC_IP_NAME\") | [ .ipAddress] | @tsv")

## Allow SSH from local ISP
echo "Update VM NSG to allow SSH"
az network nsg rule create \
  --nsg-name $VM_NSG_NAME \
  --resource-group $MAIN_VNET_RG \
  --name ssh_allow \
  --priority 100 \
  --source-address-prefixes $VM_MY_ISP_IP \
  --source-port-ranges '*' \
  --destination-address-prefixes $VM_DNS_PRIV_IP \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "Allow from MY ISP IP"


## Input Key Fingerprint
echo "Input Key Fingerprint" 
FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)

while [[ "$FINGER_PRINT_CHECK" = "0" ]]
do
    echo "not good to go: $FINGER_PRINT_CHECK"
    echo "Sleeping for 5s..."
    sleep 5
    FINGER_PRINT_CHECK=$(ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP | wc -l)
done

echo "Goood to go with Input Key Fingerprint"
ssh-keygen -F $VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $VM_PUBLIC_IP >> ~/.ssh/known_hosts

}

function linux_subnet(){

echo "On which Resource Group does the Subnet belong: "
read -e LINUX_RG_NAME

#LINUX_GROUP_EXIST=$(az group show -g $LINUX_RG_NAME &>/dev/null; echo $?)
#if [[ $LINUX_GROUP_EXIST -ne 0 ]]
#   then
#    echo -e "\n--> Creating the non existent Resource Group ${LINUX_RG_NAME} ...\n"
#    az group create --name $LINUX_RG_NAME --location $LINUX_RG_LOCATION
#fi

#read -p "Enter [y/n] : " opt

echo "On which Vnet do you want to deploy the Linux VM:"
read -e LINUX_VM_VNET_NAME

echo "On which Subnet do you want to deploy the Linux VM:"
read -e LINUX_VM_SUBNET_NAME

echo "What is the name of the NSG attached to the Subnet where you want to deploy the Linux VM:"
read -e SUBNET_NSG_NAME


 ## Public IP Create
echo "Create Public IP"
az network public-ip create \
  --name $LINUX_VM_PUBLIC_IP_NAME \
  --resource-group $LINUX_RG_NAME \
  --debug
## VM Nic Create
echo "Create VM Nic"
az network nic create \
  --resource-group $LINUX_RG_NAME \
  --vnet-name $LINUX_VM_VNET_NAME \
  --subnet $LINUX_VM_SUBNET_NAME \
  --name $LINUX_VM_NIC_NAME \
  --network-security-group $SUBNET_NSG_NAME \
  --debug

## Attach Public IP to VM NIC
echo "Attach Public IP to VM NIC"
az network nic ip-config update \
  --name $LINUX_VM_DEFAULT_IP_CONFIG \
  --nic-name $LINUX_VM_NIC_NAME \
  --resource-group $LINUX_RG_NAME \
  --public-ip-address $LINUX_VM_PUBLIC_IP_NAME \
  --debug

## Create VM
echo "Creating Virtual Machine...."
az vm create \
  --resource-group $LINUX_RG_NAME \
  --authentication-type $LINUX_AUTH_TYPE \
  --name $LINUX_VM_NAME \
  --computer-name $LINUX_VM_INTERNAL_NAME \
  --image $LINUX_VM_IMAGE \
  --size $LINUX_VM_SIZE \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
  --storage-sku $LINUX_VM_STORAGE_SKU \
  --os-disk-size-gb $LINUX_VM_OS_DISK_SIZE \
  --os-disk-name $LINUX_VM_OS_DISK_NAME \
  --nics $LINUX_VM_NIC_NAME \
  --tags $LINUX_TAGS \
  --debug 

  echo "Sleeping 30s - Allow time for Public IP"
  countdown "00:00:30"

  ## Output Public IP of VM
  echo "Getting Public IP of VM"
  LINUX_VM_PUBLIC_IP=$(az network public-ip list \
    --resource-group $LINUX_RG_NAME \
    --output json | jq -r ".[] | select ( .name == \"$LINUX_VM_PUBLIC_IP_NAME\" ) | [ .ipAddress ] | @tsv")
  echo "Public IP of VM is:"
  echo $LINUX_VM_PUBLIC_IP

  ## Get Priv IP of Linux JS VM
  echo "Getting Linux VM Priv IP"
  LINUX_PRIV_IP=$(az vm list-ip-addresses --resource-group $LINUX_RG_NAME --name $LINUX_VM_NAME --output json | jq -r ".[] | [ .virtualMachine.network.privateIpAddresses[0] ] | @tsv")

  ## Allow SSH from my Home
  echo "Update Subnet NSG to allow SSH"
  az network nsg rule create \
    --nsg-name $SUBNET_NSG_NAME \
    --resource-group $LINUX_RG_NAME \
    --name ssh_allow \
    --priority 100 \
    --source-address-prefixes $MY_HOME_PUBLIC_IP \
    --source-port-ranges '*' \
    --destination-address-prefixes $LINUX_PRIV_IP \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --description "Allow from MY ISP IP"

  ## Checking SSH connectivity
    echo "Testing SSH Conn..."
    while :
    do
      if [ "$(ssh -i "$LINUX_SSH_PRIV_KEY" -o 'StrictHostKeyChecking no' -o "BatchMode=yes" -o "ConnectTimeout 5" $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP echo up 2>&1)" == "up" ];
      then
        echo "Can connect to $LINUX_VM_PUBLIC_IP, continue"
        break
      else
        echo "Keep trying...."
       fi
     done

  echo "Go to go with Input Key Fingerprint"
  ssh-keygen -F $LINUX_VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $LINUX_VM_PUBLIC_IP >> ~/.ssh/known_hosts

  ## Install and update software
  echo "Updating VM and Stuff"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt update && sudo apt upgrade -y"

  ## VM Install software
  echo "VM Install software"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP sudo apt install tcpdump wget snap dnsutils -y

  ## Add Az Cli
  echo "Add Az Cli"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"

  ## Install Kubectl
  echo "Install Kubectl"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP sudo snap install kubectl --classic

  ## Install JQ
  echo "Install JQ"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP sudo snap install jq

  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "source <(kubectl completion bash)"

  echo "Public IP of the Virtual Machine:"
  echo $LINUX_VM_PUBLIC_IP
  
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP
}

function windows_subnet(){
# Windows Jump Server Public IP Create
echo "Create Public IP - Windows"
az network public-ip create \
  --name $WINDOWS_JS_PUBLIC_IP_NAME \
  --resource-group $RG_NAME \
  --debug

echo "Create Windows Jump Server NSG"
az network nsg create \
  --resource-group $RG_NAME \
  --name $WINDOWS_JS_NSG_NAME \
  --debug
## Windows VM Nic Create
echo "Create Windows VM Nic"
az network nic create \
  --resource-group $RG_NAME \
  --vnet-name $VNET_NAME \
  --subnet $VM_SUBNET_NAME \
  --name $WINDOWS_JS_NIC_NAME \
  --network-security-group $WINDOWS_JS_NSG_NAME \
  --debug

## Update NSG in Windows VM Subnet
echo "Update NSG in VM Subnet"
az network vnet subnet update \
  --resource-group $RG_NAME \
  --name $VM_SUBNET_NAME \
  --vnet-name $VNET_NAME \
  --network-security-group $WINDOWS_JS_NSG_NAME \
  --debug

### Windows Create VM
echo "Create Windows VM"
az vm create \
  --resource-group $RG_NAME \
  --name $WINDOWS_JS_NAME \
  --image $WINDOWS_JS_IMAGE \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --admin-password $WINDOWS_AKS_ADMIN_PASSWORD \
  --nics $WINDOWS_JS_NIC_NAME \
  --tags $WINDOWS_JS_TAGS \
  --computer-name $WINDOWS_JS_INTERNAL_NAME \
  --authentication-type password \
  --size $WINDOWS_JS_SIZE \
  --storage-sku $WINDOWS_JS_STORAGE_SKU \
  --os-disk-size-gb $WINDOWS_JS_OS_DISK_SIZE \
  --os-disk-name $WINDOWS_JS_OS_DISK_NAME \
  --nsg-rule NONE \
  --debug


# Getting Public IP of Windows JS VM
echo "Getting Public IP of Windows JS VM"
WINDOWS_JS_AZ_PUBLIC_IP=$(az network public-ip list \
  --resource-group $RG_NAME \
  --output json | jq --arg pip $WINDOWS_JS_PUBLIC_IP_NAME -r '.[] | select( .name == $pip ) | [ .ipAddress ] | @tsv')

PROCESS_NSG_FOR_LINUX_VM="true"
TIME=$SECONDS

## Get Priv IP of Windows JS VM
echo "Getting Windows JS VM Priv IP"
WINDOWS_JS_PRIV_IP=$(az vm list-ip-addresses --resource-group $RG_NAME --name $WINDOWS_JS_NAME --output json | jq -r ".[] | [ .virtualMachine.network.privateIpAddresses[0] ] | @tsv")


## Allow RDC from my Home to Windows JS VM
echo "Update Windows JS VM NSG to allow RDP"
az network nsg rule create \
  --nsg-name $WINDOWS_JS_NSG_NAME \
  --resource-group $RG_NAME \
  --name rdc_allow \
  --priority 100 \
  --source-address-prefixes $MY_HOME_PUBLIC_IP \
  --source-port-ranges '*' \
  --destination-address-prefixes $WINDOWS_JS_PRIV_IP \
  --destination-port-ranges 3389 \
  --access Allow \
  --protocol Tcp \
  --description "Allow from MY ISP IP"


echo ""
echo "Windows JS VM Public IP: $WINDOWS_JS_AZ_PUBLIC_IP"

}

options=("Azure Cluster" "Kubenet Cluster" "Private Cluster" "Linux DNS VM" "Windows DNS VM" "Create Linux VM on Subnet" "Create Windows VM on Subnet" "Destroy Environment" "Quit")
select opt in "${options[@]}"
do    
	case $opt in
        "Azure Cluster")
        az_login_check
        check_k8s_version
        sleep 2
        PURPOSE="cni"
        azure_cluster
        break;;
        "Kubenet Cluster")
        az_login_check
        PURPOSE="kubenet"
        AKS_CNI_PLUGIN="kubenet"
        check_k8s_version
        sleep 2
        azure_cluster
	      break;;
	    "Private Cluster")
        az_login_check
        PURPOSE="private"
        check_k8s_version
        sleep 2
        private_cluster
        break;;
        "Linux DNS VM")
        az_login_check
        linux_dns
        break;;
	      "Windows DNS VM")
        
        break;;
	      "Create Linux VM on Subnet")
        az_login_check
        linux_subnet
        break;;
        "Create Windows VM on Subnet")
        az_login_check
        windows_subnet
        break;;
	      "Destroy Environment")
        az_login_check
        echo ""
        destroy
        break;;
        "Quit")
         exit 0
            break
            ;;
        *) echo "Invalid Optiona $REPLY";;
    esac
done