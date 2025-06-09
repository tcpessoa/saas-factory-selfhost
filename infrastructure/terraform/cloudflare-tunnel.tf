# Create the tunnel (using new resource type)
resource "cloudflare_zero_trust_tunnel_cloudflared" "saas_factory" {
  account_id = var.cloudflare_account_id
  name       = "saas-factory"
  secret     = base64encode(random_password.tunnel_secret.result)
}

resource "random_password" "tunnel_secret" {
  length  = 32
  special = false  # Base64 encoding doesn't like special chars
}

# Tunnel configuration
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "saas_factory" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id

  config {
    # Simple routing - everything to Traefik
    ingress_rule {
      hostname = var.main_domain
      service  = "http://localhost:80"
    }
    
    ingress_rule {
      hostname = "*.${var.main_domain}"
      service  = "http://localhost:80"
    }

    # Additional domains (managed as list)
    dynamic "ingress_rule" {
      for_each = var.additional_domains
      content {
        hostname = ingress_rule.value
        service  = "http://localhost:80"
      }
    }
    
    dynamic "ingress_rule" {
      for_each = var.additional_domains
      content {
        hostname = "*.${ingress_rule.value}"
        service  = "http://localhost:80"
      }
    }

    # Catch-all
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS records for main domain
resource "cloudflare_record" "main_tunnel" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content   = "${cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id}.cfargotunnel.com"
  comment = "Main domain for SaaS Factory Tunnel"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "wildcard_tunnel" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  content   = "${cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id}.cfargotunnel.com"
  comment = "Wildcard for SaaS Factory Tunnel"
  type    = "CNAME"
  proxied = true
}

# DNS records for additional domains
resource "cloudflare_record" "additional_domains" {
  for_each = toset(var.additional_domains)
  
  zone_id = data.cloudflare_zone.additional[each.value].id
  name    = "@"
  value   = "${cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "additional_wildcards" {
  for_each = toset(var.additional_domains)
  
  zone_id = data.cloudflare_zone.additional[each.value].id
  name    = "*"
  value   = "${cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Data sources for zones
data "cloudflare_zone" "main" {
  name = var.main_domain
}

data "cloudflare_zone" "additional" {
  for_each = toset(var.additional_domains)
  name     = each.value
}

# Output tunnel token for server installation
output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.saas_factory.tunnel_token
  sensitive = true
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.saas_factory.id
}

output "tunnel_install_command" {
  value     = "cloudflared service install ${cloudflare_zero_trust_tunnel_cloudflared.saas_factory.tunnel_token}"
  sensitive = true
}
