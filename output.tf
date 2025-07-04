output "subnet_a_id" {
    value = aws_subnet.subnet_a.id
}


output "subnet_b_id" {
    value = aws_subnet.subnet_b.id
}


output "ami_id" {
    value = data.aws_ami.ubuntu.id
}


output "nat_gateway_a_ip" {
    value = aws_nat_gateway.nat_gateway_a.public_ip
}


output "nat_gateway_ip" {
    value = aws_nat_gateway.nat_gateway_b.public_ip
}

output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}
