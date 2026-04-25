variable "aws_region" {
  type        = string
  description = "WHY: Region where Terraform will provision AWS resources. WHAT: Region name (e.g., us-east-1)."
  default     = "us-east-1"
}

variable "project" {
  type        = string
  description = "WHY: Consistent naming prefix for resources. WHAT: Prefix used in resource names (e.g., k8s-self-managed)."
  default     = "k8s-self-managed-503459125797"
}

variable "environment" {
  type        = string
  description = "WHY: Isolate dev from prod in names and state. WHAT: Environment name (dev here)."
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "WHY: Each environment needs a different CIDR to avoid overlap. WHAT: VPC CIDR for dev."
  default     = "10.20.0.0/16"
}

variable "eks_kubernetes_version" {
  type        = string
  description = "EKS control plane Kubernetes version."
  default     = "1.30"
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "Instance type(s) for the dev managed node group."
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  type        = number
  description = "Desired worker count for dev (use 1 for minimal cost)."
  default     = 1
}

variable "eks_node_min_size" {
  type    = number
  default = 1
}

variable "eks_node_max_size" {
  type    = number
  default = 1
}

variable "eks_endpoint_public_access" {
  type        = bool
  description = "SECURITY: If true, kubectl can reach the API from the internet when combined with eks_public_access_cidrs."
  default     = true
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "SECURITY: CIDRs allowed to use the public EKS endpoint. Tighten for non-dev."
  default     = ["0.0.0.0/0"]
}
