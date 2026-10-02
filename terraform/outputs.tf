output "elastic_ip" {
  description = "Public IPv4 for Cloudflare DNS A record (grey-cloud / DNS-only)"
  value       = aws_eip.proxy.public_ip
}

output "instance_id" {
  description = "EC2 instance ID (SSM target)"
  value       = aws_instance.proxy.id
}

output "security_group_id" {
  description = "Dedicated proxy security group ID"
  value       = aws_security_group.proxy.id
}

output "pac_url" {
  description = "PAC URL after DNS and TLS are configured"
  value       = "https://${var.proxy_hostname}:${var.pac_https_port}/proxy.pac"
}

output "proxy_endpoint" {
  description = "Browser proxy host:port (authenticated HTTPS forward proxy)"
  value       = "${var.proxy_hostname}:${var.proxy_https_port}"
}

output "ssm_start_session_command" {
  description = "Operator command to open a shell (requires IAM ssm:StartSession)"
  value       = "aws ssm start-session --profile ${var.aws_profile} --region ${var.aws_region} --target ${aws_instance.proxy.id}"
}

output "openvpn_endpoint" {
  description = "Disguised OpenVPN server endpoint (TCP 443 with tls-crypt)"
  value       = "${aws_eip.proxy.public_ip}:${var.proxy_https_port}"
}

output "fetch_client_ovpn_command" {
  description = "Command to fetch client.ovpn profile to workstation"
  value       = "./scripts/fetch-client-ovpn.sh"
}

output "start_vpn_command" {
  description = "Command to start OpenVPN client software on workstation"
  value       = "./run-nogap-vpn.sh start"
}

