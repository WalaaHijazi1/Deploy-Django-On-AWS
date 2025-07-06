output "subnet_a_id" {
    value = aws_subnet.subnet_a.id
}


output "subnet_b_id" {
    value = aws_subnet.subnet_b.id
}


output "ami_id" {
    value = data.aws_ami.ubuntu.id
}


output "nat_gateway_ip" {
    value = aws_nat_gateway.nat_gw.public_ip
}

output "private_subnet_id_a" {
  value = aws_subnet.private_subnet_a.id
}

output "private_subnet_id_b" {
  value = aws_subnet.private_subnet_b.id
}

output "vpc_id" {
  value = aws_vpc.main.id
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

output "private_subnet_ids" {
  value = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}