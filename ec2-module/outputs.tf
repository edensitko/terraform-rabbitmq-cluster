output "launch_template_id" {
  value = aws_launch_template.rabbitmq_template.id
}

output "asg_name" {
  value = aws_autoscaling_group.rabbitmq_asg.name
}

output "alb_dns_name" {
  value = aws_lb.rabbitmq_alb.dns_name
}

output "alb_arn" {
  value = aws_lb.rabbitmq_alb.arn
}
