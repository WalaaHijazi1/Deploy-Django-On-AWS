# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}
output "private_subnet_ids" {
  value = [
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_b.id
  ]
}

output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}
output "target_group_arn" {
  value = aws_alb_target_group.app_tg.arn
}
output "db_subnet_group_name" {
  value = aws_db_subnet_group.django_db_subnet_group.name
}

output "private_route_table_id" {
  value = aws_route_table.private_rt.id
}

output "nat_gw" {
  value = aws_nat_gateway.nat_gw
}