output "server_ip" {
  description = "The public IP address of the server"
  value       = hcloud_server.saas_factory.ipv4_address
}

output "server_id" {
  description = "The ID of the Hetzner server"
  value       = hcloud_server.saas_factory.id
}

output "server_name" {
  description = "The name of the server"
  value       = hcloud_server.saas_factory.name
}

output "ssh_connection_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.saas_factory.ipv4_address}"
}

output "main_domain_dns" {
  description = "Main domain DNS record"
  value       = "${var.main_domain} -> ${hcloud_server.saas_factory.ipv4_address}"
}

output "firewall_id" {
  description = "The ID of the firewall"
  value       = hcloud_firewall.saas_factory_firewall.id
}
