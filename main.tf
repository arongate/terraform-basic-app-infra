terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.74.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "eu-west-3"
}

resource "aws_vpc" "basic_app" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "vpc-basic_app"
    Environment = "training"
  }
}

resource "aws_subnet" "basic_app" {
  count             = length(var.basic_app_subnets)
  vpc_id            = aws_vpc.basic_app.id
  cidr_block        = var.basic_app_subnets[count.index].cidr_block
  availability_zone = var.basic_app_subnets[count.index].availability_zone

  tags = {
    Name        = var.basic_app_subnets[count.index].name
    Environment = "training"
  }
}


# load balancer
resource "aws_security_group" "lb_basic_app" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.basic_app.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.basic_app.cidr_block]
  }
  ingress {
    description = "HTTPS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.basic_app.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name        = "sg-basic_app_lb"
    Environment = "training"
  }
}

resource "aws_s3_bucket" "basic_app-lb-logs" {
  bucket = var.lb_logs_s3bucket
  acl    = "private"

  tags = {
    Name        = "butcket-lb-basic_app"
    Environment = "training"
  }
}

resource "aws_s3_bucket_policy" "allow_access_to_basic_app_lb" {
  bucket = aws_s3_bucket.basic_app-lb-logs.id
  policy = data.aws_iam_policy_document.allow_access_to_basic_app_lb.json
}

# Get the current caller identity
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "allow_access_to_basic_app_lb" {
  statement {
    actions = [
      "s3:PutObject",
    ]
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::009996457667:root"]
    }
    resources = [
      "arn:aws:s3:::${var.lb_logs_s3bucket}/basic_app-lb/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]
  }
  statement {
    actions = [
      "s3:PutObject",
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [
      "arn:aws:s3:::${var.lb_logs_s3bucket}/basic_app-lb/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]
    condition {
      test     = "StringEquals"
      values   = ["bucket-owner-full-control"]
      variable = "s3:x-amz-acl"
    }
  }
  statement {
    actions = [
      "s3:GetBucketAcl"
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [
      "arn:aws:s3:::${var.lb_logs_s3bucket}"
    ]
  }
}

resource "aws_internet_gateway" "basic_app" {
  vpc_id = aws_vpc.basic_app.id

  tags = {
    Name        = "basicapp-igw"
    Environment = "training"
  }
}


resource "aws_lb" "basic_app" {
  name               = "basicapp-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_basic_app.id]
  subnets            = [for subnet in aws_subnet.basic_app : subnet.id]

  access_logs {
    bucket  = aws_s3_bucket.basic_app-lb-logs.bucket
    prefix  = "basic_app-lb"
    enabled = true
  }

  tags = {
    Name        = "basicapp-lb"
    Environment = "training"
  }

  depends_on = [
    aws_internet_gateway.basic_app,
  ]
}

resource "aws_lb_target_group" "basic_app" {
  name     = "basicapp-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.basic_app.id
}

resource "aws_lb_listener" "basic_app" {
  load_balancer_arn = aws_lb.basic_app.arn
  port              = "80"
  protocol          = "HTTP"
  #   ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.basic_app.arn
  }
}

# autoscalling
resource "aws_launch_template" "basic_app" {
  name_prefix                          = "basic_app"
  image_id                             = "ami-0d1533530bc7a81ba"
  instance_type                        = "t2.micro"
  instance_initiated_shutdown_behavior = "terminate"
  #   user_data                            = filebase64("${path.module}/init.sh")

  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "basicapp"
      Environment = "training"
    }
  }
}

resource "aws_autoscaling_group" "basic_app" {
  name                = "basicapp-asg"
  vpc_zone_identifier = [for subnet in aws_subnet.basic_app : subnet.id]
  target_group_arns   = [aws_lb_target_group.basic_app.arn]
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  force_delete        = true


  launch_template {
    id      = aws_launch_template.basic_app.id
    version = "$Latest"
  }
  tag {
    key                 = "Environment"
    value               = "training"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
}
