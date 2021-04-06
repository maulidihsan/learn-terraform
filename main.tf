provider "aws" {
    region      = var.aws_region
}

variable aws_region {
  type          = string
  default       = "ap-southeast-1"
  description   = "AWS Region"
}
variable vpc_cidr_block {
  type        = string
  default     = ""
  description = "VPC CIDR block"
}

variable subnet_cidr_block {
  type        = string
  default     = ""
  description = "Subnet CIDR block"
}

variable avail_zone {
  type        = string
  default     = ""
  description = "description"
}

variable  env_prefix {
  type        = string
  default     = ""
  description = "Environment prefix"
}

variable public_key_location {
    type      = string
}

variable instance_type {
    type      = string
}

variable my_ip {
    type      = string
    default   = ""
}

resource "aws_vpc" "app-vpc" {
    cidr_block          = var.vpc_cidr_block

    tags        = {
        Name = "${var.env_prefix}-vpc"
    }
}

resource "aws_subnet" "app-subnet-1" {
    vpc_id              = aws_vpc.app-vpc.id
    cidr_block          = var.subnet_cidr_block
    availability_zone   = var.avail_zone
    tags                = {
        Name = "${var.env_prefix}-subnet-1"
    }
}

resource "aws_route_table" "app-route-table" {
    vpc_id  = aws_vpc.app-vpc.id

    route {
        cidr_block  = "0.0.0.0/0"
        gateway_id  = aws_internet_gateway.app-igw.id
    }
    tags   = {
        Name    = "${var.env_prefix}-route-table"
    }
}

resource "aws_internet_gateway" "app-igw" {
    vpc_id  = aws_vpc.app-vpc.id
    tags    = {
        Name    = "${var.env_prefix}-igw"
    }
}

resource "aws_route_table_association" "a-rtb-subnet" {
    subnet_id       = aws_subnet.app-subnet-1.id
    route_table_id  = aws_route_table.app-route-table.id
}

resource "aws_security_group" "app-sg" {
    name    = "app-sg"
    vpc_id  = aws_vpc.app-vpc.id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["${var.my_ip}/32"]
    }

    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["${var.my_ip}/32"]
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
        prefix_list_ids = []
    }

    tags = {
        Name    = "${var.env_prefix}-sg"
    }
}

data "aws_ami" "latest-amazon-linux" {
    most_recent = true
    owners      = ["amazon"]
    filter {
        name    = "name"
        values  = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
    filter {
        name    = "virtualization-type"
        values  = ["hvm"]
    }
}

resource "aws_key_pair" "ssh-key" {
    key_name    = "server_key"
    public_key  = file(var.public_key_location)
}

resource "aws_instance" "nginx-server" {
    ami                         = data.aws_ami.latest-amazon-linux.id
    instance_type               = var.instance_type

    subnet_id                   = aws_subnet.app-subnet-1.id
    vpc_security_group_ids      = [aws_security_group.app-sg.id]
    availability_zone           = var.avail_zone

    associate_public_ip_address = true
    key_name                    = aws_key_pair.ssh-key.key_name

    user_data                   = <<EOF
                                        #!/bin/bash
                                        sudo yum update -y
                                        sudo yum install docker -y
                                        sudo systemctl start docker
                                        sudo usermod -aG docker ec2-user
                                        docker run -p 8080:80 nginx
                                    EOF
    tags = {
        Name = "${var.env_prefix}-nginxserver"
    }
}

output "ec2_public_ip" {
    value = aws_instance.nginx-server.public_ip
}
