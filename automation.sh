#!/bin/bash -e
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
printf "|`tput bold` %-40s `tput sgr0`|\n" "export WINDOWS_ADMIN_PASSWORD"
printf "|`tput bold` %-40s `tput sgr0`|\n" "export SUBID"

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
SCRIPT_VERSION="Version v3.0 20230922"

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
  LOGIN=$(az group list -o table &>/dev/null; echo $?)
  if [[ $LOGIN -ne 0 ]]
    then
      echo -e "\n--> Warning: You have to login first with the 'az login' command before you can run this automation script\n"
      az login --use-device-code
  fi
}

# Check k8s version exists on location
function check_k8s_version () {
VERSION_EXIST=$(az aks get-versions -l $AKS_RG_LOCATION -ojson --query values[*].patchVersions | jq 'map(values)[] | to_entries[] | {version: .key, upgrades: .value.upgrades}' | grep $AKS_VERSION &>/dev/null; echo $?)
#VERSION_EXIST=$(az aks get-versions -l $AKS_RG_LOCATION -ojson --query orchestrators[*].orchestratorVersion | jq -r ".[]" | grep $AKS_VERSION &>/dev/null; echo $?)
echo -e "\n--> Creating ${PURPOSE} cluster with Kubernetes version ${AKS_VERSION} on location ${AKS_RG_LOCATION}...\n"
if [ $VERSION_EXIST -ne 0 ]
then
    echo -e "\n--> Kubernetes version ${AKS_VERSION} does not exist on location ${AKS_RG_LOCATION}...\n"
    echo -e "\n--> Kubernetes version available on ${AKS_RG_LOCATION} location are:\n"
    az aks get-versions -l $AKS_RG_LOCATION -o table
    exit 0
fi
}

function destroy() {
  array=( kubenet cni private )
  echo -e "\n--> Warning: You are about to delete the whole environment\n"
  for i in ${array[@]}
  do
        PURPOSE=$i
        AKS_GROUP_EXIST=$(az group show -g $AKS_RG_NAME-$PURPOSE &>/dev/null; echo $?)
        VM_GROUP_EXIST=$(az group show -g  $LINUX_VM_RG-$PURPOSE &>/dev/null; echo $?)
  if [[ $AKS_GROUP_EXIST -eq 0 ]]
   then
      echo -e "\n--> Warning: Deleting $AKS_RG_NAME-$PURPOSE resource group ...\n"
      az group delete --name $AKS_RG_NAME-$PURPOSE
  elif [[ $VM_GROUP_EXIST -eq 0 ]]
   then
      echo -e "\n--> Warning: Deleting $LINUX_VM_RG-$PURPOSE resource group ...\n"
      az group delete --name $LINUX_VM_RG-$PURPOSE
   else
   echo -e "\n--> Info: Resource Groups $AKS_RG_NAME-$PURPOSE OR $LINUX_VM_RG-$PURPOSE don't exist in this subscription ...\n"
  fi
        echo "Deleted $i cluster resources if it existed"
  done
  
  
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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


if [[ "$AKS_CREATE_JUMP_SERVER" == "1" ]] 
then

  ## VM Jump Client subnet Creation
  echo "Create VM Subnet"
  az network vnet subnet create \
    --resource-group $AKS_RG_NAME \
    --vnet-name $AKS_VNET \
    --name $LINUX_VM_SUBNET_NAME \
    --address-prefixes $LINUX_VM_SNET_CIDR_CNI \
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
    --vnet-name $AKS_VNET \
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
  
  echo "Sleeping 30s - Allow time for Public IP"
  countdown "00:00:30"
  
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
    --destination-address-prefixes $LINUX_VM_PRIV_IP_CNI \
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
  
## Install Helm
  echo "Install Helm3"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  ## Install JQ

  echo "Install JQ"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP sudo snap install jq
  
  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "source <(kubectl completion bash)"

  ## Save Windows Password
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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
  --node-resource-group $AKS_NODE_RESOURCE_GROUP-$PURPOSE \
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

  echo $LINUX_VM_NSG_NAME
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
    --name $LINUX_VM_DEFAULT_IP_CONFIG \
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
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "sudo apt install tcpdump wget snap dnsutils -y"

  ## Add Az Cli
  echo "Add Az Cli"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  
  ## Install Kubectl
  echo "Install Kubectl"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "sudo snap install kubectl --classic"
  
  ## Install Helm
  echo "Install Helm3"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" 

  ## Install JQ
  echo "Install JQ"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "sudo snap install jq"
  
  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "source <(kubectl completion bash)"

  ## Add Win password
  echo "Add Win password"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "touch ~/win-pass.txt && echo "$WINDOWS_AKS_ADMIN_PASSWORD" > ~/win-pass.txt"

  ## Get Credentials
  echo "Get Cluster credentials"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "az login --use-device"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "az account set --subscription $SUBID"
  ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$VM_PUBLIC_IP "az aks get-credentials --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME"
  
  echo "Public IP of the VM"
  echo $VM_PUBLIC_IP

fi

}

linux_dns () {
echo "What is the Resource Group name where you want to deploy Linux DNS Server"
read -e LINUX_RG_NAME

echo "On which Resource Group does your AKS VNET is:"
read -e AKS_RG_NAME

echo "What is the Cluster Name:"
read -e AKS_CLUSTER_NAME

echo "What is the VNET Name of your AKS:"
read -e AKS_VNET_NAME

LINUX_RG_NAME_EXIST=$(az group show -g $LINUX_RG_NAME &>/dev/null; echo $?)
if [[ $LINUX_RG_NAME_EXIST -ne 0 ]]
  then
    echo -e "\n--> Creating the non existent Resource Group ${LINUX_RG_NAME} ...\n"
    az group create --name $LINUX_RG_NAME --location $LINUX_VM_LOCATION
  else
    echo "The Resource Group already exists - Continue"
fi

## LINUX VM DNS Server Vnet and Subnet Creation
echo "Create Linux DNS Server Vnet & Subnet"
az network vnet create \
  --resource-group $LINUX_RG_NAME \
  --name $LINUX_DNS_VNET_NAME \
  --address-prefix $LINUX_DNS_VNET_CIDR \
  --subnet-name $LINUX_DNS_SUBNET_NAME \
  --subnet-prefix $LINUX_DNS_SNET_CIDR \
  --debug

AKS_VNET_ID=$(az network vnet show --resource-group $AKS_RG_NAME --name $AKS_VNET_NAME --query id --output tsv)
LINUX_VM_VNET_ID=$(az network vnet show --resource-group $LINUX_RG_NAME --name $LINUX_DNS_VNET_NAME --query id --output tsv)

echo "Peering VNet - AKS-LinuxDNS"
az network vnet peering create \
  --resource-group $AKS_RG_NAME \
  --name "${AKS_VNET_NAME}-to-${LINUX_DNS_VNET_NAME}" \
  --vnet-name $AKS_VNET_NAME \
  --remote-vnet $LINUX_VM_VNET_ID \
  --allow-vnet-access \
  --debug

echo "Peering Vnet - LinuxDNS-AKS"
az network vnet peering create \
  --resource-group $LINUX_RG_NAME \
  --name "${LINUX_DNS_VNET_NAME}-to-${AKS_VNET_NAME}" \
  --vnet-name $LINUX_DNS_VNET_NAME \
  --remote-vnet $AKS_VNET_ID \
  --allow-vnet-access \
  --debug

## VM NSG Create
echo "Create NSG"
az network nsg create \
  --resource-group $LINUX_RG_NAME \
  --name $LINUX_DNS_NSG_NAME \
  --debug

## Public IP Create
echo "Create Public IP"
az network public-ip create \
  --name $LINUX_DNS_PUBLIC_IP_NAME \
  --resource-group $LINUX_RG_NAME \
  --debug

## VM Nic Create
echo "Create VM Nic"
az network nic create \
  --resource-group $LINUX_RG_NAME \
  --vnet-name $LINUX_DNS_VNET_NAME \
  --subnet $LINUX_DNS_SUBNET_NAME \
  --name $LINUX_DNS_NIC_NAME \
  --network-security-group $LINUX_DNS_NSG_NAME \
  --debug 

## Attach Public IP to VM NIC
echo "Attach Public IP to VM NIC"
az network nic ip-config update \
  --name $VM_DNS_DEFAULT_IP_CONFIG \
  --nic-name $LINUX_DNS_NIC_NAME \
  --resource-group $LINUX_RG_NAME \
  --public-ip-address $LINUX_DNS_PUBLIC_IP_NAME \
  --debug

## Update NSG in VM Subnet
echo "Update NSG in VM Subnet"
az network vnet subnet update \
  --resource-group $LINUX_RG_NAME \
  --name $LINUX_DNS_SUBNET_NAME \
  --vnet-name $LINUX_DNS_VNET_NAME \
  --network-security-group $LINUX_DNS_NSG_NAME \
  --debug

## Create VM
echo "Create VM"
az vm create \
  --resource-group $LINUX_RG_NAME \
  --authentication-type $LINUX_AUTH_TYPE \
  --name $LINUX_DNS_VM_NAME \
  --computer-name $LINUX_DNS_INTERNAL_VM_NAME \
  --image $LINUX_VM_IMAGE \
  --size $LINUX_VM_SIZE \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
  --storage-sku $LINUX_VM_STORAGE_SKU \
  --os-disk-size-gb $LINUX_VM_OS_DISK_SIZE \
  --os-disk-name $LINUX_DNS_DISK_NAME \
  --nics $LINUX_DNS_NIC_NAME \
  --tags $LINUX_DNS_VM_TAGS \
  --debug

echo "Sleeping 10s - Allow time for Public IP"
  countdown "00:00:10"

## Output Public IP of VM
DNS_VM_PUBLIC_IP=$(az network public-ip list \
  --resource-group $LINUX_RG_NAME \
  --output json | jq -r ".[] | select (.name==\"$LINUX_DNS_PUBLIC_IP_NAME\") | [ .ipAddress] | @tsv")

echo "Public IP of VM is:"
echo $DNS_VM_PUBLIC_IP

## Allow SSH from local ISP
echo "Update VM NSG to allow SSH"
az network nsg rule create \
  --nsg-name $LINUX_DNS_NSG_NAME \
  --resource-group $LINUX_RG_NAME \
  --name ssh_allow \
  --priority 100 \
  --source-address-prefixes $MY_HOME_PUBLIC_IP \
  --source-port-ranges '*' \
  --destination-address-prefixes $LINUX_VM_DNS_PRIV_IP \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "Allow from MY ISP IP"

## Input Key Fingerprint
echo "Input Key Fingerprint" 
FINGER_PRINT_CHECK=$(ssh-keygen -F $DNS_VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $DNS_VM_PUBLIC_IP | wc -l)

while [[ "$FINGER_PRINT_CHECK" = "0" ]]
do
    echo "not good to go: $FINGER_PRINT_CHECK"
    echo "Sleeping for 5s..."
    sleep 5
    FINGER_PRINT_CHECK=$(ssh-keygen -F $DNS_VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $DNS_VM_PUBLIC_IP | wc -l)
done

echo "Goood to go with Input Key Fingerprint"
ssh-keygen -F $DNS_VM_PUBLIC_IP >/dev/null | ssh-keyscan -H $DNS_VM_PUBLIC_IP >> ~/.ssh/known_hosts


echo "Write to Bind Config File "
printf "
logging {
          channel "misc" {
                    file \"/var/log/named/misc.log\" versions 4 size 4m;
                    print-time YES;
                    print-severity YES;
                    print-category YES;
          };
  
          channel "query" {
                    file \"/var/log/named/query.log\" versions 4 size 4m;
                    print-time YES;
                    print-severity NO;
                    print-category NO;
          };
  
          category default {
                    "misc";
          };
  
          category queries {
                    "query";
          };
};


acl goodclients {
    localhost;
    $AKS_SNET_CIDR;
};

options {
        directory \"/var/cache/bind\";

        forwarders {
                $VM_BIND_FORWARDERS_01;
                $VM_BIND_FORWARDERS_02;
        };

        recursion yes;

        allow-query { goodclients; };

        dnssec-validation auto;

        auth-nxdomain no;    # conform to RFC1035
        listen-on-v6 { any; };
};
" >> $LIN_BIND_CONFIG_FILE_NAME

echo "Write to Bind DNS Zone File "
printf "
\$TTL 86400
@       IN      SOA     aks.$LIN_ZONE_NAME. admin.$LIN_ZONE_NAME. (
                        $(date +%Y%m%d)   ; Serial
                        3600              ; Refresh
                        1800              ; Retry
                        604800            ; Expire
                        86400             ; Minimum TTL
                )

@       IN      NS      aks.$LIN_ZONE_NAME.
aks     IN      A       $LINUX_VM_DNS_PRIV_IP
@       IN      A       5.6.7.8
www     IN      CNAME   $LIN_ZONE_NAME.
"  >> $LIN_BIND_DNS_FILE_NAME

echo "Write to local dns zone file "
printf "
// Do any local configuration here
//

// Consider adding the 1918 zones here, if they are not used in your
// organization
//include "/etc/bind/zones.rfc1918";

zone \"$LIN_ZONE_NAME\" {
    type master;
    file \"/etc/bind/$LIN_BIND_DNS_FILE_NAME\";
};
"  >> $LIN_ZONE_LOCAL_FILE

## Update DNS Server VM
echo "Update DNS Server VM and Install Bind9"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo apt update && sudo apt upgrade -y"

## Install Bind9
echo "Install Bind9"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo apt install vim bind9 -y"

## Setup Bind9
echo "Setup Bind9"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo cp /etc/bind/named.conf.options /etc/bind/named.conf.options.backup"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo cp /etc/bind/named.conf.local /etc/bind/named.conf.local.backup"

## Create Bind9 Logs folder
echo "Create Bind9 Logs folder"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo mkdir /var/log/named"

## Setup good permission in Bind9 Logs folder - change owner
echo "Setup good permission in Bind9 Logs folder - change owner"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo chown -R bind:bind /var/log/named"

## Setup good permission in Bind9 Logs folder - change permissions
echo "Setup good permission in Bind9 Logs folder - change permissions"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo chmod -R 775 /var/log/named"

## Copy Bind Config file to DNS Server
echo "Copy Bind Config File to Remote DNS server"
scp -i $SSH_PRIV_KEY $LIN_BIND_CONFIG_FILE_NAME $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP:/tmp

## sudo cp options file to /etc/bind/
echo "Copy the Bind File to /etc/bind"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo cp /tmp/$LIN_BIND_CONFIG_FILE_NAME /etc/bind"

## Copy Bind DNS file to DNS Server
echo "Copy Bind DNS File to Remote DNS server"
scp -i $SSH_PRIV_KEY $LIN_BIND_DNS_FILE_NAME $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP:/tmp

## sudo cp options file to /etc/bind/
echo "Copy the Bind File to /etc/bind"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo cp /tmp/$LIN_BIND_DNS_FILE_NAME /etc/bind"

## Copy Bind Config file to DNS Server
echo "Copy Bind Config File to Remote DNS server"
scp -i $SSH_PRIV_KEY $LIN_ZONE_LOCAL_FILE $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP:/tmp

## sudo cp options file to /etc/bind/
echo "Copy the Bind File to /etc/bind"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo cp /tmp/$LIN_ZONE_LOCAL_FILE /etc/bind"

## sudo systemctl stop bind9
echo "Stop Bind9"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo systemctl stop bind9"

## sudo systemctl start bind9
echo "Start Bind9"
ssh -i $SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$DNS_VM_PUBLIC_IP "sudo systemctl start bind9"


CORE_DNS_CONFIGMAP="configmap.yaml"

echo "Cleaning up Bind Config File"
rm -rf $CORE_DNS_CONFIGMAP

echo "Write to Core DNS Custom ConfigMap"
printf "
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  byodnsio.server: | 
    $LIN_ZONE_NAME:53 {
        log 
        errors
        cache 15
        forward . $LINUX_VM_DNS_PRIV_IP
    }   " >> $CORE_DNS_CONFIGMAP

echo "Cleaning up Bind Config File"
rm -rf $LIN_BIND_CONFIG_FILE_NAME

echo "Cleaning up Bind dns zone File"
rm -rf $LIN_BIND_DNS_FILE_NAME

echo "Cleaning up Bind dns zone File"
rm -rf $LIN_ZONE_LOCAL_FILE

## Get Credentials
echo "Getting Cluster Credentials"
az aks get-credentials --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME --overwrite-existing

echo "Apply CoreDNS ConfigMap"
kubectl apply -f $CORE_DNS_CONFIGMAP 

## Re-deploy CoreDNS pods 
echo "Re-deploy CoreDNS pods"
kubectl rollout restart -n kube-system deployment/coredns

echo "Cleaning up Bind Config File"
rm -rf $CORE_DNS_CONFIGMAP

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

echo "On which Vnet do you want to deploy the Linux VM:"
read -e LINUX_VM_VNET_NAME

echo "On which Subnet do you want to deploy the Linux VM:"
read -e LINUX_VM_SUBNET_NAME

echo "What is the name of the NSG attached to the Subnet where you want to deploy the Linux VM:"
read -e SUBNET_NSG_NAME


 ## Public IP Create
echo "Create Public IP"
az network public-ip create \
  --name $LINUX_SUBNET_VM_PUBLIC_IP_NAME \
  --resource-group $LINUX_RG_NAME \
  --debug
## VM Nic Create
echo "Create VM Nic"
az network nic create \
  --resource-group $LINUX_RG_NAME \
  --vnet-name $LINUX_VM_VNET_NAME \
  --subnet $LINUX_VM_SUBNET_NAME \
  --name $LINUX_VM_SUBNET_NIC_NAME \
  --network-security-group $SUBNET_NSG_NAME \
  --debug

## Attach Public IP to VM NIC
echo "Attach Public IP to VM NIC"
az network nic ip-config update \
  --name $LINUX_VM_DEFAULT_IP_CONFIG \
  --nic-name $LINUX_VM_SUBNET_NIC_NAME \
  --resource-group $LINUX_RG_NAME \
  --public-ip-address $LINUX_SUBNET_VM_PUBLIC_IP_NAME \
  --debug

## Create VM
echo "Creating Virtual Machine...."
az vm create \
  --resource-group $LINUX_RG_NAME \
  --authentication-type $LINUX_AUTH_TYPE \
  --name $LINUX_VM_NAME_SUBNET \
  --computer-name $LINUX_VM_INTERNAL_NAME \
  --image $LINUX_VM_IMAGE \
  --size $LINUX_VM_SIZE \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --ssh-key-values $ADMIN_USERNAME_SSH_KEYS_PUB \
  --storage-sku $LINUX_VM_STORAGE_SKU \
  --os-disk-size-gb $LINUX_VM_OS_DISK_SIZE \
  --os-disk-name $LINUX_DISK_NAME_SUBNET \
  --nics $LINUX_VM_SUBNET_NIC_NAME \
  --tags $LINUX_TAGS \
  --debug 

  echo "Sleeping 30s - Allow time for Public IP"
  countdown "00:00:30"

  ## Output Public IP of VM
  echo "Getting Public IP of VM"
  LINUX_VM_PUBLIC_IP=$(az network public-ip list \
    --resource-group $LINUX_RG_NAME \
    --output json | jq -r ".[] | select ( .name == \"$LINUX_SUBNET_VM_PUBLIC_IP_NAME\" ) | [ .ipAddress ] | @tsv")
  echo "Public IP of VM is:"
  echo $LINUX_VM_PUBLIC_IP

  ## Get Priv IP of Linux JS VM
  echo "Getting Linux VM Priv IP"
  LINUX_PRIV_IP=$(az vm list-ip-addresses --resource-group $LINUX_RG_NAME --name $LINUX_VM_NAME_SUBNET --output json | jq -r ".[] | [ .virtualMachine.network.privateIpAddresses[0] ] | @tsv")

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
  echo "Updating VM and installing required software"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt update && sudo apt upgrade -y"

  echo "Installing ca-certificates curl gnupg:"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt-get install ca-certificates curl gnupg -y"
  echo "Adding Docker's official GPG key:"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo mkdir -m 0755 -p /etc/apt/keyrings; curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  echo "Setup docker's repository"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
  
    ## VM Install software
  echo "Installing Docker Software..."
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt-get update -y"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt install docker-ce docker-ce-cli containerd.io -y"

  ## VM Install software
  echo "VM Install software"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo apt install tcpdump wget snap dnsutils -y"

  ## Add Az Cli
  echo "Add Az Cli"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"

  ## Install Kubectl
  echo "Install Kubectl"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo snap install kubectl --classic"
  
## Install Helm
  echo "Install Helm3"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

  ## Install JQ
  echo "Install JQ"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "sudo snap install jq"

  ## Add Kubectl completion
  echo "Add Kubectl completion"
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP "source <(kubectl completion bash)"

  echo "Public IP of the Virtual Machine:"
  echo $LINUX_VM_PUBLIC_IP
  
  ssh -i $LINUX_SSH_PRIV_KEY $GENERIC_ADMIN_USERNAME@$LINUX_VM_PUBLIC_IP
}

function windows_dns(){
WINDOWS_RG_NAME_EXIST=$(az group show -g $WINDOWS_RG_NAME &>/dev/null; echo $?)
if [[ $WINDOWS_RG_NAME_EXIST -ne 0 ]]
  then
    echo -e "\n--> Creating the non existent Resource Group ${WINDOWS_RG_NAME} ...\n"
    az group create --name $WINDOWS_RG_NAME --location $WINDOWS_DNS_LOCATION
  else
    echo "The Resource Group already exists - Continue"
fi

## WINDOWS VM DNS Server Vnet and Subnet Creation
echo "Create Windows DNS Server Vnet & Subnet"
az network vnet create \
  --resource-group $WINDOWS_RG_NAME \
  --name $WINDOWS_VM_VNET_NAME \
  --address-prefix $WINDOWS_VM_VNET_CIDR \
  --subnet-name $WINDOWS_VM_SUBNET_NAME \
  --subnet-prefix $WINDOWS_VM_SNET_CIDR \
  --debug

AKS_VNET_ID=$(az network vnet show --resource-group $AKS_RG_NAME --name $AKS_VNET_NAME --query id --output tsv)
WINDOWS_VM_VNET_ID=$(az network vnet show --resource-group $WINDOWS_RG_NAME --name $WINDOWS_VM_VNET_NAME --query id --output tsv)

echo "Peering VNet - AKS-WinDNS"
az network vnet peering create \
  --resource-group $AKS_RG_NAME \
  --name "${AKS_VNET_NAME}-to-${WINDOWS_VM_SUBNET_NAME}" \
  --vnet-name $AKS_VNET_NAME \
  --remote-vnet $WINDOWS_VM_VNET_ID \
  --allow-vnet-access \
  --debug

echo "Peering Vnet - WinDNS-AKS"
az network vnet peering create \
  --resource-group $WINDOWS_RG_NAME \
  --name "${WINDOWS_VM_SUBNET_NAME}-to-${AKS_VNET_NAME}" \
  --vnet-name $WINDOWS_VM_VNET_NAME \
  --remote-vnet $AKS_VNET_ID \
  --allow-vnet-access \
  --debug

## Public IP Create
echo "Create Public IP"
az network public-ip create \
  --name $WINDOWS_DNS_PUBLIC_IP_NAME \
  --resource-group $WINDOWS_RG_NAME \
  --debug

echo "Sleeping 10s - Allow time for Public IP to be created"
countdown "00:00:10"

## VM NSG Create
echo "Create NSG"
az network nsg create \
  --resource-group $WINDOWS_RG_NAME \
  --name $WINDOWS_NSG_NAME \
  --debug

## VM Nic Create
echo "Create VM Nic"
az network nic create \
  --resource-group $WINDOWS_RG_NAME \
  --vnet-name $WINDOWS_VM_VNET_NAME \
  --subnet $WINDOWS_VM_SUBNET_NAME \
  --name $WINDOWS_DNS_NIC_NAME \
  --network-security-group $WINDOWS_NSG_NAME \
  --debug 

## Attach Public IP to VM NIC
echo "Attach Public IP to VM NIC"
az network nic ip-config update \
  --name $VM_DNS_DEFAULT_IP_CONFIG \
  --nic-name $WINDOWS_DNS_NIC_NAME \
  --resource-group $WINDOWS_RG_NAME \
  --public-ip-address $WINDOWS_DNS_PUBLIC_IP_NAME \
  --debug

## Update NSG in VM Subnet
echo "Update NSG in VM Subnet"
az network vnet subnet update \
  --resource-group $WINDOWS_RG_NAME \
  --name $WINDOWS_VM_SUBNET_NAME \
  --vnet-name $WINDOWS_VM_VNET_NAME \
  --network-security-group $WINDOWS_NSG_NAME \
  --debug

## Windows Create VM
echo "Create Windows VM"
echo $WIN_VM_IMAGE
az vm create \
  --resource-group $WINDOWS_RG_NAME \
  --name $WINDOWS_VM_NAME \
  --image "MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest"  \
  --admin-username $GENERIC_ADMIN_USERNAME \
  --admin-password $WINDOWS_ADMIN_PASSWORD \
  --nics $WINDOWS_DNS_NIC_NAME \
  --tags $WINDOWS_VM_TAGS \
  --computer-name $WINDOWS_VM_INTERNAL_NAME \
  --authentication-type password \
  --size $WINDOWS_VM_SIZE \
  --storage-sku $WINDOWS_VM_STORAGE_SKU \
  --os-disk-size-gb $WINDOWS_VM_OS_DISK_SIZE \
  --os-disk-name $WINDOWS_VM_OS_DISK_NAME \
  --nsg-rule NONE \
  --debug

echo "Sleeping 30s - Allow time for Windows VM Creation"
countdown "00:00:30"
## Output Public IP of VM
WIN_VM_PUBLIC_IP=$(az network public-ip list --resource-group $WINDOWS_RG_NAME -o json | jq -r ".[] | [.name, .ipAddress] | @csv" | grep $WINDOWS_DNS_PUBLIC_IP_NAME | awk -F "," '{print $2}')
WIN_VM_PUBLIC_IP_PARSED=$(echo $WIN_VM_PUBLIC_IP | sed 's/"//g')

echo "Public IP of VM is:"
echo $WIN_VM_PUBLIC_IP_PARSED

## Allow RDP from local ISP
echo "Update VM NSG to allow RDP"
az network nsg rule create \
  --nsg-name $WINDOWS_NSG_NAME \
  --resource-group $WINDOWS_RG_NAME \
  --name rdp_allow \
  --priority 100 \
  --source-address-prefixes $MY_HOME_PUBLIC_IP \
  --source-port-ranges '*' \
  --destination-address-prefixes $WINDOWS_VM_PRIV_IP \
  --destination-port-ranges 3389 \
  --access Allow \
  --protocol Tcp \
  --description "Allow from MY ISP IP"

az vm run-command invoke --resource-group $WINDOWS_RG_NAME --name $WINDOWS_VM_NAME \
   --command-id RunPowerShellScript \
   --scripts "Install-WindowsFeature -name DNS -IncludeManagementTools -IncludeAllSubFeature"
   
az vm run-command invoke --resource-group $WINDOWS_RG_NAME --name $WINDOWS_VM_NAME \
   --command-id RunPowerShellScript \
   --scripts "Add-DnsServerPrimaryZone -Name '$WIN_ZONE' -ZoneFile '$WIN_ZONE.dns'"
   
az vm run-command invoke --resource-group $WINDOWS_RG_NAME --name $WINDOWS_VM_NAME \
   --command-id RunPowerShellScript \
   --scripts "Add-DnsServerResourceRecordA -Name '@' -Ipv4address '$WIN_A_RECORD_IP' -ZoneName '$WIN_ZONE' ; Add-DnsServerResourceRecordCName -Name 'www' -HostNameAlias '$WIN_ZONE' -ZoneName '$WIN_ZONE'"
   
### Change DNS server for AKS VNET
echo "Changing $AKS_VNET_NAME DNS configuration"
az network vnet update --resource-group $AKS_RG_NAME --name $AKS_VNET_NAME --dns-servers $WINDOWS_VM_PRIV_IP


echo "Sleeping 10s - Allow time for DNS Servers to be changed at VNET Level"
countdown "00:00:10"


printf "|`tput bold` %-40s `tput sgr0`|\n" "After changing the DNS server at VNET level you will need to perform a DHCP_Release on the nodes so trigger the script again and choose option 8"
}

function dhcp_release() {
### Perform a DHCP release on the cluster nodes
NODE_RESOURCE_GROUP=$(az aks show --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME --query nodeResourceGroup --output tsv)
NODE_INSTANCES_NAME=($(az vmss list --resource-group $NODE_RESOURCE_GROUP --query [].name --output tsv))

for vmssName in "${NODE_INSTANCES_NAME[@]}"
do
    #  Perform DHCP release for each of the vmss instance
    echo "Performing DHCP release for each $vmssName instance"
    az vmss list-instances --resource-group  $NODE_RESOURCE_GROUP --name $vmssName --query "[].id" --output tsv | az vmss run-command invoke --scripts "{ dhclient -x; dhclient -i eth0; sleep 10; pkill dhclient; grep nameserver /etc/resolv.conf; }" --command-id RunShellScript --ids @-
done
}

function list_aks() {
function printTable(){
    local -r delimiter="${1}"
    local -r data="$(removeEmptyLines "${2}")"

    if [[ "${delimiter}" != '' && "$(isEmptyString "${data}")" = 'false' ]]
    then
        local -r numberOfLines="$(wc -l <<< "${data}")"

        if [[ "${numberOfLines}" -gt '0' ]]
        then
            local table=''
            local i=1

            for ((i = 1; i <= "${numberOfLines}"; i = i + 1))
            do
                local line=''
                line="$(sed "${i}q;d" <<< "${data}")"

                local numberOfColumns='0'
                numberOfColumns="$(awk -F "${delimiter}" '{print NF}' <<< "${line}")"

                # Add Line Delimiter

                if [[ "${i}" -eq '1' ]]
                then
                    table="${table}$(printf '%s#+' "$(repeatString '#+' "${numberOfColumns}")")"
                fi

                # Add Header Or Body

                table="${table}\n"

                local j=1

                for ((j = 1; j <= "${numberOfColumns}"; j = j + 1))
                do
                    table="${table}$(printf '#| %s' "$(cut -d "${delimiter}" -f "${j}" <<< "${line}")")"
                done

                table="${table}#|\n"

                # Add Line Delimiter

                if [[ "${i}" -eq '1' ]] || [[ "${numberOfLines}" -gt '1' && "${i}" -eq "${numberOfLines}" ]]
                then
                    table="${table}$(printf '%s#+' "$(repeatString '#+' "${numberOfColumns}")")"
                fi
            done

            if [[ "$(isEmptyString "${table}")" = 'false' ]]
            then
                echo -e "${table}" | column -s '#' -t | sed 's/^  //' | awk '/^\+/{gsub(" ", "-", $0)}1'
           fi
        fi
    fi
}

function removeEmptyLines()
{
    local -r content="${1}"

    echo -e "${content}" | sed '/^\s*$/d'
}

function repeatString()
{
    local -r string="${1}"
    local -r numberToRepeat="${2}"

    if [[ "${string}" != '' && "${numberToRepeat}" =~ ^[1-9][0-9]*$ ]]
    then
        local -r result="$(printf "%${numberToRepeat}s")"
        echo -e "${result// /${string}}"
    fi
}

function isEmptyString()
{
    local -r string="${1}"

    if [[ "$(trimString "${string}")" = '' ]]
    then
        echo 'true' && return 0
    fi

    echo 'false' && return 1
}

function trimString()
{
    local -r string="${1}"

    sed 's,^[[:blank:]]*,,' <<< "${string}" | sed 's,[[:blank:]]*$,,'
}



AKS_ARRAY=($(az aks list --output json | jq -r ".[] | [ .name, .location, .resourceGroup, .kubernetesVersion, .provisioningState, .azurePortalFqdn ] | @csv"))

declare -a AKS_STATUS_ARRAY
AKS_STATUS_ARRAY=("ClusterName,Location,RG,K8SVersion,Status,FQDN")

for akscl in "${AKS_ARRAY[@]}"; do
     AKS_CL_ARRAY=($(echo $akscl | tr -d '"' |tr "," "\n"))
     
     ## Get Cluster Status
     AKS_STATUS=$(az aks show --name ${AKS_CL_ARRAY[0]} --resource-group ${AKS_CL_ARRAY[2]} -o json | jq -r '.powerState.code')

     AKS_STATUS_ARRAY+=("${AKS_CL_ARRAY[0]},${AKS_CL_ARRAY[1]},${AKS_CL_ARRAY[2]},${AKS_CL_ARRAY[3]},$AKS_STATUS,${AKS_CL_ARRAY[5]}")
done

clear
for i in "${AKS_STATUS_ARRAY[@]}"
do
   AKS_STATUS_LIST+=$i"\n"
done

printTable ',' $AKS_STATUS_LIST

}

function helm_nginx_internal(){

echo -e "\n--> Warning: You must target a public faced cluster or run the script from the Jump Server in case its private\n"
echo -e "\n--> ......Installing Helm.....\n"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
echo "What is the Resource Group of your Cluster:"
read -e AKS_RG_NAME
echo "What is the Cluster Name:"
read -e AKS_CLUSTER_NAME

## Get Credentials
echo "Getting Cluster Credentials"
az aks get-credentials --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME --overwrite-existing

## Add the ingress-nginx repository
echo "Add Ingress Controller Helm Repo"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

## Install 
echo "Install Nginx Ingress"
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-basic --create-namespace \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.image.digest="" \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.image.digest="" \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.image.digest="" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"=true \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz


## Get PIP of LB
echo "Get PIP of LB"
LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip' | wc -l)

while [[ "$LB_PIP" = "0" ]]
do
    echo "not good to go: $LB_PIP"
    echo "Sleeping for 5s..."
    sleep 5
    LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip' | wc -l)
done

echo "Go to go with LB PIP"
LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip')
echo "LB PIP is: $LB_PIP"
}


function helm_nginx (){

echo -e "\n--> Warning: You must target a public faced cluster or run the script from the Jump Server in case its private\n"
echo -e "\n--> ......Installing Helm.....\n"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
echo "What is the Resource Group of your Cluster:"
read -e AKS_RG_NAME
echo "What is the Cluster Name:"
read -e AKS_CLUSTER_NAME

## Get Credentials
echo "Getting Cluster Credentials"
az aks get-credentials --resource-group $AKS_RG_NAME --name $AKS_CLUSTER_NAME --overwrite-existing

## Add the ingress-nginx repository
echo "Add Ingress Controller Helm Repo"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

## Install 
echo "Install Nginx Ingress"
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-basic --create-namespace \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.image.digest="" \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.image.digest="" \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.image.digest="" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz


## Get PIP of LB
echo "Get PIP of LB"
LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip' | wc -l)

while [[ "$LB_PIP" = "0" ]]
do
    echo "not good to go: $LB_PIP"
    echo "Sleeping for 5s..."
    sleep 5
    LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip' | wc -l)
done

echo "Go to go with LB PIP"
LB_PIP=$(kubectl get svc -A -n nginx-ingress-ingress-nginx-controller --no-headers -o json | jq -r '.items[].status.loadBalancer.ingress[]?.ip')
echo "LB PIP is: $LB_PIP"

## Deploy Apps
echo "App 01"
kubectl apply -f app-01.yaml -n ingress-basic
echo ""
echo "App 02"
kubectl apply -f app-02.yaml -n ingress-basic
echo "Deploy AKS App Ingress Controller"
kubectl apply -f app-ingress.yaml --namespace ingress-basic


}


function agic_brownfield (){

echo -e "\n--> Warning: You must target a public faced cluster or run the script from the Jump Server in case its private\n"  
echo -e "\n--> Brownfield assumes that you have already an existing AKS cluster\n"
echo "What is the Resource Group of your Cluster:"
read -e AKS_RG_NAME
echo "What is the Cluster Name:"
read -e AKS_CLUSTER_NAME
echo "What is the Resource Group where you want to deploy your App Gateway?"
read -e APPGTW_RG_NAME

echo "Creating the Resource Group for APP Gateway Resource..."
az group create \
  --name $APPGTW_RG_NAME \
  --location $AKS_RG_LOCATION \
  --tags env=agic \
  --debug

echo "Creating the Public IP Address for the App Gateway..."
az network public-ip create \
  --name $APPGTW_PIP_NAME \
  --resource-group $APPGTW_RG_NAME \
  --allocation-method Static \
  --sku Standard

echo "Sleeping 30s - Allow time for Public IP"
countdown "00:00:30"

echo "Creating the VNET and Subnet for App Gateway..."
az network vnet create \
  --name $APPGTW_VNET_NAME \
  --resource-group $APPGTW_RG_NAME \
  --address-prefix $APPGTW_VNET_CIDR \
  --subnet-name $APPGTW_SNET_NAME \
  --subnet-prefix $APPGTW_SNET_CIDR

echo "Creating the App Gateway Resource..."
az network application-gateway create \
  --name $APPGTW_NAME \
  --resource-group $APPGTW_RG_NAME \
  --sku Standard_v2 \
  --public-ip-address $APPGTW_PIP_NAME \
  --vnet-name $APPGTW_VNET_NAME \
  --subnet $APPGTW_SNET_NAME \
  --priority 100 \
  --debug \
  --verbose

echo "Sleeping 30secs - Allow time for App Gateway to be created"
countdown "00:00:30"


APP_GTW_ID=$(az network application-gateway show --name $APPGTW_NAME --resource-group $APPGTW_RG_NAME -o tsv --query "id")

echo "App Gateway is created on $APP_GTW_ID"

echo "Enabling AGIC addon on the AKS cluster..."

az aks enable-addons --name $AKS_CLUSTER_NAME --resource-group $AKS_RG_NAME -a ingress-appgw --appgw-id $APP_GTW_ID

echo "Sleeping 30s - Allow time for addon to be enabled IP"
countdown "00:00:30"

echo "Peer the two VNETs together..."


AKS_VNET=$(az network vnet list --resource-group $AKS_RG_NAME -o tsv --query "[0].name")

AKS_VNET_ID=$(az network vnet show --name $AKS_VNET --resource-group $AKS_RG_NAME -o tsv --query "id")

az network vnet peering create \
  --name AppGWtoAKSVnetPeering \
  --resource-group $APPGTW_RG_NAME \
  --vnet-name $APPGTW_VNET_NAME \
  --remote-vnet $AKS_VNET_ID \
  --allow-vnet-access

APP_GTW_VNET_ID=$(az network vnet show --name $APPGTW_VNET_NAME --resource-group $APPGTW_RG_NAME -o tsv --query "id")

az network vnet peering create \
  --name AKStoAppGWVnetPeering \
  --resource-group $AKS_RG_NAME \
  --vnet-name $AKS_VNET \
  --remote-vnet $APP_GTW_VNET_ID \
  --allow-vnet-access


printf "|`tput bold` %-40s `tput sgr0`|\n" "In case you have an existing AKS cluster using Kubenet mode you need to update the route table to help the packets destined for a POD IP reach the node which is hosting the pod. A simple way to achieve this is by associating the same route table created by AKS to the Application Gateway's subnet."

}

options=("Azure Cluster" "Kubenet Cluster" "Private Cluster" "List existing AKS Clusters" "Create Linux VM on Subnet" "Linux DNS VM" "Windows DNS VM" "DHCP Release" "Helm Nginx Ingress Controller" "Helm Nginx Ingress Controller-Internal" "AGIC-Brownfield" "Destroy Environment" "Quit")
select opt in "${options[@]}"
do    
	case $opt in
      "Azure Cluster")
        az_login_check
        PURPOSE="cni"
        check_k8s_version
        sleep 2
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
	    "List existing AKS Clusters")
        az_login_check
        sleep 2
        list_aks
        break;;
      "Create Linux VM on Subnet")
        az_login_check
        linux_subnet
        break;;
      "Linux DNS VM")
        az_login_check
        linux_dns
        break;;
      "Windows DNS VM")
        az_login_check
        echo "What is the Resource Group name where you want to deploy Windows DNS Server"
        read -e WINDOWS_RG_NAME
        echo "On which Resource Group does your AKS VNET is:"
        read -e AKS_RG_NAME
        echo "What is the Cluster Name:"
        read -e AKS_CLUSTER_NAME
        echo "What is the VNET Name of your AKS:"
        read -e AKS_VNET_NAME
        windows_dns
        break;;
      "DHCP Release")
        az_login_check
        echo "What is the Resource Group of your AKS:"
        read -e AKS_RG_NAME
        echo "What is the Cluster Name:"
        read -e AKS_CLUSTER_NAME
        dhcp_release
        break;;
	    "Helm Nginx Ingress Controller")
        az_login_check
        helm_nginx
        break;;
	    "Helm Nginx Ingress Controller-Internal")
        az_login_check
        helm_nginx_internal
        break;;
	    "AGIC-Brownfield")
        az_login_check
        agic_brownfield
        break;;
	    "Destroy Environment")
        az_login_check
        destroy
        break;;
        "Quit")
         exit 0
            break
            ;;
        *) echo "Invalid Option $REPLY";;
    esac
done
