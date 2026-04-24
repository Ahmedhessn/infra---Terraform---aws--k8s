## =========================
## Root stack: live/dev/k8s
## =========================
## WHY: This is the root module for the dev environment. Terraform starts here when you run:
##      `terraform plan/apply` inside this folder.
## WHAT: It builds the full dev infrastructure:
##      - VPC (network)
##      - ECR (container registry)
##      - Self-managed Kubernetes on EC2 (1 master + workers)
## HOW: This file is wiring only: it composes modules from `infra/terraform/modules/*`.

locals {
  ## WHY: Consistent naming across all resources (searchability, governance, isolation).
  ## HOW: Resource name prefix becomes `${project}-${environment}`.
  name = "${var.project}-${var.environment}"
}

module "vpc" {
  ## WHAT: Builds the network (VPC + subnets + NAT + routes).
  ## FROM WHERE: Code lives in `infra/terraform/modules/vpc`.
  source = "../../../modules/vpc"

  ## HOW: Pass a name prefix and a dev-specific CIDR block.
  name       = local.name
  cidr_block = var.vpc_cidr
}

module "ecr" {
  ## WHAT: Creates an ECR repository + lifecycle policy.
  ## FROM WHERE: `infra/terraform/modules/ecr`.
  source = "../../../modules/ecr"

  ## WHY: One repository per environment (isolation) with a clear name.
  name = "${local.name}-apps"
}

module "k8s" {
  ## WHAT: Creates self-managed K8s: EC2 master + workers + IAM + SG + bootstrap scripts.
  ## FROM WHERE: `infra/terraform/modules/k8s_self_managed`.
  source = "../../../modules/k8s_self_managed"

  ## HOW: Attach the cluster to the network created above.
  name       = local.name
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = var.vpc_cidr
  subnet_ids = module.vpc.private_subnet_ids

  ## SECURITY: SSH is disabled by default (empty list). Only enable if necessary, and prefer /32.
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  ## SECURITY: The API (6443) is VPC-only by default; you can add external CIDRs (e.g., your public IP).
  allowed_k8s_api_cidrs = var.allowed_k8s_api_cidrs

  ## COST: Use Spot for both master and workers (cheaper, but can be interrupted).
  ## NOTE: The control-plane is memory sensitive; keep master on-demand to avoid interruptions.
  master_market_type = "on-demand"
  worker_market_type = "spot"

  ## STABILITY: t3.medium can be tight for control-plane components; use a larger master.
  instance_type_master = "t3.large"

  ## SCALE: Number of worker nodes for dev.
  worker_count = 2

  ## WHY: The master writes `kubeadm join` here, and workers read it from the same place (no SSH required).
  ## HOW: Use an env-specific parameter name to avoid any dev/prod overlap.
  join_parameter_name = "/${local.name}/kubeadm/join"
}

