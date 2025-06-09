#!/bin/bash

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ .env file not found"
    exit 1
fi

# Get server IP and tunnel token from Terraform
SERVER_IP=$(cd infrastructure/terraform && terraform output -raw server_ip 2>/dev/null)
TUNNEL_TOKEN=$(cd infrastructure/terraform && terraform output -raw tunnel_token 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
    echo "❌ Could not get server IP"
    exit 1
fi

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "❌ Could not get tunnel token"
    exit 1
fi

echo "🌐 Installing Cloudflare tunnel on server: $SERVER_IP"

# Create the tunnel installation script
cat > /tmp/install-tunnel.sh << 'EOF'
#!/bin/bash
set -e

TUNNEL_TOKEN="$1"

echo "🔍 Detecting architecture..."
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

case $ARCH in
    x86_64) DEB_ARCH='amd64' ;;
    aarch64) DEB_ARCH='arm64' ;;
    armv7l) DEB_ARCH='armhf' ;;
    *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;;
esac

# Install cloudflared if not already installed
if ! command -v cloudflared &> /dev/null; then
    echo "📥 Downloading cloudflared for $DEB_ARCH..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$DEB_ARCH.deb
    dpkg -i cloudflared.deb
    rm cloudflared.deb
    echo "✅ Cloudflared installed"
else
    echo "ℹ️  Cloudflared already installed"
fi

echo "🔑 Installing tunnel service..."
cloudflared service install $TUNNEL_TOKEN

echo "🔧 Configuring systemd service..."
systemctl enable cloudflared
systemctl start cloudflared

# Wait a moment for service to start
sleep 5

echo "🔍 Checking tunnel status..."
if systemctl is-active --quiet cloudflared; then
    echo "✅ Tunnel service is running"
else
    echo "❌ Tunnel service failed to start"
    echo "📋 Service logs:"
    journalctl -u cloudflared -n 10 --no-pager
    exit 1
fi

echo "✅ Cloudflare tunnel installed and running successfully!"

EOF

# Copy and execute the tunnel script on the server
echo "📤 Copying tunnel installation script to server..."
scp /tmp/install-tunnel.sh root@$SERVER_IP:/tmp/

echo "🔧 Installing tunnel on server..."
ssh root@$SERVER_IP "chmod +x /tmp/install-tunnel.sh && /tmp/install-tunnel.sh '$TUNNEL_TOKEN' && rm /tmp/install-tunnel.sh"

# Clean up local temp file
rm /tmp/install-tunnel.sh

echo "✅ Tunnel installation completed!"
echo ""
echo "🌐 Your tunnel is now active and routing traffic from:"
echo "  • $MAIN_DOMAIN"
echo "  • *.$MAIN_DOMAIN"
echo ""
echo "🔍 To check tunnel status: ssh root@$SERVER_IP 'systemctl status cloudflared'"
echo "📋 To view tunnel logs: ssh root@$SERVER_IP 'journalctl -u cloudflared -f'"
echo ""
echo "🎯 Next step: Run 'make core' to deploy core services"
