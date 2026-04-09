output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnets" {
  value = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_sg_id" {
  value = aws_security_group.bastion_sg.id
}