# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}
output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}
output "target_group_arn" {
  value = aws_alb_target_group.app_tg.arn
}
output "private_subnet_id_a" {
  value = aws_subnet.private_subnet_a.id
}
output "private_subnet_id_b" {
  value = aws_subnet.private_subnet_b.id
}
output "db_subnet_group_name" {
  value = aws_db_subnet_group.django_db_subnet_group.name
}
