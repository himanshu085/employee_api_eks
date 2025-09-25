# ------------------------
# Data Sources
# ------------------------
data "aws_availability_zones" "available" {}

# ------------------------
# VPC
# ------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

# ------------------------
# Subnets
# ------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_a
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_b
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_a
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project}-${var.environment}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_b
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project}-${var.environment}-private-b"
  }
}

# ------------------------
# Internet Gateway
# ------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# ------------------------
# Elastic IP for NAT
# ------------------------
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

# ------------------------
# NAT Gateway
# ------------------------
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "${var.project}-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ------------------------
# Route Tables
# ------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-private-rt"
  }
}

# ------------------------
# Route Table Associations
# ------------------------
resource "aws_route_table_association" "public_assoc_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_assoc_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_assoc_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ------------------------
# Security Groups
# ------------------------
# ALB SG
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${var.project}-${var.environment}-alb-sg"

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "${var.project}-${var.environment}-alb-sg"
  }
}

# Bastion SG
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${var.project}-${var.environment}-bastion-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # restrict to your IP ideally
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-bastion-sg"
  }
}

# App SG (only ALB + Bastion)
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${var.project}-${var.environment}-app-sg"

  # ALB -> App
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Bastion -> App (SSH)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-sg"
  }
}

# Scylla SG
resource "aws_security_group" "scylla_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${var.project}-${var.environment}-scylla-sg"

  # Bastion -> Scylla (SSH)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # App -> Scylla (Cassandra client port)
  ingress {
    from_port       = 9042
    to_port         = 9042
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-scylla-sg"
  }
}

# Redis SG
resource "aws_security_group" "redis_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${var.project}-${var.environment}-redis-sg"

  # Bastion -> Redis (SSH)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # App -> Redis (default port)
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-redis-sg"
  }
}

# ------------------------
# Application Load Balancer
# ------------------------
resource "aws_lb" "app_alb" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "${var.project}-${var.environment}-alb"
  }

  depends_on = [aws_subnet.public_a, aws_subnet.public_b]
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project}-${var.environment}-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/swagger/index.html"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "${var.project}-${var.environment}-tg"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ------------------------
# IAM Role + Policies
# ------------------------
resource "aws_iam_role" "app_role" {
  name = "${var.project}-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "app_s3_policy" {
  name   = "${var.project}-${var.environment}-app-s3-policy"
  role   = aws_iam_role.app_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::jenkinsbackup085",
          "arn:aws:s3:::jenkinsbackup085/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "app_ssm_policy" {
  name   = "${var.project}-${var.environment}-app-ssm-policy"
  role   = aws_iam_role.app_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ],
        Resource = "arn:aws:ssm:us-east-1:891612580887:parameter/employee_api/github-pat"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "${var.project}-${var.environment}-app-instance-profile"
  role = aws_iam_role.app_role.name
}

# ------------------------
# EC2 Instances
# ------------------------
# Bastion (public)
resource "aws_instance" "bastion" {
  ami                    = "ami-0bbdd8c17ed981ef9"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = "vmkey"

  associate_public_ip_address = true

  tags = { Name = "${var.project}-${var.environment}-bastion" }
}

# App (private, no public IP)
resource "aws_instance" "app" {
  ami                    = "ami-0bbdd8c17ed981ef9"
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = "vmkey"
  iam_instance_profile   = aws_iam_instance_profile.app_instance_profile.name
  associate_public_ip_address = false

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # ensure App waits for Scylla + Redis to finish
  depends_on = [
    aws_instance.scylla,
    aws_instance.redis,
    aws_route_table_association.private_assoc_a
  ]

  connection {
    type                = "ssh"
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    host                = self.private_ip
    bastion_host        = aws_instance.bastion.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y unzip curl",
      "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip -o awscliv2.zip",
      "sudo ./aws/install",
      "aws s3 cp s3://jenkinsbackup085/setup1.sh /home/ubuntu/setup1.sh",
      "chmod +x /home/ubuntu/setup1.sh",
      "bash /home/ubuntu/setup1.sh"
    ]
  }

  tags = { Name = "${var.project}-${var.environment}-app" }
}

# Scylla (private, via Bastion)
resource "aws_instance" "scylla" {
  ami                    = "ami-0bbdd8c17ed981ef9"
  instance_type          = var.scylla_instance_type
  subnet_id              = aws_subnet.private_b.id
  vpc_security_group_ids = [aws_security_group.scylla_sg.id]
  key_name               = "vmkey"

  depends_on = [aws_route_table_association.private_assoc_b]

  connection {
    type                = "ssh"
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    host                = self.private_ip
    bastion_host        = aws_instance.bastion.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ubuntu",
      "sudo docker rm -f scylla || true",
      "sudo docker run -d --name scylla -p 9042:9042 scylladb/scylla:latest"
    ]
  }
}

# Redis (private, via Bastion)
resource "aws_instance" "redis" {
  ami                    = "ami-0bbdd8c17ed981ef9"
  instance_type          = var.redis_instance_type
  subnet_id              = aws_subnet.private_b.id
  vpc_security_group_ids = [aws_security_group.redis_sg.id]
  key_name               = "vmkey"

  depends_on = [aws_route_table_association.private_assoc_b]

  connection {
    type                = "ssh"
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    host                = self.private_ip
    bastion_host        = aws_instance.bastion.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ubuntu",
      "sudo docker rm -f redis || true",
      "sudo docker run -d --name redis -p 6379:6379 redis:latest"
    ]
  }
}

# ------------------------
# Register App with Target Group
# ------------------------
resource "aws_lb_target_group_attachment" "app_tg_attachment" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app.id
  port             = 8080
}
