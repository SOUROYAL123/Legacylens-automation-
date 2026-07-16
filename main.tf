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

# 4. Update the VPC's Default/Main Route Table to act as the Public Highway
resource "aws_default_route_table" "public_rt" {
  default_route_table_id = aws_vpc.legacylens.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Legacylens-Public-RT"
  }
}

# 5. Associate the Public Route Table with the Public Subnet (Safely Bypassed)
# resource "aws_route_table_association" "public_assoc" {
#   subnet_id      = aws_subnet.public_subnet.id
#   route_table_id = aws_route_table.public_rt.id
# }

# 6. Create Private App Subnet (Lab Standard Naming)
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Legacylens-Private-App"
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
    description = "SSH from anywhere"
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

# 9. Spin up the free-tier EC2 Bastion Host (Ubuntu 24.04 Blueprint)
resource "aws_instance" "bastion" {
  ami                    = "ami-0522ab6e1ddcc7055" 
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = "legacylens-key"

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

# 12. Create a Dedicated Route Table for Private Subnets (Lab Standard Naming)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "Legacylens-Private-RT"
  }
}

# 13. Associate Private App Subnet to the Private Route Table
resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private.id
}

# 14. Create a Database Subnet Group for Multi-AZ deployments
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "legacylens-db-subnet-group"
  subnet_ids = [aws_subnet.private_app.id, aws_subnet.private_db_subnet.id]

  tags = {
    Name = "Legacylens-DB-Subnet-Group"
  }
}

# 15. Create the Database Security Group
resource "aws_security_group" "db_sg" {
  name        = "Legacylens-DB-SG"
  description = "Access rules for PostgreSQL database instances"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "Allow PostgreSQL port 5432 strictly from the Private App Subnet"
    from_port   = 5432                 
    to_port     = 5432                 
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]       
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Legacylens-DB-SG"
  }
}

# ====================================================================
# 🛠️ STATE REFACTORING MIGRATION BLOCKS
# Prevents destruction by safely renaming tracked objects in state file
# ====================================================================

moved {
  from = aws_subnet.private_app_subnet
  to   = aws_subnet.private_app
}

moved {
  from = aws_route_table.private_rt
  to   = aws_route_table.private
}