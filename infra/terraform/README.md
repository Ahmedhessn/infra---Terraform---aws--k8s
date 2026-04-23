## Terraform layout (best practice)

## Why this structure?

- **WHY**: You asked for *remote state per environment* + *modules* + *least privilege* + *restricted SSH*.
- **WHAT**: We use a standard “**modules** + **live environments**” layout:
  - `modules/` contains reusable building blocks (no environment-specific values inside).
  - `live/dev` and `live/prod` are thin roots that pass env variables into modules.
- **HOW**: You run `bootstrap` once per env to create S3+DynamoDB, then initialize the backend for the env’s `k8s` stack.

- **`modules/`**: reusable building blocks
  - `remote_state`: S3 + DynamoDB for Terraform remote state/locking
  - `vpc`: VPC + public/private subnets + NAT
  - `ecr`: ECR repo + lifecycle policy
  - `k8s_self_managed`: 1 master + N workers (kubeadm) with SSM-based join (no SSH required)
- **`live/`**: per-environment roots (thin wrappers)
  - `live/dev/bootstrap`: remote state for dev
  - `live/dev/k8s`: VPC + ECR + K8s for dev
  - `live/prod/bootstrap`: remote state for prod
  - `live/prod/k8s`: VPC + ECR + K8s for prod

## Remote state per environment

Each environment has its own:
- S3 bucket: `${project}-${env}-tf-state`
- DynamoDB table: `${project}-${env}-tf-locks`

### WHY S3 + DynamoDB?

- **WHY**: Local state breaks as soon as you have more than one person or CI applying.
- **WHAT**:
  - **S3** stores the state file.
  - **DynamoDB** stores the lock record (prevents concurrent `apply`).
- **HOW**: Terraform backend `s3` uses both when you configure `bucket`, `key`, and `dynamodb_table`.

### Create remote state (dev)

From `infra/terraform/live/dev/bootstrap`:

```bash
terraform init
terraform apply
```

Read outputs:
- `remote_state.bucket`
- `remote_state.dynamodb_table`

### Configure backend for dev k8s

Copy `infra/terraform/live/dev/k8s/backend.hcl.example` to `backend.hcl` and replace:
- `bucket`
- `dynamodb_table`

Then from `infra/terraform/live/dev/k8s`:

```bash
terraform init -backend-config=backend.hcl
terraform apply
```

Repeat the same steps for `prod`.

## Variables per environment (dev/prod)

- **WHY**: dev and prod should not share CIDRs, state, or security exceptions.
- **WHAT**: Each env has its own `variables.tf` defaults:
  - `live/dev/k8s/variables.tf`
  - `live/prod/k8s/variables.tf`
- **HOW**: Override safely using:
  - `terraform apply -var="allowed_ssh_cidrs=[\"x.x.x.x/32\"]"`
  - or add a `dev.tfvars`/`prod.tfvars` file and pass `-var-file=...`

## Security defaults

- **SSH** is disabled by default (`allowed_ssh_cidrs = []`)
- **Kubernetes API (6443)** is restricted to **VPC CIDR only** by default. You can add extra CIDRs via `allowed_k8s_api_cidrs`.
- **IAM least privilege**:
  - nodes get minimal ECR pull permissions
  - SSM core permissions (Session Manager)
  - scoped access to one SSM Parameter to publish/read the kubeadm join command

### HOW to enable SSH (only if you really need it)

- **WHY**: SSH is hard to audit and often left open by mistake.
- **WHAT**: This project defaults to using **SSM Session Manager** instead of SSH.
- **HOW**: If you must enable SSH, set (example):

```bash
terraform apply -var='allowed_ssh_cidrs=["203.0.113.10/32"]'
```

## CI/CD (GitHub Actions + OIDC)

### What you need in AWS (one-time)

1) **IAM OIDC provider**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

2) **IAM role for GitHub Actions**
- Trust policy must restrict to your repo and branch (recommended: `main`)
- Attach permissions that allow Terraform to manage:
  - S3/DynamoDB (remote state)
  - VPC/EC2/IAM/ECR/SSM (cluster stack)

### What you need in GitHub (repo settings)

Add the following **Repository Variables**:
- `AWS_REGION` (example: `us-east-1`)
- `TF_STATE_BUCKET_DEV` (bucket name created by `live/dev/bootstrap`)
- `TF_LOCK_TABLE_DEV` (DynamoDB table created by `live/dev/bootstrap`)

Add the following **Repository Secret**:
- `AWS_ROLE_ARN` (the IAM role ARN you created for GitHub Actions)

### Workflows included

- **PRs**: `.github/workflows/terraform-dev-plan.yml`
  - runs fmt/validate/plan for `infra/terraform/live/dev/k8s`
- **main branch**: `.github/workflows/terraform-dev-apply.yml`
  - runs apply for `infra/terraform/live/dev/k8s`


