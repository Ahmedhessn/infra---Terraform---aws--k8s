## WHY: Self-managed K8s on EC2 needs OS images, networking rules, IAM, and bootstrapping (kubeadm).
## WHAT: This module creates 1 master EC2 + N workers EC2, a security group, and minimal IAM.
## HOW: Use Ubuntu 22.04 AMI, install containerd + kubeadm/kubelet/kubectl via cloud-init, then:
## - master runs `kubeadm init` and publishes a join command to SSM Parameter Store
## - workers read the join command from SSM and execute it
##
## NOTE: This is a "managed self" cluster (self-managed Kubernetes, managed by Terraform).

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "k8s" {
  name_prefix = "${var.name}-sg-"
  vpc_id      = var.vpc_id
  description = "Kubernetes cluster security group"

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    ## WHY: Exposing 6443 to the world is risky.
    ## HOW: Default to VPC-only access; optionally add extra CIDRs via `allowed_k8s_api_cidrs`.
    cidr_blocks = concat([var.vpc_cidr], var.allowed_k8s_api_cidrs)
  }

  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      ## WHY: SSH should be restricted; default is disabled (empty list).
      ## HOW: Only open if you explicitly provide CIDRs.
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  ingress {
    description = "Node-to-node all traffic within SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${var.name}-node-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  ## WHY: Least-privilege needs a precise ARN for the one SSM Parameter we use.
  ## HOW: Parameter ARNs are `...:parameter/<name>` (note no extra slash before the name).
  join_param_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.join_parameter_name}"
}

data "aws_iam_policy_document" "node_min" {
  statement {
    sid     = "EcrRead"
    effect  = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    ## WHY: `GetAuthorizationToken` must be `*` in AWS; the others can be scoped but typically are ok.
    resources = ["*"]
  }

  statement {
    sid    = "SsmCore"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "JoinParamReadWrite"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter"
    ]
    ## WHY: Workers need to read the join command; master needs to write it.
    ## HOW: Scope to exactly one parameter per cluster/environment.
    resources = [local.join_param_arn]
  }
}

resource "aws_iam_policy" "node_min" {
  name_prefix = "${var.name}-node-min-"
  policy      = data.aws_iam_policy_document.node_min.json
}

resource "aws_iam_role_policy_attachment" "node_min" {
  role       = aws_iam_role.node.name
  policy_arn  = aws_iam_policy.node_min.arn
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "${var.name}-node-"
  role        = aws_iam_role.node.name
}

locals {
  ## WHY: We keep bootstrap logic in user-data to avoid manual setup.
  ## WHAT: Install containerd + Kubernetes packages and required sysctls.
  ## HOW: Use official Kubernetes repos (pkgs.k8s.io) and pin version via variables.
  install_script = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    ## WHY: `awscli` is needed to read/write SSM Parameter Store for join command exchange.
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq awscli

    # containerd
    apt-get install -y containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    systemctl restart containerd
    systemctl enable containerd

    # sysctl
    modprobe br_netfilter
    cat >/etc/sysctl.d/99-kubernetes-cri.conf <<SYSCTL
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    SYSCTL
    sysctl --system

    # kubeadm/kubelet/kubectl
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubelet=${K8S_FULL}-* kubeadm=${K8S_FULL}-* kubectl=${K8S_FULL}-*
    apt-mark hold kubelet kubeadm kubectl
    systemctl enable kubelet
  EOF

  k8s_major_minor = join(".", slice(split(".", var.kubernetes_version), 0, 2))
  k8s_full        = var.kubernetes_version
}

resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_master
  ## WHY: Keep master private (no public IP). Access via SSM or via a bastion/VPN if needed.
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  iam_instance_profile        = aws_iam_instance_profile.node.name
  key_name                    = var.ssh_key_name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/user_data_master.sh.tftpl", {
    K8S_MAJOR_MINOR = local.k8s_major_minor
    K8S_FULL        = local.k8s_full
    INSTALL_SCRIPT  = local.install_script
    JOIN_PARAMETER  = var.join_parameter_name
  })

  tags = {
    Name = "${var.name}-master"
    Role = "master"
  }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_worker
  ## HOW: Spread workers across provided subnets (usually private) for multi-AZ resilience.
  subnet_id                   = element(var.subnet_ids, count.index % length(var.subnet_ids))
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  iam_instance_profile        = aws_iam_instance_profile.node.name
  key_name                    = var.ssh_key_name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/user_data_worker.sh.tftpl", {
    K8S_MAJOR_MINOR = local.k8s_major_minor
    K8S_FULL        = local.k8s_full
    INSTALL_SCRIPT  = local.install_script
    JOIN_PARAMETER  = var.join_parameter_name
  })

  tags = {
    Name = "${var.name}-worker-${count.index + 1}"
    Role = "worker"
  }
}

