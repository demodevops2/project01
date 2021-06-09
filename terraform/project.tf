provider "aws" {
  
  region     = "${var.region}"
#  access_key = "${var.access_key}"
#  secret_key = "${var.secret_key}"
}

# Create a VPC to launch our instances into.
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-example-vpc"
  }
}

# Create an internet gateway to give our subnet access to the outside world.
resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "terraform-example-internet-gateway"
  }
}

# Grant the VPC internet access on its main route table.
resource "aws_route" "route" {
  route_table_id         = "${aws_vpc.vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gateway.id}"
}

# Create subnets in each availability zone to launch our instances into, each with address blocks within the VPC.
resource "aws_subnet" "main" {
  count                   = "${length(data.aws_availability_zones.available.names)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${element(data.aws_availability_zones.available.names, count.index)}"

  tags = {
    Name = "public-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

# Create a security group in the VPC which our instances will belong to.
resource "aws_security_group" "default" {
  name        = "terraform_security_group"
  description = "Terraform example security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  # Allow outbound internet access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-example-security-group"
  }
}

# Create an application load balancer security group.
resource "aws_security_group" "alb" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-example-alb-security-group"
  }
}

# Create a new application load balancer.
resource "aws_alb" "alb" {
  name            = "terraform-example-alb"
  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = aws_subnet.main.*.id

  tags = {
    Name = "terraform-example-alb"
  }
}

# Create a new target group for the application load balancer.
resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"

  stickiness {
    type = "lb_cookie"
  }

  # Alter the destination of the health check to be the default page.
  health_check {
    path = "/"
    port = 80
  }
}

# Create a new application load balancer listener for HTTP.
resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.group.arn}"
    type             = "forward"
  }
}

# Crate LC for autoscaling group
resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = var.ami # Amazon Linux 2 AMI (HVM), SSD Volume Type
  instance_type = var.instance_type
#  key_name = var.keyname
  iam_instance_profile = "${aws_iam_instance_profile.test_profile.name}"
  security_groups = ["${aws_security_group.alb.id}"]
  associate_public_ip_address = true

  user_data = filebase64("${path.module}/example.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# Create a autoscaling group
resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"
  min_size             = 1
  desired_capacity     = 2
  max_size             = 4
  
  health_check_type    = "ELB"
#  load_balancers = "${aws_alb_target_group.group.arn}"
 
#  target_group_arns = aws_alb_target_group.group.arn
  launch_configuration = aws_launch_configuration.web.name
  vpc_zone_identifier       = aws_subnet.main.*.id

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}

# Create a new ALB Target Group attachment
resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.web.id
  alb_target_group_arn   = aws_alb_target_group.group.arn
}
