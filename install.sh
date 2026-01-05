#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Cloudwarden Auto-Installer${NC}"
echo "--------------------------------"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root (use sudo).${NC}"
  exit 1
fi

# Function to check and install dependencies
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    # Check for curl and wget
    if ! command -v curl &> /dev/null; then
        echo "Installing curl..."
        apt-get update && apt-get install -y curl
    fi

    if ! command -v wget &> /dev/null; then
        echo "Installing wget..."
        apt-get update && apt-get install -y wget
    fi

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        echo -e "${GREEN}Docker installed successfully.${NC}"
    else
        echo -e "${GREEN}Docker is already installed.${NC}"
    fi

    # Check for Docker Compose (plugin)
    if ! docker compose version &> /dev/null; then
         echo -e "${RED}Docker Compose plugin not found. Please verify your Docker installation.${NC}"
         exit 1
    fi
}

check_dependencies

# Configuration Prompts
echo -e "\n${BLUE}Configuration${NC}"
echo "--------------------------------"

read -p "Enter path for container data (default: /opt/cloudwarden): " CONTAINERS_DATA
CONTAINERS_DATA=${CONTAINERS_DATA:-/opt/cloudwarden}

# Create data directories
mkdir -p "$CONTAINERS_DATA"

read -p "Enter Email Address for Let's Encrypt: " EMAIL_ADDRESS
read -p "Enter your domain name: " DOMAIN_NAME

echo -e "${BLUE}NOTE: You need a Cloudflare API Token for DNS challenges.${NC}"
read -p "Enter Cloudflare API Key: " CLOUDFLARE_API_KEY

echo -e "${BLUE}Set a password for the WireGuard Web UI.${NC}"
read -s -p "Enter WireGuard Password: " WG_PASSWORD
echo ""

# Generate WireGuard Password Hash
echo -e "\n${BLUE}Generating WireGuard password hash...${NC}"
WG_EASY_PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$WG_PASSWORD" | cut -d "'" -f2 | sed 's/\$/\$$/g')

# Optional Bitwarden Push Notifications
read -p "Do you want to configure Bitwarden Push Notifications? (y/n): " CONFIGURE_PUSH
if [[ "$CONFIGURE_PUSH" =~ ^[Yy]$ ]]; then
    read -p "Enter Push Installation ID: " PUSH_INSTALLATION_ID
    read -p "Enter Push Installation Key: " PUSH_INSTALLATION_KEY
else
    PUSH_INSTALLATION_ID=""
    PUSH_INSTALLATION_KEY=""
fi

## Function to create DNS entry
#Create Public DNS record for the VPN using Cloudflare API
create_cloudflare_dns_entries () {
#GET DNS Zone from Cloudflare
#Check if jq is installed
JQ_BIN=$(which jq)
if [ -z "$JQ_BIN" ]
  then
  echo "jq installation to work with APIs"
  apt update
  apt install jq -y 
fi

CLOUDFLARE_DNS_ZONE=$( curl -s --request GET --url https://api.cloudflare.com/client/v4/zones --header 'Content-Type: application/json' --header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' | jq -r '.result[].id')
##Check if the DNS Entrie already exist
CHECK_RECORD_ALREADY_EXIST=$(curl -s --request GET \
--url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_DNS_ZONE/dns_records \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' | grep $VPN_DOMAIN_NAME)

if [ -z "$CHECK_RECORD_ALREADY_EXIST" ]
then
    echo "$line does not exist"
    curl --request POST \
    --url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_DNS_ZONE/dns_records \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' \
    --data '{
    "content": "'$PUBLIC_IP'",
    "name": "'$VPN_DOMAIN_NAME'",
    "proxied": false,
    "type": "A",
    "comment": "A Record for '$VPN_DOMAIN_NAME'"
    }'
else
    echo "$line exist"
fi
}

# Optional Create Public DNS entry for the VPN
PUBLIC_IP=$(curl -s4 ifconfig.me)
read -p "Do you want to create a public DNS entry for vpn.$DOMAIN_NAME? otherwise you will need use your public IP $PUBLIC_IP (y/n): " CREATE_VPN_DNS
if [[ "$CREATE_VPN_DNS" =~ ^[Yy]$ ]]; then
    VPN_DOMAIN_NAME=vpn.$DOMAIN_NAME
    create_cloudflare_dns_entries
else
    VPN_DOMAIN_NAME=$PUBLIC_IP
fi

# Download docker-compose file and .env
wget -O docker-compose.yml https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/docker-compose.yml
wget -O .env https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/example.env

#Edit the .env file
ENV_FILE=.env
#GENERAL
sed -i "s;<CONTAINERS_DATA>;$CONTAINERS_DATA;g" $ENV_FILE
sed -i "s;<DOMAIN_NAME>;$DOMAIN_NAME;g" $ENV_FILE
sed -i "s;<EMAIL_ADDRESS>;$EMAIL_ADDRESS;g" $ENV_FILE
#WG-EASY
sed -i "s;<WG_EASY_PASSWORD_HASH>;$WG_EASY_PASSWORD_HASH;g" $ENV_FILE
sed -i "s;<VPN_DOMAIN_NAME>;$VPN_DOMAIN_NAME;g" $ENV_FILE
#TRAEFIK
sed -i "s;<CLOUDFLARE_API_KEY>;$CLOUDFLARE_API_KEY;g" $ENV_FILE
#VAULTWARDEN
sed -i "s;<PUSH_INSTALLATION_ID>;$PUSH_INSTALLATION_ID;g" $ENV_FILE
sed -i "s;<PUSH_INSTALLATION_KEY>;$PUSH_INSTALLATION_KEY;g" $ENV_FILE

#Create folders
mkdir -p $CONTAINERS_DATA/wireguard
mkdir -p $CONTAINERS_DATA/adguardhome/work
mkdir -p $CONTAINERS_DATA/adguardhome/conf
mkdir -p $CONTAINERS_DATA/traefik/letsencrypt
mkdir -p $CONTAINERS_DATA/vaultwarden/data

##Create adguard rewrite for Vaultwarden
cp AdGuardHome.yaml $CONTAINERS_DATA/adguardhome/conf/AdGuardHome.yaml
sed -i "s;<EMAIL_ADDRESS>;$EMAIL_ADDRESS;g" $CONTAINERS_DATA/adguardhome/conf/AdGuardHome.yaml
sed -i "s;<ADGUARDHOME_PASSWORD_HASH>;$ADGUARDHOME_PASSWORD_HASH;g" $CONTAINERS_DATA/adguardhome/conf/AdGuardHome.yaml
sed -i "s;<DOMAIN_NAME>;$DOMAIN_NAME;g" $CONTAINERS_DATA/adguardhome/conf/AdGuardHome.yaml

# Create Docker Network
NETWORK_NAME="my_network"
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    echo -e "\n${BLUE}Creating docker network '$NETWORK_NAME'...${NC}"
    docker network create --driver=bridge --subnet=172.19.0.0/16 --gateway=172.19.0.1 "$NETWORK_NAME"
    echo -e "${GREEN}Network created.${NC}"
else
    echo -e "${GREEN}Network '$NETWORK_NAME' already exists.${NC}"
fi

# Start Services
echo -e "\n${BLUE}Starting services...${NC}"
docker compose up -d

echo -e "\n${GREEN}Installation completed!${NC}"
echo "WireGuard UI: http://$VPN_DOMAIN_NAME (Check port mapping if behind NAT/Firewall)"
echo "Vaultwarden: https://$VAULTWARDEN_DOMAIN_NAME"
