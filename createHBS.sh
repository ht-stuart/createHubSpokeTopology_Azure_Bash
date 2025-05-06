#!/bin/bash 

#This script will create a hub and spoke network topology with your desired number of Vnets /n

#!/bin/bash

set -x

# Update the Azure CLI extension for virtual network manager
az extension update --name virtual-network-manager

# Display the purpose of the script
printf "This script will create a Hub & Spoke network topology with your desired number of Vnets (spokes) + a Vnet gateway.\n"
printf "+ A network manager + network group for central administration (location: East US).\n"
printf "+ A security configuration blocking traffic on ports 80 and 443.\n"
printf "This script will use your default subscription for scope and access.\n"


# Function to get the default subscription ID
getDefaultSubscriptionId() {
    defaultSubscriptionId=$(az account list --query "[?isDefault].id" -o tsv | tr -d '\r')
    echo "Default subscription ID is: $defaultSubscriptionId"
    az account list --query "[?id=='$defaultSubscriptionId']" -o jsonc
    read -p "Is this the correct subscription? (y/n): " choice
    if [ "$choice" == "y" ]; then
        echo "Proceeding with subscription ID: $defaultSubscriptionId"
    elif [ "$choice" == "n" ]; then
    read -p "Please enter the correct subscription ID: " defaultSubscriptionId
        while true; do
            if az account list --query "[?id=='$defaultSubscriptionId']" -o tsv | grep -q "$defaultSubscriptionId"; then
                echo "Valid subscription ID: $defaultSubscriptionId"
                break
            else
                echo "Invalid subscription ID. Please enter a valid subscription ID."
                read -p "Please enter the correct subscription ID: " defaultSubscriptionId
            fi
        done
        echo "Using subscription ID: $defaultSubscriptionId"

        return
    else
        echo "Invalid choice. Please enter 'y' or 'n'."
        getDefaultSubscriptionId
    fi
}

# Function to validate the user's selected Azure location
locationChoice() {
    # Prompt the user for their desired Azure location
    read -p "Would you like to use the default location (East US) or select a different location? (default/different): " choice
    if [ "$choice" == "default" ]; then
        myLocation="eastus"
        echo "Using default location: $myLocation"
        return
    elif [ "$choice" == "different" ]; then
        locationSelector
    else
        echo "Invalid choice. Please enter 'default' or 'different'."
        locationChoice
    fi
}

# Function to prompt the user for a different location
locationSelector() {
    while true; do
        # Display information about location restrictions
        printf "**Some locations are not available in all regions.\n"
        printf "**Some locations have access to limited resources:\n"
        printf "**Please look into this before switching locations.\n"

        # Prompt the user for their desired Azure location
        read -p "What is your desired cloud location for deployment: " location

        # Convert the input to lowercase for consistency
        myLocation=$(echo "$location" | tr '[:upper:]' '[:lower:]')

        # Check if the location is valid
        if az account list-locations --query "[?name=='$myLocation']" -o tsv | grep -q "$myLocation"; then
            echo "Your selected location '$myLocation' is valid....proceeding..."
            break
        else
            echo "Invalid location: '$myLocation'. Please select a valid Azure region."
            echo "Here is a list of valid Azure regions:"
            az account list-locations --query "[].name" -o table
        fi
    done
}

# Function to prompt the user for the number of spokes
getSpokes() {
    read -p "How many VNets(spokes) do you want to create? " numVNets
    if ! [[ "$numVNets" =~ ^[2-9]+$ ]]; then
        echo "VNet quantity must be a number > 2 and valid"
        getSpokes
    else 
    return
    fi
}

# Main Variables
networkManagerName="myNetworkManager"
resourceGroup="networkManagerRG"

#Variables for tagging
tagKey="NetworkType"
tagValue="Production"

networkGroupName="myNetworkGroup"
# Policy Names
vNetPolicyName="vNetPolicy"
azPolicyName="vNetPolicyAssignment"

# Connectivity Configuration Variables
configName="HubSpokeConfig"
Topology="HubandSpoke"
commitType="Connectivity"

# Virtual Network and Gateway Names
myHubVnet="vnetHUB"
myVnet="vnet00"
myVnetGateway="vnetGateway"
myVnetGatewayIP="vnetGatewaypip" 

# Security Configuration Variables
mySecurityAdminName="mySecurityAdminConfig"
mySecurtityCollectionName="mySecurityRuleCollection"
mySecurtiyyRuleName="mySecurityRule"
securityCommitType="SecurityAdmin"

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
        echo "Error: Failed to add VNet(s) to network group."
        exit 1
    fi
 }

# Check the provisioning state of the gateway
checkForGatewayDeployment() {
    while true; do
        printf "For proper deployment, the VNET gateway must first be successfully provisioned. This may take a while...\n"
        printf "This will loop until the gateway is successfully provisioned, then proceed.\n"

        # Get the provisioning state of the gateway
        provisioningState=$(az network vnet-gateway show -g $resourceGroup -n $myVnetGateway --query "provisioningState" -o tsv | tr -d '\r')
        if [ "$provisioningState" == "Succeeded" ]; then
            echo "Gateway deployment is successful."
            break
        elif [ "$provisioningState" == "Updating" ]; then
            echo "Gateway deployment is not successful yet... waiting for 30 seconds, then checking again."
            sleep 30
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

# Deploy the connectivity configuration
deployConnectConfig() {
    az network manager post-commit \
        --network-manager-name $networkManagerName \
        --commit-type $commitType \
        --configuration-ids "/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/networkManagers/$networkManagerName/connectivityConfigurations/$configName" \
        --target-locations $myLocation \
        --resource-group $resourceGroup 
        if [ $? -ne 0 ]; then
        echo "Checking to make sure deployments were successful."
        for vnet in "${my_array[@]}"; do
        provisioningState=$(az network manager list-effective-connectivity-config \
            --resource-group $resourceGroup \
            --virtual-network-name $vnet \
            --query "value[0].provisioningState" -o tsv | tr -d '\r')
        if [ "$provisioningState" == "Succeeded" ]; then
            echo "Provisioning state for $vnet is $provisioningState"
        else
            echo "Provisioning state for $vnet is not Succeeded"
            exit
        fi
    done 
    else
        echo "Connectivity configuration deployed successfully."
    fi 
}

# Security Admin Configuration

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
        --applies-to-groups network-group-id="/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/networkManagers/$networkManagerName/networkGroups/$networkGroupName" \
        --configuration-name $mySecurityAdminName \
        --network-manager-name $networkManagerName \
        --resource-group $resourceGroup \
        --rule-collection-name $mySecurtityCollectionName
}

# Create the security rule
createSecurityRule() {
    az network manager security-admin-config rule-collection rule create \
        --access "Deny" \
        --configuration-name $mySecurityAdminName \
        --direction "Outbound" \
        --network-manager-name $networkManagerName \
        --priority 1 \
        --protocol "Tcp" \
        --resource-group $resourceGroup \
        --rule-collection-name $mySecurtityCollectionName \
        --rule-name $mySecurtiyyRuleName \
        --dest-port-ranges 80 443 \
        --destinations address-prefix="*" address-prefix-type="IPPrefix" 
}

# Deploy the security configuration
deploySecurityConfig() {
    az network manager post-commit \
        --network-manager-name $networkManagerName \
        --commit-type $securityCommitType \
        --configuration-ids "/subscriptions/$defaultSubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/networkManagers/$networkManagerName/securityAdminConfigurations/$mySecurityAdminName" \
        --target-locations $myLocation \
        --resource-group $resourceGroup 

    if [ $? -eq 0 ]; then
        echo "Security configuration deployed successfully."
    else
        echo "Error: Failed to deploy security configuration. Verifying security rules on VNets..."
        for vnet in "${my_array[@]}"; do
            az network manager list-effective-security-admin-rule \
                --resource-group $resourceGroup \
                --virtual-network-name $vnet \
                --output json > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "Error: Security rule not found on $vnet."
                exit 1
            fi
            echo "Security rule found on $vnet."
        done
        echo "All security rules verified on all VNets."
    fi
}

# Call the functions
getDefaultSubscriptionId
locationChoice
getSpokes
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
createSecurityAdminConfig
createSecurityAdminRuleCollection
createSecurityRule
deploySecurityConfig

echo "All configurations and deployments completed successfully."


