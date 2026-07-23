provider "aws" {
  region = "ap-south-1" # Mumbai region
}

# 1. Core Virtual Private Cloud Perimeter
resource "aws_vpc" "legacylens" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "Legacylens-VPC"
  }
}

# 2. Public Facing Lobby Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "Legacylens-Public-Subnet"
  }
}

# 3. Inbound/Outbound Public Highway Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.legacylens.id

  tags = {
    Name = "Legacylens-IGW"
  }
}

# 4. Main Route Table Configuration (Public Network Rules -> IGW)
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

# 5. Isolated Application Core Subnet
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Legacylens-Private-App"
  }
}

# 6. Isolated Database Subnet 1
resource "aws_subnet" "private_db_subnet" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "Legacylens-Private-DB-Subnet"
  }
}

# 6b. Additional Isolated Database Subnet 2 for Multi-AZ High Availability
resource "aws_subnet" "private_db_subnet_2" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Legacylens-Private-DB-Subnet2"
  }
}

# 7. Security Firewall for Public Guard (Bastion Host)
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

# 7b. Inner Firewall for Private App Server (Security Group Nesting)
resource "aws_security_group" "private_app_sg" {
  name        = "private-app-sg"
  description = "Access rules for hidden application server tier"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description     = "Allow SSH strictly from instances wearing Bastion SG badge"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    description = "Allow all outbound traffic via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Legacylens-Private-App-SG"
  }
}

# 8. Hardened EC2 Bastion Host Instance (With SSM Profile Attached)
resource "aws_instance" "bastion" {
  ami                    = "ami-0522ab6e1ddcc7055"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = "legacylens-key"

  # Attaches the SSM IAM Instance Profile so the instance connects to SSM
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  tags = {
    Name = "Legacylens-Bastion-Host"
  }
}

# 9. Static Public IP Assignment for NAT Routing
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "Legacylens-NAT-EIP"
  }
}

# 10. Unidirectional NAT Gateway (Placed in Public Subnet)
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "Legacylens-NAT-GW"
  }
}

# 11. Custom Dedicated Route Table for Private Subnets (Routes -> NAT Gateway)
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

# 12. Associate Application Subnet to Private Routing Layer
resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private.id
}

# 13. Managed Multi-AZ Database Group Mapping
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "legacylens-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_subnet.id, aws_subnet.private_db_subnet_2.id]

  tags = {
    Name = "Legacylens-DB-Subnet-Group"
  }
}

# 14. Task 1 Compliance: Database Security Group (Least Privilege Referencing)
resource "aws_security_group" "db_sg" {
  name        = "Legacylens-DB-SG"
  description = "Access rules for PostgreSQL database instances"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description     = "Allow PostgreSQL port 5432 strictly from Private App SG badge"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_app_sg.id] # 👈 Least Privilege SG Chaining
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

# 15. Production-Ready Managed Postgres Database Engine (Multi-AZ)
resource "aws_db_instance" "postgres_db" {
  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  db_name                = "legacylens_prod"
  username               = "db_admin_user"
  password               = "LegacyLensSecure2026!"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az               = true
  skip_final_snapshot    = true

  tags = {
    Name = "Legacylens-Production-Database"
  }
}

# 16. Private Application Server
resource "aws_instance" "private_app_server" {
  ami                    = "ami-0522ab6e1ddcc7055"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]
  key_name               = "legacylens-key"

  tags = {
    Name = "Legacylens-Private-App-Server"
  }
}

# 17. IAM Role for Systems Manager (SSM)
resource "aws_iam_role" "ssm_role" {
  name = "Legacylens-SSM-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 18. Attach the AmazonSSMManagedInstanceCore Policy to the Role
resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 19. Create an Instance Profile to pass the IAM Role to the Bastion Instance
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "Legacylens-SSM-Profile"
  role = aws_iam_role.ssm_role.name
}

# ====================================================================
# 🛠️ STATE REFACTORING MIGRATION BLOCKS
# ====================================================================
moved {
  from = aws_subnet.private_app_subnet
  to   = aws_subnet.private_app
}

moved {
  from = aws_route_table.private_rt
  to   = aws_route_table.private
}