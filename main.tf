# M1 Infrastruktur: VPC, ein öffentliches Subnetz, 5 EC2-Instanzen (cicd.internal)
# Entspricht der Infrastrukturspezifikation (Stand finaler Draft).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region # Zugangsdaten kommen aus den Umgebungsvariablen (siehe README)

  default_tags {
    tags = {
      Project   = "cicd-m1"
      ManagedBy = "terraform"
    }
  }
}

locals {
  domain = "cicd.internal"

  # Instanzplan laut Spezifikation: Hostname => feste private IP, Typ, Root-Volume (GB), Security Group
  instances = {
    dns1   = { ip = "10.0.1.10", type = "t3.micro", disk = 8, sg = "dns" }
    dns2   = { ip = "10.0.1.11", type = "t3.micro", disk = 8, sg = "dns" }
    gitlab = { ip = "10.0.1.20", type = "t3.medium", disk = 25, sg = "gitlab" }
    runner = { ip = "10.0.1.21", type = "t3.small", disk = 16, sg = "runner" }
    ldap   = { ip = "10.0.1.30", type = "t3.micro", disk = 8, sg = "ldap" }
  }

  dns_servers = [local.instances.dns1.ip, local.instances.dns2.ip]

  security_group_ids = {
    dns    = aws_security_group.dns.id
    gitlab = aws_security_group.gitlab.id
    runner = aws_security_group.runner.id
    ldap   = aws_security_group.ldap.id
  }
}

# ---------------------------------------------------------------- Netzwerk

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "cicd-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "cicd-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags                    = { Name = "cicd-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "cicd-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# DHCP-Optionen: Domain cicd.internal, Nameserver dns1 und dns2.
# Erst nach der BIND-Installation einschalten (var.use_custom_dhcp = true),
# sonst haben die VMs beim ersten Start keine Namensauflösung für apt.
resource "aws_vpc_dhcp_options" "cicd" {
  count               = var.use_custom_dhcp ? 1 : 0
  domain_name         = local.domain
  domain_name_servers = local.dns_servers
  tags                = { Name = "cicd-dhcp-options" }
}

resource "aws_vpc_dhcp_options_association" "cicd" {
  count           = var.use_custom_dhcp ? 1 : 0
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.cicd[0].id
}

# ---------------------------------------------------------------- Security Groups

resource "aws_security_group" "dns" {
  name        = "cicd-dns"
  description = "DNS-Server dns1 und dns2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.team_ips
  }
  ingress {
    description = "DNS-Anfragen (UDP) aus der VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "Zonentransfer und grosse Antworten (TCP) aus der VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "Ping-Tests"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "Alles ausgehend (apt, Forwarder 8.8.8.8)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-dns" }
}

resource "aws_security_group" "runner" {
  name        = "cicd-runner"
  description = "GitLab Runner"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.team_ips
  }
  ingress {
    description = "Ping-Tests"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "Alles ausgehend (GitLab, Docker Hub, npm)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-runner" }
}

resource "aws_security_group" "gitlab" {
  name        = "cicd-gitlab"
  description = "GitLab CE"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.team_ips
  }
  ingress {
    description     = "HTTPS Web-UI, Git ueber HTTPS, Runner-Registrierung"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = var.team_ips
    security_groups = [aws_security_group.runner.id]
  }
  ingress {
    description     = "Container Registry"
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    cidr_blocks     = var.team_ips
    security_groups = [aws_security_group.runner.id]
  }
  ingress {
    description = "Ping-Tests"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "Alles ausgehend (apt, LDAP)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-gitlab" }
}

resource "aws_security_group" "ldap" {
  name        = "cicd-ldap"
  description = "OpenLDAP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.team_ips
  }
  ingress {
    description     = "LDAP-Bind und Suche (StartTLS auf 389)"
    from_port       = 389
    to_port         = 389
    protocol        = "tcp"
    cidr_blocks     = [var.vpc_cidr]
    security_groups = [aws_security_group.gitlab.id]
  }
  ingress {
    description = "Ping-Tests"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "Alles ausgehend (apt)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-ldap" }
}

# ---------------------------------------------------------------- Instanzen

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "vm" {
  for_each = local.instances

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.value.type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = each.value.ip
  vpc_security_group_ids      = [local.security_group_ids[each.value.sg]]
  associate_public_ip_address = true # dynamisch, kein Elastic IP (Kosten)

  root_block_device {
    volume_type = "gp3"
    volume_size = each.value.disk
  }

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  # Hostname, FQDN und SSH-Schlüssel aller Teammitglieder beim ersten Start
  user_data = "#cloud-config\n${yamlencode({
    hostname                  = each.key
    fqdn                      = "${each.key}.${local.domain}"
    prefer_fqdn_over_hostname = true
    manage_etc_hosts          = true
    ssh_authorized_keys       = var.ssh_public_keys
  })}"

  tags = { Name = "${each.key}.${local.domain}" }

  depends_on = [aws_route_table_association.public]

  lifecycle {
    # Verhindert, dass ein neues Ubuntu-Image oder geänderte Schlüssel die VMs
    # (und damit z. B. alle GitLab-Daten) beim nächsten apply neu erstellen.
    ignore_changes = [ami, user_data]
  }
}
