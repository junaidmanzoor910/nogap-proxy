data "aws_subnet" "selected" {
  id = var.subnet_id
}

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      ManagedBy   = "terraform"
      ProxyHost   = var.proxy_hostname
      Application = var.allowed_destination_domain
    },
    var.additional_tags,
  )
}

resource "aws_security_group" "proxy" {
  name        = "${var.project_name}-sg"
  description = "Disguised OpenVPN on TCP 443 (looks like HTTPS); SSM egress only (no SSH)"
  vpc_id      = var.vpc_id

  # OpenVPN — disguised as HTTPS on TCP 443 (with internal fallback to Nginx)
  ingress {
    description = "OpenVPN disguised over HTTPS (TCP 443)"
    from_port   = var.proxy_https_port
    to_port     = var.proxy_https_port
    protocol    = "tcp"
    cidr_blocks = [var.proxy_client_cidr_ipv4]
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6_ingress ? [1] : []
    content {
      description      = "OpenVPN disguised over HTTPS (IPv6 TCP 443)"
      from_port        = var.proxy_https_port
      to_port          = var.proxy_https_port
      protocol         = "tcp"
      ipv6_cidr_blocks = [var.proxy_client_cidr_ipv6]
    }
  }

  # Practical egress for SSM, DNS, NTP, OS updates, ACME DNS API, and HTTPS to allowed app origins.
  # Security groups cannot filter by domain; Squid enforces destination policy.
  egress {
    description = "Outbound IPv4 (see docs/COST.md for tightening options)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = var.enable_ipv6_ingress ? [1] : []
    content {
      description      = "Outbound IPv6 (only if AAAA published and instance uses v6)"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-sg" })
}

resource "aws_iam_role" "ssm" {
  name = "${var.project_name}-ec2-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "proxy" {
  ami                    = var.ubuntu_ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.proxy.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  # No SSH key pair — administration via SSM Session Manager only.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/../cloud-init/user-data.yaml.tpl", {
    proxy_hostname             = var.proxy_hostname
    allowed_destination_domain = var.allowed_destination_domain
    pac_https_port             = var.pac_https_port
    proxy_https_port           = var.proxy_https_port
  })

  user_data_replace_on_change = true

  tags = merge(local.common_tags, { Name = "${var.project_name}-ec2" })

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "proxy" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.project_name}-eip" })
}

resource "aws_eip_association" "proxy" {
  instance_id   = aws_instance.proxy.id
  allocation_id = aws_eip.proxy.id
}
