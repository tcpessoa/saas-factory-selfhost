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

echo "📦 Deploying core services to server: $SERVER_IP"

# Create the deployment script that will run on the server
cat > /tmp/server-deploy-core.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Deploying SaaS Factory Core Services"
echo "======================================="

cd /opt/saas-factory

# Create environment file
echo "📝 Creating environment file..."
cat > .env << ENVEOF
MAIN_DOMAIN=${MAIN_DOMAIN}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
ENVEOF

echo "🌐 Creating Docker networks..."
# Create networks if they don't exist
docker network create saas-factory-traefik-net || true
docker network create saas-factory-database-net || true
docker network create saas-factory-monitoring-net || true

echo "🚛 Starting Traefik (reverse proxy)..."
cd core/traefik
docker-compose up -d
sleep 5

echo "🗄️  Starting Database (PostgreSQL)..."
cd ../database
chmod +x init-scripts/01-init-multiple-databases.sh
docker-compose up -d
sleep 10

echo "📊 Starting Monitoring (Dozzle + Uptime Kuma)..."
cd ../monitoring
docker-compose up -d
sleep 5

echo "🔍 Checking service status..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "✅ Core services deployed successfully!"
echo ""
echo "🌐 Your services are available at:"
echo "   Traefik Dashboard: https://traefik.${MAIN_DOMAIN}"
echo "   Logs Viewer:       https://logs.${MAIN_DOMAIN}"
echo "   Status Monitor:    https://status.${MAIN_DOMAIN}"
echo ""
echo "🔐 Default credentials:"
echo "   Traefik Dashboard: admin / admin"
echo ""
echo "📋 Database connection (from apps):"
echo "   Host: saas-factory-postgres"
echo "   Port: 5432"
echo "   Password: ${POSTGRES_PASSWORD}"
echo ""
echo "💡 Tip: Use 'docker logs <container-name>' to view logs"
echo "    or visit https://logs.${MAIN_DOMAIN} for web-based log viewer"

EOF

# Create directory structure
echo "📁 creating saas factory directory structure..."
ssh root@$SERVER_IP 'mkdir -p /opt/saas-factory/{core,apps,data,scripts}'
ssh root@$SERVER_IP 'mkdir -p /opt/saas-factory/core/{database,monitoring,traefik}'
ssh root@$SERVER_IP 'mkdir -p /opt/saas-factory/core/database/init-scripts'

# Copy all necessary files to the server
echo "📂 Copying core service files to server..."

# Copy Docker Compose files
echo "   📄 Copying Docker Compose configurations..."
scp core/database/docker-compose.yml root@$SERVER_IP:/opt/saas-factory/core/database/
scp core/database/init-scripts/01-init-multiple-databases.sh root@$SERVER_IP:/opt/saas-factory/core/database/init-scripts/
scp core/monitoring/docker-compose.yml root@$SERVER_IP:/opt/saas-factory/core/monitoring/
scp core/traefik/docker-compose.yml root@$SERVER_IP:/opt/saas-factory/core/traefik/

echo "   📄 Copying DB script..."
scp scripts/db-manage.sh root@$SERVER_IP:/opt/saas-factory/scripts/

# Copy environment variables
echo "   🔐 Copying environment configuration..."
scp .env root@$SERVER_IP:/opt/saas-factory/

# Copy and execute the deployment script
echo "📤 Copying deployment script to server..."
scp /tmp/server-deploy-core.sh root@$SERVER_IP:/tmp/

echo "🚀 Running deployment on server..."
ssh root@$SERVER_IP 'chmod +x /tmp/server-deploy-core.sh && MAIN_DOMAIN='"$MAIN_DOMAIN"' POSTGRES_PASSWORD='"$POSTGRES_PASSWORD"' /tmp/server-deploy-core.sh && rm /tmp/server-deploy-core.sh'

# Clean up local temp file
rm /tmp/server-deploy-core.sh

echo ""
echo "🎉 Core deployment completed!"
echo ""
echo "🔗 Quick links:"
echo "   SSH to server: ssh root@$SERVER_IP"
echo "   View services: ssh root@$SERVER_IP 'docker ps'"
echo "   View logs:     https://logs.$MAIN_DOMAIN"
echo ""
echo "📚 Next steps:"
echo "   1. Visit https://status.$MAIN_DOMAIN to set up monitoring"
echo "   2. Start deploying your SaaS applications!"
