locals {
  environment = var.environment_name
  service     = var.service_name
  region      = var.aws_region

  env  = local.service
  name = "${local.environment}-${local.service}"

  # Mapping
  cluster_version            = var.cluster_version
  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix
  eks_admin_role_name        = var.eks_admin_role_name
  workload_repo_path         = var.workload_repo_path
  workload_repo_url          = var.workload_repo_url
  workload_repo_revision     = var.workload_repo_revision
  workload_repo_secret       = var.workload_repo_secret

  gitops_bridge_repo_url      = var.gitops_bridge_repo_url
  gitops_bridge_repo_revision = var.gitops_bridge_repo_revision

  # Route 53 Ingress Weights
  # argocd_route53_weight      = var.argocd_route53_weight
  # route53_weight             = var.route53_weight
  # ecsfrontend_route53_weight = var.ecsfrontend_route53_weight

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  aws_addons = {
    enable_cert_manager          = true
    enable_aws_ebs_csi_resources = true # generate gp2 and gp3 storage classes for ebs-csi
    #enable_aws_efs_csi_driver                    = true
    #enable_aws_fsx_csi_driver                    = true
    enable_aws_cloudwatch_metrics = true
    #enable_aws_privateca_issuer                  = true
    #enable_cluster_autoscaler                    = true
    #enable_external_dns                          = true
    enable_external_secrets             = true
    enable_aws_load_balancer_controller = true
    #enable_fargate_fluentbit                     = true
    enable_aws_for_fluentbit = true
    #enable_aws_node_termination_handler          = true
    enable_karpenter = true
    #enable_velero                                = true
    #enable_aws_gateway_api_controller            = true
    #enable_aws_secrets_store_csi_driver_provider = true
  }
  oss_addons = {
    #enable_argo_rollouts                         = true
    #enable_argo_workflows                        = true
    #enable_cluster_proportional_autoscaler       = true
    #enable_gatekeeper                            = true
    #enable_gpu_operator                          = true
    enable_ingress_nginx = true
    enable_kyverno       = true
    #enable_kube_prometheus_stack                 = true
    enable_metrics_server = true
    #enable_prometheus_adapter                    = true
    #enable_secrets_store_csi_driver              = true
    #enable_vpa                                   = true
    #enable_foo                                   = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }
  addons = merge(local.aws_addons, local.oss_addons, { kubernetes_version = local.cluster_version })

  #----------------------------------------------------------------
  # GitOps Bridge, define metadatas to pass from Terraform to ArgoCD
  #----------------------------------------------------------------

  addons_metadata = merge(
    module.eks_blueprints_addons.gitops_metadata, # eks blueprints addons automatically expose metadatas
    {
      aws_cluster_name                        = module.eks.cluster_name
      aws_region                              = local.region
      aws_account_id                          = data.aws_caller_identity.current.account_id
      aws_vpc_id                              = data.aws_vpc.vpc.id
      cluster_endpoint                        = module.eks.cluster_endpoint
      env                                     = local.env
      argocd_password                         = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      aws_secret_manager_workload_secret_name = local.workload_repo_secret
      workload_repo_path                      = local.workload_repo_path
      workload_repo_url                       = local.workload_repo_url
      workload_repo_revision                  = local.workload_repo_revision
      gitops_bridge_repo_url                  = local.gitops_bridge_repo_url
      gitops_bridge_repo_revision             = local.gitops_bridge_repo_revision

      target_group_arn = local.service == "blue" ? data.aws_lb_target_group.tg_blue.arn : data.aws_lb_target_group.tg_green.arn # <-- Add this line
      #aws_security_group_ingress_nginx = aws_security_group.ingress_nginx.id
      # argocd_route53_weight = local.argocd_route53_weight
      # route53_weight = local.route53_weight
    }
  )

  #---------------------------------------------------------------
  # Manifests for bootstraping the cluster for addons & workloads
  #---------------------------------------------------------------
  argocd_bootstrap_app_of_apps = {
    addons    = file("${path.module}/../../bootstrap/addons.yaml")
    workloads = file("${path.module}/../../bootstrap/workloads.yaml")
  }

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

################################################################################
# Datas for External Load Balancer
################################################################################
data "aws_lb_target_group" "tg_blue" {
  name = "${local.environment}-tg-blue"
}

data "aws_lb_target_group" "tg_green" {
  name = "${local.environment}-tg-green"
}

data "aws_lb" "alb" {
  name = "${local.environment}-alb"
}

data "aws_security_group" "alb_sg" {
  count = 1
  id    = tolist(data.aws_lb.alb.security_groups)[count.index]
}
