variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "employee-eks"
}

variable "vpc_id" {
  description = "VPC ID where EKS will run"
  type        = string
}

variable "private_subnets" {
  description = "Private subnets for worker nodes"
  type        = list(string)
}
