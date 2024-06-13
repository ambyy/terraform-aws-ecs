# Required variables

variable "region" {
  description   = "region to use for AWS resources"
  type          = string
  default       = "ap-south-1"
}

variable "vpc_cidr" {
  description   = "CIDR range for created VPC"
  type          = string
  default       = "10.0.0.0/16"
}

variable "subnet_cidr_a" {
  description   = "CIDR range for subnet within VPC"
  type          = string
  default       = "10.0.1.0/24"
}

variable "subnet_cidr_b" {
  description   = "CIDR range for subnet within VPC"
  type          = string
  default       = "10.0.2.0/24"
}

variable "aws_access_key_id" {
  type          = string
  sensitive     = true
}

variable "aws_secret_access_key" {
  type          = string
  sensitive     = true
}

variable "aws_session_token" {
  type          = string
  sensitive     = true
}