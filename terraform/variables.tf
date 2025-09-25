variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "otms"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr_a" {
  type    = string
  default = "10.10.1.0/24"
}

variable "public_subnet_cidr_b" {
  type    = string
  default = "10.10.2.0/24"
}

variable "private_subnet_cidr_a" {
  type    = string
  default = "10.10.3.0/24"
}

variable "private_subnet_cidr_b" {
  type    = string
  default = "10.10.4.0/24"
}

variable "app_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "scylla_instance_type" {
  type    = string
  default = "t3.small"
}

variable "redis_instance_type" {
  type    = string
  default = "t3.small"
}

variable "app_image" {
  type        = string
  description = "Container image"
  default     = "employee-api:latest"
}

variable "private_key_path" {
  type        = string
  description = "Path to SSH private key"
}
