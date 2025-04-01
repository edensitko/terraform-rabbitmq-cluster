# ---------------------
# VPC Module  
# ---------------------
resource "aws_security_group" "rabbitmq_sg" {
  name        = "rabbitmq_sg"
  description = "Allow RabbitMQ UI and AMQP"
  vpc_id      = var.vpc_id

ingress {
  from_port   = 81
  to_port     = 81
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
}

# ---------------------
# Target Group & Load Balancer
# ---------------------
resource "aws_lb_target_group" "rabbitmq_tg" {
  name     = "rabbitmq-cluster-tg"
  port     = 15672
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

resource "aws_lb" "rabbitmq_alb" {
  name               = "rabbitmq-cluster-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.rabbitmq_sg.id]
  subnets            = var.subnet_ids

  tags = {
    Name = "RabbitMQClusterALB"
  }
}

resource "aws_lb_listener" "rabbitmq_listener" {
  load_balancer_arn = aws_lb.rabbitmq_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq_tg.arn
  }
}

# ---------------------
# Launch Template 
# ---------------------
resource "aws_launch_template" "rabbitmq_template" {
  name_prefix   = "rabbitmq-cluster-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  user_data = base64encode(<<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1
    set -x

    apt update -y
    apt install -y docker.io curl
    systemctl start docker
    systemctl enable docker

    CLUSTER_COOKIE="CLUSTER_COOKIE_SECRET"
    RABBITMQ_NODENAME="rabbit@$(hostname -s)"
    echo "$CLUSTER_COOKIE" > /var/lib/rabbitmq/.erlang.cookie
    chmod 400 /var/lib/rabbitmq/.erlang.cookie
    chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie

    docker rm -f rabbitmq || true

    docker network create rabbitmq-net || true

    docker run -d \
      --hostname $(hostname -s) \
      --name rabbitmq \
      --network rabbitmq-net \
      -e RABBITMQ_ERLANG_COOKIE="$CLUSTER_COOKIE" \
      -e RABBITMQ_NODENAME=$RABBITMQ_NODENAME \
      -e RABBITMQ_DEFAULT_USER=admin \
      -e RABBITMQ_DEFAULT_PASS=admin123 \
      -p 5672:5672 -p 15672:15672 \
      rabbitmq:3.12-management

    # Cluster join logic
    PRIMARY_NODE_HOSTNAME="rabbitmq-1"
    MY_HOSTNAME="$(hostname -s)"
    if [ "$MY_HOSTNAME" != "$PRIMARY_NODE_HOSTNAME" ]; then
      sleep 30
      docker exec rabbitmq rabbitmqctl stop_app
      docker exec rabbitmq rabbitmqctl join_cluster rabbit@$PRIMARY_NODE_HOSTNAME
      docker exec rabbitmq rabbitmqctl start_app
    fi
  EOF
  )

  vpc_security_group_ids = [aws_security_group.rabbitmq_sg.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.root_volume_size
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "RabbitMQClusterNode"
    }
  }
}


# ---------------------
# Auto Scaling Group
# ---------------------
resource "aws_autoscaling_group" "rabbitmq_asg" {
  name                      = "rabbitmq-cluster-asg"
  min_size                  = 3
  max_size                  = 3
  desired_capacity          = 3
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [aws_lb_target_group.rabbitmq_tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.rabbitmq_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "RabbitMQClusterInstance"
    propagate_at_launch = true
  }
}


resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.rabbitmq_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.rabbitmq_asg.name
}

# ---------------------
# CloudWatch Alarm for Scale Up
# ---------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "This metric monitors high CPU usage"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.rabbitmq_asg.name
  }
}

# CloudWatch Alarm for Scale Down
resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "This metric monitors low CPU usage"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.rabbitmq_asg.name
  }
}
