# SaaS Factory - Simplified Solo Developer Infrastructure

A dead simple, secure infrastructure setup for running multiple SaaS applications on a single VPS using Docker Compose and Cloudflare Tunnel.

NOT PRODUCTION READY, you would need to at least not expose dozzle with DOZZLE_ENABLE_ACTIONS and DOZZLE_ENABLE_SHELL. It's just for demo purposes.

## 🚀 Quick Start (5 minutes)

### Prerequisites
- Hetzner Cloud account
- Cloudflare account with your domain
- Terraform installed locally
- SSH key pair (`ssh-keygen -t rsa -b 4096`)

### 1. Configuration
```bash
# Clone and configure
git clone <your-repo>
cd saas-factory
cp .env.example .env
# Edit .env with your API tokens and domain
```

### 2. Deploy Everything
```bash
make infrastructure  # Deploy VPS + security hardening
make tunnel          # Install Cloudflare tunnel  
make core            # Deploy database + monitoring
```

### 3. Start Building
Your infrastructure is ready! Core services available at:
- `https://traefik.yourdomain.com` - Traffic dashboard
- `https://logs.yourdomain.com` - Container logs
- `https://status.yourdomain.com` - Service monitoring

## 🏗️ What You Get

### Secure VPS Setup
- **Hardened SSH**: Key-only authentication, fail2ban protection
- **Automatic Updates**: Security patches applied automatically  
- **Minimal Firewall**: Only SSH port open (everything else via tunnel)
- **Health Monitoring**: Basic disk/memory monitoring

### Production-Ready Services
- **PostgreSQL**: Shared database with per-app isolation
- **Traefik**: Automatic HTTPS and container discovery
- **Cloudflare Tunnel**: Zero-config SSL/DNS (no port forwarding)
- **Monitoring**: Container logs (Dozzle) + uptime monitoring (Uptime Kuma)

### Developer Experience
- **Single Command Deploy**: `make core` deploys everything
- **Local Development**: Mirror production setup locally
- **Easy Scaling**: Add new apps by joining existing networks

## 📁 Repository Structure

```
saas-factory/
├── Makefile                    # All commands you need
├── .env.example               # Configuration template
├── infrastructure/terraform/   # VPS + Cloudflare DNS setup
├── core/                      # Shared services
│   ├── database/             # PostgreSQL + init scripts
│   ├── monitoring/           # Dozzle + Uptime Kuma
│   └── traefik/             # Reverse proxy
└── scripts/                  # Deployment automation
    ├── configure-security.sh # SSH hardening + firewall
    ├── install-tunnel.sh     # Cloudflare tunnel setup
    └── deploy-core.sh        # Core services deployment
```

## 🔧 Available Commands

```bash
make help            # Show all available commands
make setup           # Deploy all
make infrastructure  # Deploy VPS and configure security
make tunnel          # Install Cloudflare tunnel
make core            # Deploy database, monitoring, traefik
make ssh             # Connect to your server
make status          # Show infrastructure status
make destroy         # ⚠️ Delete everything
```

## 🔐 Security Features

- **SSH Hardening**: Password auth disabled, key-only access
- **Fail2ban**: Automatic IP blocking for failed SSH attempts
- **UFW Firewall**: Only SSH port exposed (tunnel handles everything else)
- **Auto Updates**: Security patches applied automatically
- **Network Isolation**: Docker networks separate services

## 💰 Cost Breakdown

**Monthly Total: ~$4/month**
- Hetzner CAX11 VPS: €3.29 (~$4)
- Cloudflare: Free plan sufficient

**What you get for $4/month:**
- Unlimited SaaS applications
- Automatic SSL certificates
- Professional monitoring
- Secure, hardened infrastructure
- Zero maintenance overhead

## 🏃‍♂️ Deploy Your First SaaS App

After core setup, deploying a new SaaS app is simple:

1. **Create app directory**: `mkdir /opt/saas-factory/apps/my-saas`
2. **Add Docker Compose**: Include Traefik labels and join networks
3. **Connect to database**: Use shared PostgreSQL with app-specific database
4. **Deploy**: `docker-compose up -d`

Your app automatically gets:
- HTTPS via Cloudflare tunnel
- Database access via shared PostgreSQL
- Monitoring via Dozzle/Uptime Kuma
- Professional DNS routing

## 🆘 Troubleshooting

**Infrastructure not deploying?**
- Check API tokens in `.env`
- Verify domain is managed by Cloudflare
- Ensure SSH key path is correct

**Can't access services?**
- Wait 5-10 minutes for DNS propagation
- Check tunnel status: `ssh root@<server-ip> 'systemctl status cloudflared'`
- View logs: `make ssh` then `docker logs <container-name>`

**Need to start over?**
```bash
make destroy  # ⚠️ Deletes everything
make clean    # Clean local temp files
```

## 🎯 Next Steps

1. **Set up monitoring**: Visit `https://status.yourdomain.com` to configure alerts
2. **Create database**: Script to add new database per SaaS app
3. **Deploy apps**: Use the shared infrastructure to run your SaaS applications

---

**Simple. Secure. Scalable.** Perfect for solo developers who want professional infrastructure without the complexity.

