terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  access_key = "[access key]"
  secret_key = "[secret key]"
}

# VPC 생성
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# IGW(Internet Gateway) 생성
# VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# Route table 생성
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    # cidr_block address를 IGW로 보내고, 
    cidr_block = "0.0.0.0/0" 
    # 0.0.0.0/0 send all traffic before ip will route to IGW. 
    # 모든 트래픽이 aws IGW로 전송되기 때문에 gaqteway_id에 대한 설정이 필요하다.
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    # 실제로는 IPv6를 사용하지 않지만 All traffic이 동일한 IGW로 routing되도록 설정한다.
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# Subnet 생성
# AZ(Data centre에 대한 setup)
# 생성한 Subnet을 상단에서 설정한 Route table에 넣어준다.
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"
  tags = {
    Name = "prod-subnet"
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# create security group 
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  # Port의 range setup
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  # egrass policy 
  # protocol: -1 (any protocol)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Internet interface
# subnet 내의 ip를 private_ips의 ip로 지정한다.(any)
# 이제 s
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     =  ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

# 위에서 생성한 NI에 EIP적용를 적용한다.
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.gw
  ]
}

# Server
# device에 접근하기 위해서 key-pair에 대한 이름을 정의해줘야 한다.
resource "aws_instance" "web-server-instance" {
  ami = "ami-058165de3b7202099"
  instance_type = "t2.micro"
  availability_zone = "ap-northeast-2a"
  key_name = "class-hglee-seoul"
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo your very first web server > /var/www/html/index.html' 
              EOF
  tags = {
    Name = "web-server"
  }
}