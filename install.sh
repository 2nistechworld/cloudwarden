#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Cloudwarden Auto-Installer${NC}"
echo "--------------------------------"

#Get current user
CURRENT_USER=$(logname)
# Fix permissiom
if [[ "$CURRENT_USER" != "root" ]]; then
    CURRENT_USER_GRP=$(sudo -u $CURRENT_USER id -gn)
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root (use sudo).${NC}"
  exit 1
fi

# Updating the packages
echo "Updating the packages"
apt update && apt upgrade

# Function to check and install dependencies
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    # Check for curl and wget
    if ! command -v curl &> /dev/null; then
        echo "Installing curl..."
        apt install curl -y
    fi

    if ! command -v wget &> /dev/null; then
        echo "Installing wget..."
        apt install wget -y
    fi

    DOCKER_BIN=$(which docker)
        if [ -z "$DOCKER_BIN" ]
        then
            echo -e "${BLUE}Docker not found. Installing Docker...${NC}"
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
            echo -e "${GREEN}Docker installed successfully.${NC}"
        else
            echo -e "${GREEN}Docker is already installed.${NC}"
        fi
}

check_dependencies

# Download docker-compose file and .env
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/example.env -o .env
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/AdGuardHome.yaml -o AdGuardHome.yaml

# Configuration Prompts
echo -e "\n${BLUE}Configuration${NC}"
echo "--------------------------------"

read -p "Enter path for container data (default: /opt/cloudwarden): " CONTAINERS_DATA
CONTAINERS_DATA=${CONTAINERS_DATA:-/opt/cloudwarden}

# Create data directories
mkdir -p "$CONTAINERS_DATA"
if [[ "$CURRENT_USER" != "root" ]]; then
    chown $CURRENT_USER:$CURRENT_USER_GRP -R "$CONTAINERS_DATA"
fi


read -p "Enter Email Address for Let's Encrypt: " EMAIL_ADDRESS
read -p "Enter your domain name: " DOMAIN_NAME

while true
    do
        echo -e "${BLUE}NOTE: You need a Cloudflare API Token for DNS challenges.${NC}"
        echo -e "${BLUE}https://github.com/2nistechworld/cloudwarden#how-to-get-your-cloudflare-api-key${NC}"
        read -p "Enter Cloudflare API Key: " CLOUDFLARE_API_KEY
        CHECK_CLOUDFLARE_API_KEY=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" --header "Authorization: Bearer $CLOUDFLARE_API_KEY" | grep "This API Token is valid and active")
            if [ -z "$CHECK_CLOUDFLARE_API_KEY" ]; then
                echo -e "${RED}CloudFlare API Key Not valid, try again${NC}"
            else
                echo -e "${GREEN}CloudFlare API Key valid${NC}"
                break
            fi
    done
echo -e "${BLUE}Bitwarden push notification configuration${NC}"
echo -e "${BLUE}To enable push go to https://bitwarden.com/host/ to get your ID and Key${NC}"
read -p "Enter Push Installation ID: " PUSH_INSTALLATION_ID
read -p "Enter Push Installation Key: " PUSH_INSTALLATION_KEY
read -p "Did you choose the bitwarden.eu (European Union) Region? (y/n): " EU_REGION
if [[ "$EU_REGION" =~ ^[Yy]$ ]]; then
    sed -i 's/#- PUSH_RELAY_URI/- PUSH_RELAY_URI/' docker-compose.yml
    sed -i 's/#- PUSH_IDENTITY_URI/- PUSH_IDENTITY_URI/' docker-compose.yml
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

#Edit the .env file
ENV_FILE=.env
#GENERAL
sed -i "s;<CONTAINERS_DATA>;$CONTAINERS_DATA;g" $ENV_FILE
sed -i "s;<DOMAIN_NAME>;$DOMAIN_NAME;g" $ENV_FILE
sed -i "s;<EMAIL_ADDRESS>;$EMAIL_ADDRESS;g" $ENV_FILE
#WG-EASY
sed -i "s;<VPN_DOMAIN_NAME>;$VPN_DOMAIN_NAME;g" $ENV_FILE
#TRAEFIK
sed -i "s;<CLOUDFLARE_API_KEY>;$CLOUDFLARE_API_KEY;g" $ENV_FILE
#VAULTWARDEN
sed -i "s;<PUSH_INSTALLATION_ID>;$PUSH_INSTALLATION_ID;g" $ENV_FILE
sed -i "s;<PUSH_INSTALLATION_KEY>;$PUSH_INSTALLATION_KEY;g" $ENV_FILE

#Create folders
mkdir -p "$CONTAINERS_DATA/wg-easy"
mkdir -p "$CONTAINERS_DATA/adguardhome/work"
mkdir -p "$CONTAINERS_DATA/adguardhome/conf"
mkdir -p "$CONTAINERS_DATA/traefik/letsencrypt"
mkdir -p "$CONTAINERS_DATA/vaultwarden/data"

## Create passwords
## AdGuardHome
ADGUARDHOME_PASSWORD=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 35 ; echo '')
docker pull httpd:2.4
ADGUARDHOME_PASSWORD_HASH=$(docker run httpd:2.4 htpasswd -B -n -b $EMAIL_ADDRESS $ADGUARDHOME_PASSWORD | cut -d ":" -f2)
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

# Fix permissiom
if [[ "$CURRENT_USER" != "root" ]]; then
    usermod -aG docker $CURRENT_USER
    chown $CURRENT_USER:$CURRENT_USER_GRP docker-compose.yml
    chown $CURRENT_USER:$CURRENT_USER_GRP .env
    chown -R $CURRENT_USER:$CURRENT_USER_GRP $CONTAINERS_DATA
fi

# Start Services
echo -e "\n${BLUE}Starting services...${NC}"
docker compose up -d

echo -e "\n${GREEN}Installation completed!${NC}"
echo -e "\n${BLUE}Next steps:${NC}"
echo -e "To connect to the VPN remotetely you need to ${RED}Open the port 51820/udp in your firewall.${NC}"
echo -e "${GREEN}$VPN_DOMAIN_NAME will be uses to connect to the VPN remotely.${NC}"
echo -e "\n${BLUE}Access WG_EASY UI :${NC}"
echo "If you ran this script on a machine running in your local network,"
echo "you can access the WG_EASY UI using http://your_local_ip:51821"
echo "Or"
echo "If you ran this script on a cloud VPS, you can either temporary open the port 51821/tcp "
echo "to acess WG_EASY UI using http://$PUBLIC_IP:51821 or create a SSH tunnel with the command:"
echo -e "${BLUE}ssh -L 51821:172.19.0.2:51821 $CURRENT_USER@$PUBLIC_IP${NC} in your terminal"
echo "Once the tunnel ceated, open a browser and access http://localhost:51821"
echo -e "\n${BLUE}Informations :${NC}"
echo -e "\n${GREEN}Once connected to the VPN you can access :${NC}"
echo "WG-EASY UI: https://vpnui.$DOMAIN_NAME"
echo "Vaultwarden: https://vault.$DOMAIN_NAME"
echo "AdGuardHome: http://172.19.0.3"
echo "Login: $EMAIL_ADDRESS"
echo "Password: $ADGUARDHOME_PASSWORD"

#cleanup
rm -f AdGuardHome.yaml 