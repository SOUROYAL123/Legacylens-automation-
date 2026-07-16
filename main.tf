provider "aws" {
  region = "ap-south-1" # Mumbai region
}

resource "aws_vpc" "legacylens" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "Legacylens-VPC"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "Legacylens-Public-Subnet"
  }
}
# 3. Create the Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.legacylens.id

  tags = {
    Name = "Legacylens-IGW"
  }
}

# 4. Create a Custom Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Legacylens-Public-RT"
  }
}

# 5. Associate the Public Route Table with the Public Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
# 6. Create Private App Subnet
resource "aws_subnet" "private_app_subnet" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Legacylens-Private-App-Subnet"
  }
}

# 7. Create Private DB Subnet
resource "aws_subnet" "private_db_subnet" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "Legacylens-Private-DB-Subnet"
  }
}

# 8. Create Security Group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH access to Bastion host"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "SSH from anywhere (or change to your specific IP)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# 9. Spin up the free-tier EC2 Bastion Host (Amazon Linux 2023)
resource "aws_instance" "bastion" {
  ami           = "ami-0522ab6e1ddcc7055" # Standard Amazon Linux 2023 AMI for ap-south-1
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  # Optional: Uncomment and add your key name if you created it in AWS Console
  # key_name               = "legacylens-key"

  tags = {
    Name = "Legacylens-Bastion-Host"
  }
}
# 10. Allocate an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "Legacylens-NAT-EIP"
  }
}

# 11. Deploy the NAT Gateway into the Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "Legacylens-NAT-GW"
  }
}

# 12. Create a Dedicated Route Table for Private Subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "Legacylens-Private-RT"
  }
}

# 13. Associate Private App Subnet to the NAT Route Table
resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# 14. Create a Database Subnet Group for Multi-AZ deployments
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "legacylens-db-subnet-group"
  subnet_ids = [aws_subnet.private_app_subnet.id, aws_subnet.private_db_subnet.id]

  tags = {
    Name = "Legacylens-DB-Subnet-Group"
  }
}