output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_id_a" {
  value = aws_subnet.private_subnet_a.id
}

output "private_subnet_id_b" {
  value = aws_subnet.private_subnet_b.id
}

output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "alb_arn" {
  value = aws_alb.app_LoadBalancer.arn
}

output "target_group_arn" {
  value = aws_alb_target_group.app_tg.arn
}