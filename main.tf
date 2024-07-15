#variables
variable "access_key" {
  description = "IAM user access key"
}
variable "secret_key" {
  description = "IAM user secret key"
}

#Provider
provider "aws" {
  region = "eu-west-2"
  access_key = var.access_key
  secret_key = var.secret_key
}

#budget
resource "aws_budgets_budget" "Monthly_budget"{
 name              = "prod_budget"
 budget_type	   = "COST"
 limit_amount      = "0.00"
 limit_unit        = "USD"
 time_unit         = "MONTHLY"
 time_period_start = "2022-08-25_00:01"
}

#vpc 1
resource "aws_vpc" "prod-vpc" {
 cidr_block = "10.0.0.0/16"
 tags = {
  Name = "Production-VPC"
  }
}

#internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

}

#custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}


#Subnets 
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "Prod_Subnet"
  }
}

resource "aws_subnet" "subnet-2" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "Dev_Subnet"
  }
}

#Associate prod subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#Security group to allow port 22, 80, 443
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "allow_web_inbound_traffic"
  vpc_id      = aws_vpc.prod-vpc.id

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

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" #for any protocol, use "-1" as protocol value
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#Create NIC with valid ip in subnet range
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

#Assign an elastic IP
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

#test outputs
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

output "server_private_ip" {
  value = aws_instance.web_server_instance.private_ip
}


#Create server instance and intstall apache
resource "aws_instance" "web_server_instance" {
  ami           = "ami-0fb391cce7a602d1f"
  instance_type = "t2.micro"
  availability_zone = "eu-west-2a"
  key_name      = "iac-key"
  
  network_interface {
      device_index = 0 #first network interface
      network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data     = file("IaC_user_data.sh")

  tags = {
    Name = "IaC Web_Server"
  }
} 