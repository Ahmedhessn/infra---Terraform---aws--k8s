## =========================
## Root stack: live/dev/k8s
## =========================
## WHY: Dev environment entrypoint for Terraform in this folder.
## WHAT: VPC + ECR + **EKS** (managed control plane, one managed worker node for dev).
## HOW: Composes `vpc`, `ecr`, and `eks` modules.

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${local.name}-eks"
  ## WHY: EKS control plane expects subnets in multiple AZs; include public + private from the VPC module.
  eks_subnet_ids = sort(concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids))
}

module "vpc" {
  source = "../../../modules/vpc"

  name       = local.name
  cidr_block = var.vpc_cidr
}

module "ecr" {
  source = "../../../modules/ecr"

  name = "${local.name}-apps"
}

module "ecr_mysql" {
  source = "../../../modules/ecr"
  name   = "${local.name}-mysql"
}

module "ecr_memcached" {
  source = "../../../modules/ecr"
  name   = "${local.name}-memcached"
}

module "ecr_nginx" {
  source = "../../../modules/ecr"
  name   = "${local.name}-nginx"
}

module "ecr_rabbitmq" {
  source = "../../../modules/ecr"
  name   = "${local.name}-rabbitmq"
}

module "ecr_tomcat" {
  source = "../../../modules/ecr"
  name   = "${local.name}-tomcat"
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name           = local.cluster_name
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  cluster_subnet_ids     = local.eks_subnet_ids
  kubernetes_version     = var.eks_kubernetes_version
  node_instance_types    = var.eks_node_instance_types
  node_desired_size      = var.eks_node_desired_size
  node_min_size          = var.eks_node_min_size
  node_max_size          = var.eks_node_max_size
  endpoint_public_access = var.eks_endpoint_public_access
  public_access_cidrs    = var.eks_public_access_cidrs

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
