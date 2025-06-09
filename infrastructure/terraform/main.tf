# SSH Key
resource "hcloud_ssh_key" "saas_factory_key" {
  name       = "${var.server_name}-key"
  public_key = file(var.ssh_public_key_path)
}

# Server
resource "hcloud_server" "saas_factory" {
  name        = var.server_name
  image       = var.server_image
  server_type = var.server_type
  location    = var.server_location
  
  ssh_keys = [hcloud_ssh_key.saas_factory_key.id]
  
  labels = {
    project = "saas-factory"
    env     = "production"
  }

  # Basic setup script
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y curl wget git
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker root
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create directories
    mkdir -p /opt/saas-factory/{core,apps,data}
    
    # Enable Docker service
    systemctl enable docker
    systemctl start docker
  EOF

  # Prevent recreation on user_data changes (since we'll configure via scripts later)
  lifecycle {
    ignore_changes = [user_data]
  }
}

# Firewall (SSH only, rest handled by Cloudflare Tunnel)
resource "hcloud_firewall" "saas_factory_firewall" {
  name = "${var.server_name}-firewall"
  
  # SSH access
  rule {
    direction = "in"
    port      = "22"
    protocol  = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Attach firewall to server
resource "hcloud_firewall_attachment" "saas_factory_firewall_attachment" {
  firewall_id = hcloud_firewall.saas_factory_firewall.id
  server_ids  = [hcloud_server.saas_factory.id]
}

# Cloudflare Zone Settings
resource "cloudflare_zone_settings_override" "saas_factory_settings" {
  zone_id = var.cloudflare_zone_id
  
  settings {
    # SSL settings
    ssl                     = "full"
    always_use_https        = "on"
    min_tls_version         = "1.2"
    
    # Security settings
    security_level          = "medium"
    challenge_ttl           = 1800
    
    # Performance settings
    browser_cache_ttl       = 14400
    browser_check           = "on"
    
    development_mode        = "off"
  }
}
