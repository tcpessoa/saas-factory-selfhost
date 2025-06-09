#!/bin/bash

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ .env file not found"
    exit 1
fi

# Get server IP from Terraform
SERVER_IP=$(cd infrastructure/terraform && terraform output -raw server_ip 2>/dev/null)
if [ -z "$SERVER_IP" ]; then
    echo "❌ Could not get server IP"
    exit 1
fi

echo "🔒 Configuring security for server: $SERVER_IP"

# Create the security configuration script
cat > /tmp/server-security.sh << 'EOF'
#!/bin/bash
set -e

echo "🔧 Starting security configuration..."

# Update system
echo "📦 Updating system packages..."
apt-get update
apt-get upgrade -y

# Configure SSH security
echo "🔐 Configuring SSH security..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# SSH hardening configuration - modify existing config instead of replacing
echo "🔧 Hardening SSH configuration..."

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Apply security settings by modifying existing config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/PermitEmptyPasswords yes/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/#X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config

# Add additional security settings if they don't exist
grep -q "ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
grep -q "ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config
grep -q "MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
grep -q "MaxSessions" /etc/ssh/sshd_config || echo "MaxSessions 2" >> /etc/ssh/sshd_config

echo "📝 SSH security settings applied:"
echo "  ✅ Password authentication disabled"
echo "  ✅ Public key authentication enabled"
echo "  ✅ Empty passwords disabled"
echo "  ✅ X11 forwarding disabled"
echo "  ✅ Connection limits configured"

# Create SSH privilege separation directory if it doesn't exist
echo "📁 Ensuring SSH privilege separation directory exists..."
mkdir -p /run/sshd
chown root:root /run/sshd
chmod 755 /run/sshd

# Test SSH config and restart
echo "🔍 Testing SSH configuration..."
sshd -t

# Detect SSH service name (different distributions use different names)
echo "🔄 Detecting SSH service name..."
if systemctl is-active --quiet sshd; then
    SSH_SERVICE="sshd"
elif systemctl is-active --quiet ssh; then
    SSH_SERVICE="ssh"
elif systemctl is-enabled --quiet sshd 2>/dev/null; then
    SSH_SERVICE="sshd"
elif systemctl is-enabled --quiet ssh 2>/dev/null; then
    SSH_SERVICE="ssh"
else
    echo "⚠️  Could not detect SSH service name, trying common names..."
    if systemctl list-unit-files | grep -q "^sshd.service"; then
        SSH_SERVICE="sshd"
    elif systemctl list-unit-files | grep -q "^ssh.service"; then
        SSH_SERVICE="ssh"
    else
        echo "❌ Could not find SSH service"
        exit 1
    fi
fi

echo "🔄 Restarting SSH service ($SSH_SERVICE)..."
systemctl restart $SSH_SERVICE

# Configure automatic security updates
echo "🛡️ Configuring automatic security updates..."
apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UPGRADESEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPGRADESEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF

# Install fail2ban for additional protection
echo "🚫 Installing and configuring fail2ban..."
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'FAIL2BANEOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
FAIL2BANEOF

systemctl enable fail2ban
systemctl start fail2ban

# Note: No additional firewall needed - Hetzner firewall + Cloudflare tunnel handles everything
echo "🔥 Firewall: Using Hetzner Cloud firewall (SSH only) + Cloudflare tunnel"

# Create a basic monitoring script
echo "📊 Setting up basic monitoring..."
cat > /opt/health-check.sh << 'HEALTHEOF'
#!/bin/bash
# Basic health check script

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    echo "$(date): WARNING - Disk usage is at ${DISK_USAGE}%" >> /var/log/health-check.log
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [ $MEM_USAGE -gt 90 ]; then
    echo "$(date): WARNING - Memory usage is at ${MEM_USAGE}%" >> /var/log/health-check.log
fi

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "$(date): ERROR - Docker is not running" >> /var/log/health-check.log
fi
HEALTHEOF

chmod +x /opt/health-check.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "*/15 * * * * /opt/health-check.sh") | crontab -

# Ensure SSH privilege separation directory persists across reboots
echo "🔧 Making SSH directory persistent across reboots..."
cat > /etc/systemd/system/ssh-prepare.service << 'SSHSERVICEEOF'
[Unit]
Description=Create SSH privilege separation directory
Before=ssh.service sshd.service
ConditionPathExists=/run

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /run/sshd
ExecStart=/bin/chown root:root /run/sshd
ExecStart=/bin/chmod 755 /run/sshd
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SSHSERVICEEOF

systemctl enable ssh-prepare.service
systemctl start ssh-prepare.service

echo "✅ Security configuration completed!"
echo ""
echo "🔒 Security measures applied:"
echo "  ✅ SSH hardened (key-only authentication)"
echo "  ✅ SSH privilege separation directory configured"
echo "  ✅ Automatic security updates enabled"
echo "  ✅ Fail2ban installed and configured"
echo "  ✅ Hetzner firewall configured (SSH only)"
echo "  ✅ Basic monitoring script installed"
echo ""
echo "⚠️  IMPORTANT: Password authentication is now DISABLED"
echo "   Make sure your SSH key is working before closing this session!"

EOF

# Copy and execute the security script on the server
echo "📤 Copying security script to server..."
scp /tmp/server-security.sh root@$SERVER_IP:/tmp/

echo "🔧 Executing security configuration..."
ssh root@$SERVER_IP 'chmod +x /tmp/server-security.sh && /tmp/server-security.sh && rm /tmp/server-security.sh'

# Clean up local temp file
rm /tmp/server-security.sh

echo "✅ Security configuration completed successfully!"
echo ""
echo "🎯 Next steps:"
echo "  1. Run 'make tunnel' to install Cloudflare tunnel"
echo "  2. Run 'make core' to deploy core services"
