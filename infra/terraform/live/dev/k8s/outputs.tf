## WHY: Outputs make it easy to see "what was created" (IDs, URLs, IPs) without opening AWS Console.
## WHAT: We return organized outputs as groups (network/ecr/k8s) instead of many scattered outputs.

output "network" {
  ## WHAT: Network details (VPC + subnets) created by the VPC module.
  value = {
    vpc_id             = module.vpc.vpc_id
    private_subnet_ids = module.vpc.private_subnet_ids
    public_subnet_ids  = module.vpc.public_subnet_ids
  }
}

output "ecr" {
  ## WHAT: ECR repository details used for docker push/pull.
  value = {
    repository_url = module.ecr.repository_url
    repository_arn = module.ecr.repository_arn
  }
}

output "k8s" {
  ## WHAT: Cluster details (security group + instances) for debugging and operational access.
  value = {
    security_group_id = module.k8s.security_group_id
    instances         = module.k8s.instances
  }
}

