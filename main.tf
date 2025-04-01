provider "aws" {
  region = var.aws_region
}

module "ec2_instance" {
  source              = "./ec2-module"
  ami_id              = var.ami_id
  instance_type       = var.instance_type
  root_volume_size    = var.root_volume_size
  ebs_volume_size     = var.ebs_volume_size
  ebs_volume_type     = var.ebs_volume_type
  availability_zone   = var.availability_zone
  subnet_id           =  var.subnet_id
  subnet_ids          = var.subnet_ids
  vpc_id              = var.vpc_id        
}