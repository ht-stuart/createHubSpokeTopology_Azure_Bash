#!/bin/bash


# Function to validate the user's selected Azure location
locationChoice() {
    # Prompt the user for their desired Azure location
    read -p "Would you like to use the default location (East US) or select a different location? (default/different): " choice
    if [ "$choice" == "default" ]; then
        myLocation="eastus"
        echo "Using default location: $myLocation"
        exit
    elif [ "$choice" == "different" ]; then
        locationSelector
    else
        echo "Invalid choice. Please enter 'default' or 'different'."
        locationChoice
    fi
}

locationSelector() {
    # Prompt the user for their desired Azure location}
    printf "**Some locations are not available in all regions.\n"
    printf "**Some locations have access to limited resources:\n"
    printf "**Please look into this before switching locations:\n"
    read -p "What is your desired cloud location for deployment: " location

    # Convert the input to lowercase for consistency
    myLocation=$(echo "$location" | tr '[:upper:]' '[:lower:]')

    # Check if the location is valid
    if az account list-locations --query "[?name=='$myLocation']" -o tsv | grep -q "$myLocation"; then
        echo "Your selected location '$myLocation' is valid....proceeding..."
        exit
    else
        echo "Invalid location: '$myLocation'. Please select a valid Azure region."
        echo "Here is a list of valid Azure regions:"
        az account list-locations --query "[].name" -o table
        locationSelector
        return
    fi
}

locationChoice
locationSelector