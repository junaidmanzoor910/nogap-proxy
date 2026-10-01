variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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
  description = "Ubuntu 24.04 LTS AMI in us-east-1 (pin after inspection; update on rebuild)"
  type        = string
  default     = "ami-0045d7fc2ad003464"
}

variable "subnet_id" {
  description = "Public subnet for the proxy instance (default VPC public subnet)"
  type        = string
  default     = "subnet-0e1846394e4fca539"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = "vpc-0e0ba7688bcfc8569"
}

variable "additional_tags" {
  description = "Extra tags applied to billable resources"
  type        = map(string)
  default     = {}
}
