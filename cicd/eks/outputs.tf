# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "region" {
  description = "AWS region"
  value       = var.region
}


output "loxilb_private_ip" {
  description = "loxilb private ip address"
  value       = module.ec2_instance.private_ip
}

output "loxilb_public_ip" {
  description = "loxilb public ip address"
  value       = module.ec2_instance.public_ip
}

output "host_private_ip" {
  description = "host private ip address"
  value       = module.ec2_instance2.private_ip
}

output "host_public_ip" {
  description = "host public ip address"
  value       = module.ec2_instance2.public_ip
}
