provider "aws" {
  region  = "us-east-2"
}

############################
# Instances
############################
resource "aws_instance" "master1" {
  ami           = data.aws_ami.k8s_master_ami.id
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private_subnet.id

  vpc_security_group_ids = [aws_security_group.allow_all_sg.id]
  key_name               = aws_key_pair.ssh_key.key_name
}

resource "aws_instance" "master2" {
  ami           = data.aws_ami.k8s_master_ami.id
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private_subnet.id

  vpc_security_group_ids = [aws_security_group.allow_all_sg.id]
  key_name               = aws_key_pair.ssh_key.key_name
}

resource "aws_instance" "bastion" {
  ami           = "ami-0996d3051b72b5b2c"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id

  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.allow_all_sg.id]
  key_name               = aws_key_pair.ssh_key.key_name
}

data "aws_ami" "k8s_master_ami" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "name"
    values = ["k8s-master-*"]
  }
}



############################
# Load Balancer
############################
resource "aws_lb" "nlb" {
  name               = "k8s-control-plane-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.private_subnet.id]
}

resource "aws_lb_target_group" "target_group" {
  name        = "k8s-target-group"
  port        = 6443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id


  stickiness {
    type    = "source_ip"
    enabled = false
  }
}

resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_lb_target_group_attachment" "attach_master1" {
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.master1.private_ip
  port             = 6443
}

resource "aws_lb_target_group_attachment" "attach_master2" {
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.master2.private_ip
  port             = 6443
}



############################
# Security Groups & keys
############################
resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "allow_all_sg" {
  name        = "DebugSG"
  description = "Allow All DANGEROUS"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



############################
# Networking
############################
resource "aws_vpc" "vpc" {
  cidr_block  = "10.17.0.0/16"

  enable_dns_support  = true
  enable_dns_hostnames = true
}

# Private
resource "aws_subnet" "private_subnet" {
  vpc_id      = aws_vpc.vpc.id
  cidr_block  = "10.17.0.0/19"
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "private_routing_table" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Public
resource "aws_subnet" "public_subnet" {
  vpc_id              = aws_vpc.vpc.id
  cidr_block          = "10.17.32.0/20"
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "public_routing_table" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}
