# Cloudwarden - Self host your password manager with Vaultwarden

## Description
This is a docker compose configuration to securely self host a Vaultwarden Password Manager instance locally or on a VPS.
This configuration will NOT expose the password manager to the internet; it will be only accessible via VPN (WireGuard).

<img src="/images/Diagram.drawio.png" style="align:center">

## Prerequisites
- A VPS, Virtual Machine, or Bare Metal server running a Linux-based OS (Debian, Ubuntu, etc.)
- Docker and Docker Compose installed
- A domain name managed by Cloudflare
- A [Cloudflare API Key](https://github.com/2nistechworld/cloudwarden#how-to-get-your-cloudflare-api-key)
- A [Bitwarden installation ID and key](https://github.com/2nistechworld/cloudwarden#how-to-get-your-bitwarden-installation-id-and-key)

## Docker Containers
- [wg-easy](https://github.com/wg-easy/wg-easy): VPN using WireGuard to access the server and the Password Manager.
    - **Modern Web UI**: Complete rewrite with a sleek, responsive design.
    - **Traffic Statistics**: Real-time Rx/Tx charts for connected clients.
    - **2FA Support**: Enhanced security with Two-Factor Authentication (TOTP).
    - **Client Management**: Easy QR code scanning and configuration downloading.
    - **Multi-language Support**: Interface available in multiple languages.
- [Traefik](https://traefik.io/traefik): Reverse proxy to access Vaultwarden. Manages SSL/TLS certificates using Let's Encrypt.
    - **Automatic SSL/TLS**: Auto-provisioning and renewal of certificates via Let's Encrypt.
    - **Web Dashboard**: Monitoring and configuration visualization.
    - **Middleware Support**: Powerful request modification handling.
    - **Load Balancing**: Efficient traffic distribution.
- [AdGuard Home](https://adguard.com/): DNS Server to resolve Vaultwarden URL when connected to the VPN. Can also be used to block ads.
    - **Network-wide Protection**: Blocks ads and trackers for all devices.
    - **Parental Controls**: Enforce safe search and block adult content.
    - **Encrypted DNS**: Supports DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT).
    - **DNS Rewrite**: Custom DNS rules to redirect specific domains (e.g., for local services).
    - **DHCP Server**: Built-in DHCP handling for your network.
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden): The Password Manager.
    - **Full Compatibility**: Works with official Bitwarden apps and extensions.
    - **Advanced Storage**: Store TOTP seeds, Passkeys, and SSH Keys.
    - **2FA/MFA**: Supports Authenticator apps, YubiKey, and FIDO2 WebAuthn.
    - **Organization Support**: Share passwords securely with groups and families.
    - **Lightweight**: Optimized for low-resource environments (unlike the official server).

## Installation Methods

### Option 1: Auto-Installer Script (Recommended)
The `install.sh` script is designed to automate the entire deployment process.

**How it works:**
1.  **System Prep**: Updates system packages and checks for/installs dependencies (Docker, curl, wget, jq).
2.  **Environment Setup**: Creates the required Docker network (`my_network`) and creates the directory structure for persistent data.
3.  **File Retrieval**: Downloads the latest `docker-compose.yml`, `.env`, and `AdGuardHome.yaml` configuration files.
4.  **Configuration**: Prompts you for your domain, email, and API keys, validates your Cloudflare API key, and updates the `.env` file automatically.
5.  **Security**: Generates secure passwords/hashes for AdGuard Home and configures them.
6.  **DNS**: Optionally creates the DNS `A` record for your VPN subdomain using the Cloudflare API.

**Usage:**
Run the script as root (or with sudo):
```bash
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/install.sh -o install.sh
(sudo) bash install.sh
```

### Option 2: Manual Installation
If you prefer not to use the script, follow these steps to configure the environment manually.

#### 1. Install Docker (as root or using sudo)
```bash
sudo curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

#### 2. Network Setup
Create the specific docker network required for the containers:
```bash
docker network create --driver=bridge --subnet=172.19.0.0/16 --gateway=172.19.0.1 my_network
```

#### 3. Create Directory Structure
Create the folders where your data will be stored. Replace `/opt/cloudwarden` with your preferred path.
```bash
export DATA_PATH="/opt/cloudwarden"
mkdir -p $DATA_PATH
mkdir -p $DATA_PATH/wg-easy
mkdir -p $DATA_PATH/adguardhome/work
mkdir -p $DATA_PATH/adguardhome/conf
mkdir -p $DATA_PATH/traefik/letsencrypt
mkdir -p $DATA_PATH/vaultwarden/data
```

#### 4. Download Files
Download the configuration files:
```bash
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/example.env -o .env
curl -fsSL https://raw.githubusercontent.com/2nistechworld/cloudwarden/refs/heads/main/AdGuardHome.yaml -o AdGuardHome.yaml
```

#### 5. Configure AdGuard Home
Copy the default configuration to your data directory:
```bash
cp AdGuardHome.yaml $DATA_PATH/adguardhome/conf/
```

You must generate an `htpasswd` hash for the AdGuard Home admin user.
*Using Docker to generate the hash (replace `yourpassword`):*
```bash
docker pull httpd:2.4
docker run --rm httpd:2.4 htpasswd -B -n -b admin yourpassword
```
Copy the output hash (everything after `admin:`).

Edit `$DATA_PATH/adguardhome/conf/AdGuardHome.yaml`:
- Replace `<ADGUARDHOME_PASSWORD_HASH>` with the hash you generated.
- Replace `<EMAIL_ADDRESS>` with your email address.
- Replace `<DOMAIN_NAME>` with your domain name.

#### 6. Configure `.env` File
Edit the `.env` file and fill in the following values:

| Name                    | Description                                        |
|-------------------------|----------------------------------------------------|
| CONTAINERS_DATA         | Path to data folders (e.g., `/opt/cloudwarden`)    |
| EMAIL_ADDRESS           | Email address for Let's Encrypt notifications      |
| VPN_DOMAIN_NAME         | External domain for VPN (e.g., `vpn.example.com`). |
| VPNUI_DOMAIN_NAME       | Domain for WG-Easy UI (e.g., `wg.example.com`)     |
| WG_EASY_INIT_PASSWORD   | Password for WG-Easy UI (e.g., `yourpassword`)     |
| CLOUDFLARE_API_KEY      | Your Cloudflare API Token                          |
| PUSH_INSTALLATION_ID    | Bitwarden installation ID (from bitwarden.com)     |
| PUSH_INSTALLATION_KEY   | Bitwarden installation key (from bitwarden.com)    |
| VAULTWARDEN_DOMAIN_NAME | Domain for Vaultwarden (e.g., `vault.example.com`) |

**Notes:** 
- `EMAIL_ADDRESS` will be used as login for AdGuardHome and wg-easy UI.
- `WG_EASY_INIT_PASSWORD` is the password for the WG-Easy UI, it will be used only once to initialize the WG-Easy container. you can put the value a null once the container is initialized.
- For Vaultwarden, if you are in the EU region, uncomment the `PUSH_RELAY_URI` and `PUSH_IDENTITY_URI` lines in `docker-compose.yml`.

#### 7. Start Services
Once configured, start the stack:
```bash
docker compose up -d
```

### Next Steps & Access Information

Once the installation is complete:
1.  **Firewall**: You must open port **51820/udp** in your firewall to allow VPN connections.
2.  **VPN Connection**: Use `vpn.<your_domain>` or the server public IP to connect remotely.

**Accessing WG-EASY UI (First Time):**
-   **Local Network**: `http://<your_local_ip>:51821`
-   **Cloud VPS**:
    -   Create an SSH tunnel:
        ```bash
        ssh -L 51821:172.19.0.2:51821 <user>@<public_ip>
        ```
    -   Then access: `http://localhost:51821`
    - Or you can temporary open port 51821/tcp in your firewall.

**Accessing Services:**
Once connected to the VPN, you can access your services at:
-   **WG-EASY UI**: `https://vpnui.<your_domain>`
-   **Vaultwarden**: `https://vault.<your_domain>`
-   **AdGuard Home**: `http://172.19.0.3`
    -   *Login*: Your email address
    -   *Password*: The password you generated in step 5 (or the script output)

## How to get your Cloudflare API Key
To get you API token go to https://dash.cloudflare.com/profile/api-tokens

- Click **Create Token**
- Choose **Edit zone DNS template**
- Configure like this with your own domain:
<img src="/images/get-cf-api-key.png" style="width:50%; align:center">

- Continue to summary and save your API token.

## How to get your Bitwarden installation ID and key
Go to https://bitwarden.com/host/ and follow the instructions.
---
**Supported Projects:**
- [Traefik](https://traefik.io/traefik)
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [wg-easy](https://github.com/wg-easy/wg-easy)
- [AdGuard Home](https://adguard.com/)