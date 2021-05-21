##################################################################################
# RESOURCE 
##################################################################################

# Networking
resource "aws_default_vpc" "default" {}

resource "aws_vpc" "vpc" {
  cidr_block = var.network_address_space[terraform.workspace]

  tags = {
      Name = "${local.env_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.env_name}-igw"
  }
}

resource "aws_subnet" "subnet" {
  count = var.subnet_count[terraform.workspace]
  cidr_block = cidrsubnet(var.network_address_space[terraform.workspace], 8, count.index)
  vpc_id = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
      Name = "${local.env_name}-subnet-${count.index+1}"
  }
}

# Routing
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route { 
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.env_name}-rtb"
  }
}

resource "aws_route_table_association" "rtba-subnet" {
  count = var.subnet_count[terraform.workspace]
  subnet_id = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.rtb.id
}

# Security groups
resource "aws_security_group" "elb-sg" {
  name = "${local.env_name}-elb-sg"
  vpc_id = aws_vpc.vpc.id

  #Allow HTTP request from anywhere
  ingress {
      from_port     = 80
      to_port       = 80
      protocol      = "tcp"
      cidr_blocks   = ["0.0.0.0/0"]
  }

  #Allow all for outbound connection
  egress {
      from_port     = 0 
      to_port       = 0
      protocol      = "-1"
      cidr_blocks   = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.env_name}-elb-sg"
  }
}

resource "aws_security_group" "instance-sg" {
  name = "${local.env_name}-instance-sg"
  vpc_id = aws_vpc.vpc.id

  #Allow HTTP request from anywhere
  ingress {
      from_port     = 3000
      to_port       = 3000
      protocol      = "tcp"
      cidr_blocks   = ["0.0.0.0/0"]
  }

  #Allow SSH from anywhere
  ingress {
      from_port     = 22
      to_port       = 22
      protocol      = "tcp"
      cidr_blocks   = ["0.0.0.0/0"]
  }

  #Allow all for outbound connection
  egress {
      from_port = 0 
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.env_name}-instance-sg"
  }
}

resource "aws_security_group" "prototype-sg" {
  name        = "${local.env_name}-prototype-sg"
  description = "Allow only ssh"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.env_name}-prototype-sg"
  }
}

# Launch Configuration
resource "aws_launch_configuration" "web-launch-template" {
  name             = "${local.env_name}-web-launch-template"
  image_id         = aws_ami_from_instance.web-ami.id
  instance_type    = var.instance_size[terraform.workspace]
  security_groups  = [aws_security_group.instance-sg.id]

  user_data = <<-EOF
  #!/bin/bash
  su ec2-user
  cd /home/ec2-user/NPA-CloudStorage
  id > test.txt
  sudo npm install pm2 -g
  pm2 start npm -- start
  ls
  EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Autoscaling Group
resource "aws_autoscaling_group" "asg" {
  name = "${local.env_name}-asg"
  desired_capacity = var.instance_count[terraform.workspace]
  max_size = var.instance_count["Max"]
  min_size = var.instance_count["Min"]
  launch_configuration = aws_launch_configuration.web-launch-template.name

  vpc_zone_identifier = aws_subnet.subnet[*].id

  target_group_arns = [aws_lb_target_group.asg-tg.arn]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key = "Name"
    propagate_at_launch = true
    value = "${local.env_name}-server-clone"
  }
}

# Load Balancer Target Group
resource "aws_lb_target_group" "asg-tg" {
  name = "${local.env_name}-asg-target-group"
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    path = "/"
    port = 3000
    protocol = "HTTP"
    matcher = "200"
    interval = 5 
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

# Load balancer
resource "aws_elb" "web-elb" {
  name = "${local.env_name}-web-elb"

  subnets = aws_subnet.subnet[*].id
  security_groups = [aws_security_group.elb-sg.id]

  listener {
    instance_port       = 3000
    instance_protocol   = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }

  tags = {
    Name = "${local.env_name}-elb"
  }
}

# Attach autoscaling group to load balancer
resource "aws_autoscaling_attachment" "asg-attach-elb" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  elb                    = aws_elb.web-elb.id
}

# Instance : Prototype instance
resource "aws_instance" "web-instance-prototype" {
  ami                       = data.aws_ami.aws-linux.id
  instance_type             = var.instance_size[terraform.workspace]
  key_name                  = var.key_name
  vpc_security_group_ids    = [aws_security_group.prototype-sg.id]

  tags = {
    Name = "${local.env_name}-server-prototype"
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)
  } 

  provisioner "remote-exec" {
    inline = [
      "curl -sL https://rpm.nodesource.com/setup_14.x | sudo bash -",
      "sudo yum install -y nodejs",
      "sudo yum install -y git",
      "git clone https://github.com/CokeFung/NPA-CloudStorage.git",
      "cd NPA-CloudStorage",
      "touch .env",
      "echo \"REACT_APP_AWS_ACCESS_KEY_ID=${var.aws_access_key}\" >> .env",
      "echo \"REACT_APP_AWS_SECRET_ACCESS_KEY=${var.aws_secret_key}\" >> .env",
      "echo \"REACT_APP_S3_REGION=${var.region}\" >> .env",
      "echo \"REACT_APP_S3_BUCKET=${var.bucket_name}\" >> .env",
      "echo \"REACT_APP_SERVER_NAME=${local.env_name}-server\" >> .env",
      "npm install",
      "ls -la",
    ]
  }
}

# AMI : create AMI from prototype instance
resource "aws_ami_from_instance" "web-ami" {
  name = "${local.env_name}-web-ami"
  source_instance_id = aws_instance.web-instance-prototype.id
  snapshot_without_reboot = true
  
  tags = {
    Name = "${local.env_name}-web-ami"
  }
}
