variable "github_token" {
  type = string
}

variable "repo_name" {
  type = string
  default = "base-go"
}

variable "ec2_user" {
  type = string
  default = "ubuntu"
}

provider "aws" {
  region = "eu-central-1"
}

provider "github" {
  token = var.github_token
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "aws_availability_zones" "avz" {}

data "aws_ami" "ubuntu" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name_prefix = "allow_ssh"

  ingress {
    to_port     = 22
    from_port   = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    to_port     = 80
    from_port   = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.example.public_key_openssh
}

resource "aws_instance" "vm" {
  instance_type          = "t3.micro"
  ami                    = data.aws_ami.ubuntu.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = <<EOT
#!/bin/bash
# Install docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get update
apt-get install -y docker-ce
usermod -aG docker ubuntu

# Install docker-compose
curl -L https://github.com/docker/compose/releases/download/1.21.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
  EOT

  tags = {
    Name = "MicroUbuntu"
  }
}


resource "local_file" "ssh_key" {
  content  = tls_private_key.example.private_key_openssh
  filename = "ssh_ec2_key_private"
}

output "ssh" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true
}

output "public_ip" {
  value = aws_instance.vm.public_ip
}

data "github_actions_public_key" "example" {
  repository = var.repo_name
}

resource "github_actions_secret" "private_key_secret" {
  repository = var.repo_name
  secret_name = "EC2_SSH_PRIVATE_KEY"
  plaintext_value = tls_private_key.example.private_key_pem
}

resource "github_actions_secret" "user_secret" {
  repository = var.repo_name
  secret_name = "EC2_USER"
  plaintext_value = var.ec2_user
}

resource "github_actions_secret" "host_secret" {
  repository = var.repo_name
  secret_name = "EC2_HOST"
  plaintext_value = aws_instance.vm.public_ip
}