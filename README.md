# Cloudwarden - Self host your password manager with Vaultwarden

## Description
This is a docker compose configuration to securely self host Vaultwarden Password manager instance localy or on a VPS.
This configuration will NOT expose the password manager to internet it will be only accessible via VPN (WireGuard)

## What you will need
- A VPS, Virtual machine or Bare Metal server running a Linux based OS (Debian, Ubuntu or others)
- Docker and docker compose
- A domain name migrated to Cloudflare
- A [Cloudflare API Key](https://github.com/2nistechworld/cloudwarden#how-to-get-your-cloudflare-api-key).

## Docker containers used
- [wg-easy](https://github.com/wg-easy/wg-easy): VPN using Wireguard to Access the server and the Password Manager.
- [Traefik](https://traefik.io/traefik): Reverse proxy to access Vaultwarden. Manage also the SSL/TLS Certificate using Let's encrypt.
- [AdGuard Home](https://adguard.com/): DNS Server to resolve Vaultwarden URL when connected to the VPN. Can also be used to browse internet and block ads.
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden): The Password Manager we want to acess.

## Installation
- Connect to SSH on the machine you want to install Vaultwarden
- Use a non root user with sudo privileges
- Install docker and docker compose if not installed
    - https://docs.docker.com/engine/install/
    - Add the non root user to the docker group to run docker commands without sudo:

   ```sudo usermod -aG docker $USER```

- Create a network for the containers to communicate.

```docker network create --driver=bridge --subnet=172.19.0.0/16 --gateway=172.19.0.1 my_network```

- Create a password for wg-easy UI (The UI will be exposed on internet during the initial setup, so choose a strong password)
    - Replace "yourSecurePassword" with your desired password in the command below:

  ```docker run -it ghcr.io/wg-easy/wg-easy wgpw yourSecurePassword | cut -d "'" -f2 | sed 's/\$/\$$/g'```

  Save the output hash for later use in the .env file.

- Get the docker compose file

```wget -O docker-compose.yml https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/docker-compose.yml```

- Get the .env file

```wget -O .env https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/example.env```

- Edit the .env file as follow

| NAme                    | Values                          |
|-------------------------|---------------------------------|
| CONTAINERS_DATA         | Folders to store datas          |
| EMAIL_ADDRESS           | Email address for Let's encrypt |
| PUSH_INSTALLATION_ID    | Bitwarden installation ID       |  
| PUSH_INSTALLATION_KEY   | Bitwarden installation key      |  
| VAULTWARDEN_DOMAIN_NAME | ex: vaultwarden.mydomain.com    |  
| CLOUDFLARE_API_KEY      | Your Cloudfalre API Key         |  
| WG_EASY_PASSWORD_HASH   | Password Hash for wg-easy UI    |  
| VPN_DOMAIN_NAME         | ex: vpn.mydomain.com            |

- Start all the services with

```docker compose up -d```

## How to get your Cloudflare API Key
To get you API token go to https://dash.cloudflare.com/profile/api-tokens

- Click Create Token
- choose Edit zone DNS template
- Configure like this with your own domain
<img src="/images/get-cf-api-key.png" style=" width:50% ; align:center " >

- Continue to summary and save your API token

Also please support the developpers of:
- [Traefik](https://traefik.io/traefik)
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [wg-easy](https://github.com/wg-easy/wg-easy)
- [AdGuard Home](https://adguard.com/)