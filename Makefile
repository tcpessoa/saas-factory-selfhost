.PHONY: help check-env infrastructure tunnel core ssh status destroy clean

GREEN=\033[0;32m
YELLOW=\033[1;33m
RED=\033[0;31m
BLUE=\033[0;34m
PURPLE=\033[0;35m
NC=\033[0m # No Color

# Default target
help: ## Show this help message
	@echo "$(GREEN)SaaS Factory - Available commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Quick start:$(NC)"
	@echo "  1. cp .env.example .env  (and edit with your values)"
	@echo "  2. make setup            (full deployment - infra + tunnel + core)"
	@echo ""
	@echo "$(GREEN)Manual deployment:$(NC)"
	@echo "  1. make infrastructure   (deploy VPS and DNS)"
	@echo "  2. make tunnel           (install Cloudflare tunnel)"
	@echo "  3. make core             (deploy core services)"

setup: check-env ## 🚀 Complete setup: deploy infrastructure, tunnel, and core services
	@echo "$(PURPLE)╔════════════════════════════════════════╗$(NC)"
	@echo "$(PURPLE)║        SaaS Factory Setup              ║$(NC)"
	@echo "$(PURPLE)║  This will deploy your complete stack  ║$(NC)"
	@echo "$(PURPLE)╚════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)Phase 1/3: Infrastructure Deployment$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) infrastructure
	@echo ""
	@echo "$(BLUE)Phase 2/3: Cloudflare Tunnel Setup$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) tunnel
	@echo ""
	@echo "$(BLUE)Phase 3/3: Core Services Deployment$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) core
	@echo ""
	@echo "$(GREEN)🎉 Setup Complete!$(NC)"
	@echo "$(GREEN)═══════════════════$(NC)"
	@MAIN_DOMAIN=$$(grep '^MAIN_DOMAIN=' .env | cut -d'=' -f2) && \
	echo "🌐 Your SaaS Factory is ready at: https://$$MAIN_DOMAIN" && \
	echo "📊 Run 'make status' to see all services" && \
	echo "📋 Run 'make logs' to view service logs"

check-env: ## Check if .env exists and generate terraform.tfvars
	@if [ ! -f .env ]; then \
		echo "$(RED)❌ .env file not found. Copy .env.example to .env and fill in your values.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)🔄 Generating terraform.tfvars from .env...$(NC)"
	@set -a; . ./.env; set +a; \
	cd infrastructure/terraform && \
	echo "hetzner_token = \"$$HETZNER_TOKEN\"" > terraform.tfvars && \
	echo "cloudflare_api_token = \"$$CLOUDFLARE_API_TOKEN\"" >> terraform.tfvars && \
	echo "ssh_public_key_path = \"$$SSH_PUBLIC_KEY_PATH\"" >> terraform.tfvars && \
	echo "main_domain = \"$$MAIN_DOMAIN\"" >> terraform.tfvars && \
	echo "cloudflare_zone_id = \"$$CLOUDFLARE_ZONE_ID\"" >> terraform.tfvars && \
	echo "cloudflare_account_id = \"$$CLOUDFLARE_ACCOUNT_ID\"" >> terraform.tfvars

infrastructure: check-env ## Deploy VPS and configure security
	@echo "$(GREEN)🚀 Deploying infrastructure...$(NC)"
	@cd infrastructure/terraform && terraform init && terraform apply -auto-approve
	@echo "$(GREEN)⏳ Waiting for server to be ready...$(NC)"
	@sleep 30
	@echo "$(GREEN)🔒 Configuring server security...$(NC)"
	@./scripts/configure-security.sh

tunnel: check-env ## Install and configure Cloudflare tunnel
	@echo "$(GREEN)🌐 Installing Cloudflare tunnel...$(NC)"
	@./scripts/install-tunnel.sh

core: check-env ## Deploy core services (database, monitoring, traefik)
	@echo "$(GREEN)📦 Deploying core services...$(NC)"
	@./scripts/deploy-core.sh

ssh: check-env ## SSH into the server
	@SERVER_IP=$$(cd infrastructure/terraform && terraform output -raw server_ip 2>/dev/null); \
	if [ -z "$$SERVER_IP" ]; then \
		echo "$(RED)❌ Could not get server IP. Has infrastructure been deployed?$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)🔗 Connecting to $$SERVER_IP...$(NC)"; \
	ssh root@$$SERVER_IP

status: check-env ## Show infrastructure and services status
	@echo "$(GREEN)📊 Infrastructure Status$(NC)"
	@echo "======================"
	@if [ -f infrastructure/terraform/terraform.tfstate ]; then \
		MAIN_DOMAIN=$$(grep '^MAIN_DOMAIN=' .env | cut -d'=' -f2) && \
		cd infrastructure/terraform && \
		echo "🖥️  Server IP: $$(terraform output -raw server_ip 2>/dev/null || echo 'Not deployed')" && \
		echo "🌐 Domain: $$MAIN_DOMAIN" && \
		echo "🔗 Tunnel ID: $$(terraform output -raw tunnel_id 2>/dev/null || echo 'Not available')" && \
		echo "" && \
		echo "$(GREEN)🔍 Server Status:$(NC)" && \
		SERVER_IP=$$(terraform output -raw server_ip 2>/dev/null); \
		if [ -n "$$SERVER_IP" ]; then \
			echo "🖥️  Attempting SSH connection..." && \
			if ssh -o ConnectTimeout=10 -o BatchMode=yes root@$$SERVER_IP 'echo "✅ SSH connection successful"' 2>/dev/null; then \
				echo ""; \
				echo "$(GREEN)🐳 Docker Services:$(NC)"; \
				ssh -o ConnectTimeout=5 root@$$SERVER_IP 'docker ps --format "table {{.Names}}\t{{.Status}}"' 2>/dev/null || echo "⚠️  Cannot retrieve Docker status"; \
				echo ""; \
				echo "$(GREEN)🌐 Tunnel Status:$(NC)"; \
				ssh -o ConnectTimeout=5 root@$$SERVER_IP 'systemctl is-active cloudflared && echo "✅ Tunnel is running" || echo "❌ Tunnel is not running"' 2>/dev/null || echo "⚠️  Cannot check tunnel status"; \
			fi; \
			echo ""; \
			echo "💡 Web services accessible via: https://(subdomain).$$MAIN_DOMAIN"; \
		else \
			echo "❌ Server IP not found"; \
		fi \
	else \
		echo "$(RED)❌ No infrastructure deployed yet$(NC)"; \
		echo "Run 'make infrastructure' to create infrastructure first"; \
	fi

logs: check-env ## View logs from all services
	@SERVER_IP=$$(cd infrastructure/terraform && terraform output -raw server_ip 2>/dev/null); \
	if [ -z "$$SERVER_IP" ]; then \
		echo "$(RED)❌ Could not get server IP. Has infrastructure been deployed?$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)📋 Viewing service logs (Ctrl+C to exit)...$(NC)"; \
	MAIN_DOMAIN=$$(grep '^MAIN_DOMAIN=' .env | cut -d'=' -f2) && \
	echo "💡 You can also view logs via Dozzle at: https://logs.$$MAIN_DOMAIN"; \
	echo ""; \
	ssh root@$$SERVER_IP 'docker logs --tail=50 -f saas-factory-traefik 2>/dev/null || echo "Traefik is not running"'

destroy: check-env ## Destroy all infrastructure (⚠️ DANGEROUS)
	@echo "$(RED)⚠️  This will destroy your VPS and all data!$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	@echo "$(YELLOW)Getting server IP before destruction...$(NC)"
	@SERVER_IP=$$(cd infrastructure/terraform && terraform output -raw server_ip 2>/dev/null || echo ""); \
	cd infrastructure/terraform && terraform destroy -auto-approve; \
	if [ -n "$$SERVER_IP" ]; then \
		echo "$(YELLOW)Cleaning up known_hosts for IP: $$SERVER_IP$(NC)"; \
		ssh-keygen -R "$$SERVER_IP" 2>/dev/null || true; \
		echo "$(GREEN)✓ Removed $$SERVER_IP from known_hosts$(NC)"; \
	else \
		echo "$(YELLOW)Could not determine server IP, skipping known_hosts cleanup$(NC)"; \
	fi
	@echo "$(GREEN)Infrastructure destroyed successfully$(NC)"

clean: ## Clean temporary files
	@echo "$(GREEN)🧹 Cleaning temporary files...$(NC)"
	@rm -rf infrastructure/terraform/.terraform/
	@rm -f infrastructure/terraform/terraform.tfstate.backup
	@rm -f infrastructure/terraform/terraform.tfvars
