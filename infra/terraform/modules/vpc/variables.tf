variable "name" {
  type        = string
  description = "Name prefix for VPC resources."
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR."
}

variable "az_count" {
  type        = number
  description = "Number of AZs to span."
  default     = 2
}

