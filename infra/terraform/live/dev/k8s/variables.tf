variable "aws_region" {
  type        = string
  description = "WHY: Region where Terraform will provision AWS resources. WHAT: Region name (e.g., us-east-1)."
  default     = "us-east-1"
}

variable "project" {
  type        = string
  description = "WHY: Consistent naming prefix for resources. WHAT: Prefix used in resource names (e.g., k8s-self-managed)."
  default     = "k8s-self-managed"
}

variable "environment" {
  type        = string
  description = "WHY: Isolate dev from prod in names and state. WHAT: Environment name (dev here)."
  default     = "dev"
}

variable "vpc_cidr" {
  type    = string
  description = "WHY: Each environment needs a different CIDR to avoid overlap. WHAT: VPC CIDR for dev."
  default = "10.20.0.0/16"
}

variable "allowed_ssh_cidrs" {
  type    = list(string)
  description = "SECURITY: WHY: SSH is risky when exposed. WHAT: CIDRs allowed to access port 22. HOW: Keep [] to disable SSH."
  default = []
}

variable "allowed_k8s_api_cidrs" {
  type    = list(string)
  description = "SECURITY: WHAT: Additional CIDRs allowed to access the Kubernetes API (6443). WHY: Default access is VPC-only."
  default = []
}

