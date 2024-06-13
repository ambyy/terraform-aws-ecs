#Create the VPC, subnet and internet gateway
resource "aws_vpc" "the-vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames=true
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "the-subnet-a" {
  vpc_id     = aws_vpc.the-vpc.id
  cidr_block = var.subnet_cidr_a
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "the-subnet-b" {
  vpc_id     = aws_vpc.the-vpc.id
  cidr_block = var.subnet_cidr_b
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "the-inet-gw" {
  vpc_id = aws_vpc.the-vpc.id

  tags = {
    Name = "inet-gateway"
  }
}

resource "aws_route_table" "the-route-table" {
  vpc_id = aws_vpc.the-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.the-inet-gw.id
  }

  tags = {
    Name = "main-route-table"
  }
}

resource "aws_route_table_association" "the-subnet-a-association" {
  subnet_id      = aws_subnet.the-subnet-a.id
  route_table_id = aws_route_table.the-route-table.id
}

resource "aws_route_table_association" "the-subnet-b-association" {
  subnet_id      = aws_subnet.the-subnet-b.id
  route_table_id = aws_route_table.the-route-table.id
}

#Setup the security group needed
resource "aws_security_group" "the-sec-grp" {
  vpc_id = aws_vpc.the-vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    self = "false"
    description = "any"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-service-sg"
  }
}

# Launch Template
resource "aws_launch_template" "the-launch-template" {
  name = "ecsLaunchTemplate"

  iam_instance_profile {
    name = aws_iam_instance_profile.the-instance-profile.name
  }

  image_id = data.aws_ssm_parameter.ecs-ami-id.value
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.the-sec-grp.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp2"
    }
  }

  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.the-ecs-cluster.name} >> /etc/ecs/ecs.config
EOF
  )
}

# Auto Scaling Group
resource "aws_autoscaling_group" "the-asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  launch_template {
    id = aws_launch_template.the-launch-template.id
  }
  vpc_zone_identifier = [aws_subnet.the-subnet-a.id, aws_subnet.the-subnet-b.id]
}

#Setup the application load balancer
resource "aws_lb" "the-alb" {
  name               = "hello-world-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.the-sec-grp.id]
  subnets            = [aws_subnet.the-subnet-a.id, aws_subnet.the-subnet-b.id]

  tags = {
    Name = "hello-world-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.the-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.the-alb-tg.arn
  }
}

resource "aws_lb_target_group" "the-alb-tg" {
  name     = "hello-world-tg"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.the-vpc.id

  health_check {
    path = "/"
  }

  tags = {
    Name = "hello-world-tg"
  }
}

resource "aws_ecs_cluster" "the-ecs-cluster" {
  name = "hello-world-cluster"
}

resource "aws_ecs_capacity_provider" "the-capacity-provider" {
 name = "hw-capacity-provider"

 auto_scaling_group_provider {
   auto_scaling_group_arn = aws_autoscaling_group.the-asg.arn

   managed_scaling {
     maximum_scaling_step_size = 1000
     minimum_scaling_step_size = 1
     status                    = "ENABLED"
     target_capacity           = 3
   }
 }
}

resource "aws_ecs_cluster_capacity_providers" "the-cluster-capacity-provider" {
 cluster_name = aws_ecs_cluster.the-ecs-cluster.name

 capacity_providers = [aws_ecs_capacity_provider.the-capacity-provider.name]

 default_capacity_provider_strategy {
   base              = 1
   weight            = 100
   capacity_provider = aws_ecs_capacity_provider.the-capacity-provider.name
 }
}

resource "aws_ecs_task_definition" "hw-task" {
  family                   = "hello-world"
  network_mode             = "awsvpc"
  cpu                      = "256"
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = jsonencode([
    {
      name      = "hello-world"
      image     = "tutum/hello-world"
      cpu = 256
      memory = 512
      essential = true,
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol = "tcp"
        }
      ]
    }
  ])
}

#create the ECS service
resource "aws_ecs_service" "main" {
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.the-ecs-cluster.id
  task_definition = aws_ecs_task_definition.hw-task.arn
  desired_count   = 2

  network_configuration {
    subnets          = [aws_subnet.the-subnet-a.id, aws_subnet.the-subnet-b.id]
    security_groups  = [aws_security_group.the-sec-grp.id]
  }

  force_new_deployment = true

  placement_constraints {
    type = "distinctInstance"
  }

  triggers = {
    redeployment = timestamp()
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.the-capacity-provider.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.the-alb-tg.arn
    container_name   = "hello-world"
    container_port   = 80
  }

  depends_on = [aws_autoscaling_group.the-asg]
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "the-instance-role" {
  name = "ecsInstanceRole"
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

resource "aws_iam_instance_profile" "the-instance-profile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.the-instance-role.name
}

resource "aws_iam_role_policy_attachment" "the-ecs-instance-policy" {
  role       = aws_iam_role.the-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

data "aws_ssm_parameter" "ecs-ami-id" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

#Log the load balancer app URL. Paste this URL in the browser to see the output of deployed application
output "app_url" {
  value = aws_lb.the-alb.dns_name
}