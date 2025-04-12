#!/bin/bash 

#This script will create a hub and spoke network topology with your desired number of Vnets /n

#!/bin/bash

set -x

# Update the Azure CLI extension for virtual network manager
az extension update --name virtual-network-manager

# Display the purpose of the script
printf "This script will create a mesh network topology with your desired number of Vnets /n
and a network manager + network group for administration(Central US). This script will use your default subscription for scope and access. \n"

# Function to get the default subscription ID
getDefaultSubscriptionId() {
    defaultSubscriptionId=$(az account list --query "[?isDefault].id" -o tsv | tr -d '\r')
    echo "Default subscription ID is: $defaultSubscriptionId"
}

# Variables
networkManagerName="myNetworkManager"
resourceGroup="networkManagerRG"
myLocation="centralus"

#Variables for tagging
tagKey="NetworkType"
tagValue="Production"

networkGroupName="myNetworkGroup"
# Policy names
vNetPolicyName="vNetPolicy"
azPolicyName="vNetPolicyAssignment"

# Configuration name
configName="HubSpokeConfig"
Topology="HubandSpoke"
commitType="Connectivity"

# Virtual network and gateway names
myHubVnet="vnetHUB"
myVnet="vnet00"
myVnetGateway="vnetGateway"
myVnetGatewayIP="vnetGatewaypip" 

# Create the resource group if it doesn't exist
createRG() {
    az group create --name $resourceGroup --location $myLocation
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create resource group."
        exit 1
    fi
}

# Create the network manager
createNetworkManager() {
    az network manager create \
        --name $networkManagerName \
        --resource-group $resourceGroup \
        --location $myLocation \
        --scope-access "Connectivity" "SecurityAdmin" \
        --network-manager-scopes subscriptions="/subscriptions/$defaultSubscriptionId"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create network manager."
        exit 1
    fi
}
# Create the hub network
createHubNetwork() {
    az network vnet create \
        --name $myHubVnet \
        --resource-group $resourceGroup \
        --location $myLocation \
        --address-prefix 10.0.0.0/16 \
        --subnet-name hubSubnet \
        --subnet-prefixes 10.0.0.0/24 
        echo "Successfully created Hub Virtual Network"
    if [ $? -ne 0 ]; then
        echo "Error: Faied to create Hub Virtual Network"
        exit 1
    fi  
}

# Create the GatewaySubnet
createGatewaySubnet() {
    az network vnet subnet create \
        --vnet-name $myHubVnet \
        --name "GatewaySubnet" \
        --resource-group $resourceGroup \
        --address-prefix "10.0.255.0/27"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create GatewaySubnet."
        exit 1
    fi
}

# Request a public IP address for the gateway
requestIpAddress() {
    az network public-ip create \
        --name VNETpip1 \
        --resource-group $resourceGroup \
        --allocation-method Static \
        --sku Standard \
        --version IPv4
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create public IP address."
        exit 1
    fi
}

# Create the virtual network gateway
createVirtualNetworkGateway() {
    az network vnet-gateway create \
        --name $myVnetGateway \
        --location $myLocation \
        --resource-group $resourceGroup \
        --public-ip-address VNETpip1 \
        --gateway-type Vpn \
        --vpn-gateway-generation Generation1 \
        --vnet $myHubVnet \
        --sku VpnGw1 \
        --vpn-type RouteBased \
        --no-wait 
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create VNet gateway."
        exit 1
    fi
}

# Create VNets
createVNets() {
    read -p "How many VNets do you want to create? " numVNets
    if ! [[ "$numVNets" =~ ^[2-9]+$ ]]; then
        echo "VNet quantity must be a number > 2."
        createVNets
        return
    fi
    for ((i=1; i<=numVNets; i++))
    do
        az network vnet create \
            --name $myVnet$i \
            --resource-group $resourceGroup \
            --location $myLocation \
            --address-prefixes 10.$i.0.0/16 \
            --subnet-name mySubnet$i \
            --subnet-prefixes 10.$i.0.0/24 \
            --tags $tagKey=$tagValue

            my_array+=("$myVnet$i")
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create VNet myVNet$i."
            exit 1
        fi
    done
    echo "$numVNets VNets created successfully."
}


# Create the network group
createNetworkGroup() {
    az network manager group create \
        --name $networkGroupName \
        --resource-group $resourceGroup \
        --network-manager $networkManagerName
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create network group."
        exit 1
    fi
}

 # Manually add networks to network group
 addNetworksToNetworkGroup() {
    for myVnet in "${my_array[@]}"
    do
        az network manager group static-member create \
            --name $myVnet \
            --network-group $networkGroupName \
            --network-manager $networkManagerName \
            --resource-group $resourceGroup \
            --resource-id "/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/virtualNetworks/$myVnet" 
    done
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add VNet(s) to mesh."
        exit 1
    fi
 }

# Check the provisioning state of the gateway
checkForGatewayDeployment() {
    while true; do
        printf "For proper deployment, the VNET gateway must first be successfully provisioned. This may take a while...\nThis will loop until the gateway is successfully provisioned, then proceed.\n"

        # Get the provisioning state of the gateway
        provisioningState=$(az network vnet-gateway show -g $resourceGroup -n $myVnetGateway --query "provisioningState" -o tsv | tr -d '\r')

        if [ "$provisioningState" == "Succeeded" ]; then
            echo "Gateway deployment is successful."
            break
        elif [ "$provisioningState" == "Updating" ]; then
            echo "Gateway deployment is not successful yet... waiting for 1 minute, then checking again."
            sleep 60
        else
            echo "Error: Gateway deployment is in an unexpected state: $provisioningState"
            exit 1
        fi
    done
    echo "Exiting checkForGatewayDeployment and proceeding to the next step."
}

# Create a connectivity configuration

addConnectConfig() {
    az network manager connect-config create \
        --configuration-name $configName \
        --connectivity-topology $Topology \
        --applies-to-groups "[{\"networkGroupId\": \"/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/networkManagers/$networkManagerName/networkGroups/$networkGroupName\", \"use-hub-gateway\": \"true\", \"groupConnectivity\": \"DirectlyConnected\"}]" \
        --hub "{\"resourceType\": \"Microsoft.Network/virtualNetworks\", \"resourceId\": \"/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/virtualNetworks/$myHubVnet\"}" \
        --network-manager-name $networkManagerName \
        --resource-group $resourceGroup 
        echo "Successfully created connectivity configuration"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create connectivity configuration."
        exit 1
    fi
}

# Confirm successful deployment

checkForConfigDeployment() {
    for myVnet in "${my_array[@]}"
    do
        while true; do
            # Get the provisioning state of the connectivity configuration
            provisioningState=$(az network manager list-effective-connectivity-config \
                --resource-group $resourceGroup \
                --virtual-network-name $myVnet \
                --query "provisioningState" -o tsv | tr -d '\r')
            if [ "$provisioningState" == "Succeeded" ]; then
                echo "Connectivity configuration deployment is successful for $myVnet."
                break
            else
                echo "Error: Connectivity configuration deployment is in an unexpected state: $provisioningState for $myVnet."
                exit 1
            fi
        done
    done
}

# Deploy the connectivity configuration
deployConnectConfig() {
    az network manager post-commit \
        --network-manager-name $networkManagerName \
        --commit-type $commitType \
        --configuration-ids "/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/networkManagers/$networkManagerName/connectivityConfigurations/$configName" \
        --target-locations $myLocation \
        --resource-group $resourceGroup 
        if [ $? -ne 0 ]; then
        echo "Checking to make sure deploments were successful."
        checkForGatewayDeployment
    
    fi
    echo "Successfully deployed connectivity configuration."
}


# Call the functions
getDefaultSubscriptionId
createRG
createNetworkManager
createHubNetwork
createGatewaySubnet
requestIpAddress
createVirtualNetworkGateway
createVNets
createNetworkGroup
addNetworksToNetworkGroup
checkForGatewayDeployment
addConnectConfig
deployConnectConfig
checkForConfigDeployment

# Create Security Admin Config
createSecurityAdminConfig() {
    az network manager security-admin-config create \
        --config-name $mySecurityAdminName \
        --resource-group $resourceGroup \
        --network-manager-name $networkManagerName
}


# Create the security rule collection
createSecurityAdminRuleCollection() {
    az network manager security-admin-config rule-collection create \
        --applies-to-groups network-group-id ="/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/NetworkManager/networkGroups/$networkGroupName" \
        --config-name $mySecurityAdminName \
        --network-manager-name $networkManagerName \
        --resource-group $resourceGroup \
        --rule-collection-name $mySecurtityCollectionName
}


# Create the security rule
createSecurityRule() {
    az network manager security-admin-config rule-collection rule create \
        --access "Deny" \
        --config-name $mySecurityAdminName \
        --direction "Outbound" \
        --network-manager-name $networkManagerName \
        --priority 1 \
        --protocol "Tcp" \
        --resource-group $resourceGroup \
        --rule-collection-name $mySecurtityCollectionName \
        --rule-name $mySecurtiyyRuleName \
        --dest-port-ranges 80 443 \
        --destinations address-prefixes "*"
}
