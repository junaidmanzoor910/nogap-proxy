variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "stagging"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Resource naming prefix"
  type        = string
  default     = "nogap-split-proxy"
}

variable "proxy_hostname" {
  description = "TLS hostname for the forward proxy and PAC (DNS A record target is the Elastic IP)"
  type        = string
  default     = "proxy-dev.nogap.ai"
}

variable "allowed_destination_domain" {
  description = "Application domain permitted through the proxy (subdomains allowed via label-boundary ACLs)"
  type        = string
  default     = "app-dev.nogap.ai"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gib" {
  description = "Root EBS volume size (GiB)"
  type        = number
  default     = 20
}

variable "pac_https_port" {
  description = "Nginx HTTPS port serving the PAC file"
  type        = number
  default     = 8443
}

variable "proxy_https_port" {
  description = "Squid HTTPS forward proxy listener port"
  type        = number
  default     = 443
}

variable "proxy_client_cidr_ipv4" {
  description = "IPv4 CIDR allowed to reach proxy and PAC ports (use narrower ranges if policy requires)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_ipv6_ingress" {
  description = "If false, security group has no IPv6 ingress (recommended unless you publish AAAA and need v6 clients)"
  type        = bool
  default     = false
}

variable "proxy_client_cidr_ipv6" {
  description = "IPv6 CIDR for ingress when enable_ipv6_ingress is true"
  type        = string
  default     = "::/0"
}

variable "ubuntu_ami_id" {
  description = "Ubuntu 24.04 LTS AMI in ap-south-1"
  type        = string
  default     = "ami-007b1f3fdea0383d9"
}

variable "subnet_id" {
  description = "Public subnet for the proxy instance (default VPC public subnet in ap-south-1)"
  type        = string
  default     = "subnet-0533622882f2dd7c3"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = "vpc-075f158427b4c385f"
}

variable "additional_tags" {
  description = "Extra tags applied to billable resources"
  type        = map(string)
  default     = {}
}
