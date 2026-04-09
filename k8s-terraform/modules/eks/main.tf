module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.32"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # TODO: restrict to your IP e.g. ["<your-ip>/32"]
  cluster_endpoint_private_access = true

  # Grant cluster admin access to the IAM identity running Terraform
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      key_name       = "my-eks-key"
    }
  }
}

resource "aws_security_group_rule" "allow_bastion_ssh" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.bastion_sg_id
  security_group_id        = module.eks.node_security_group_id
}