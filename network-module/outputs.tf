output "vpc_id" {
  value = aws_vpc.main_vpc.id
}

output "subnet_ids" {
  value = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]
}



