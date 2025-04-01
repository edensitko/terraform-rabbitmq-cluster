variable "aws_region" {
  default = "us-east-1"
}

variable "ami_id" {
  default = "ami-084568db4383264d4" 
}
variable "availability_zone" {
  default = "us-east-1c"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "root_volume_size" {
  default = 8
}

variable "ebs_volume_size" {
  default = 10
}

variable "ebs_volume_type" {
  default = "gp2"
}

variable "subnet_id" {
  description = "Single subnet ID for EC2"
}

variable "subnet_ids" {
  description = "List of subnet IDs for ASG and ALB"
}

variable "vpc_id" {
  description = "The VPC ID to attach security groups to"
  type        = string

}

