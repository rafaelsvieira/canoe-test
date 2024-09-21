data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_ssm_parameter" "ecs_optimized_ami" {
    name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

locals {
    azs = slice(data.aws_availability_zones.available.names, 0, 3)
    tags = {
        Company     = "Canoe"
        Environment = var.environment
    }
    container_name = "canoe-api"
    user_data = <<-EOT
        #!/bin/bash

        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${var.cluster_name}
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
        EOF
    EOT
}

##############################################
# VPC and subnets
##############################################

module "vpc" {
    source    = "terraform-aws-modules/vpc/aws"
    version   = "~> 5.13.0"

    tags  = local.tags
    azs   = local.azs
    name  = var.vpc_name
    cidr  = var.vpc_cidr

    enable_nat_gateway = true
    single_nat_gateway = true

    private_subnets = [for index, v in local.azs : cidrsubnet(var.vpc_cidr, 3, index)]
    public_subnets  = [for index, v in local.azs : cidrsubnet(var.vpc_cidr, 3, index + 3)]
}

##############################################
# ECR
##############################################

module "ecr" {
    source = "terraform-aws-modules/ecr/aws"
    version   = "~> 2.3.0"

    tags                    = local.tags
    repository_name         = var.ecr_name
    repository_force_delete = true

    create_lifecycle_policy           = true

    repository_lifecycle_policy = jsonencode({
        rules = [
            {
                rulePriority = 1,
                description  = "Keep last 5 images",
                selection = {
                    tagStatus     = "tagged",
                    tagPrefixList = ["v"],
                    countType     = "imageCountMoreThan",
                    countNumber   = 5
                },
                action = {
                    type = "expire"
                }
            }
        ]
    })
}

##############################################
# ALB
##############################################

module "alb" {
    source  = "terraform-aws-modules/alb/aws"
    version = "~> 9.0"

    name = "alb-${var.cluster_name}"

    load_balancer_type = "application"

    vpc_id  = module.vpc.vpc_id
    subnets = module.vpc.public_subnets

    # For example only
    enable_deletion_protection = false

    # Security Group
    security_group_ingress_rules = {
        all_http = {
            from_port   = 80
            to_port     = 80
            ip_protocol = "tcp"
            cidr_ipv4   = "0.0.0.0/0"
        }

        all_https = {
            from_port   = 443
            to_port     = 443
            ip_protocol = "tcp"
            description = "HTTPS web traffic"
            cidr_ipv4   = "0.0.0.0/0"
        }
    }

    security_group_egress_rules = {
        all = {
            ip_protocol = "-1"
            cidr_ipv4   = module.vpc.vpc_cidr_block
        }
    }

    listeners = {
        # ex_http = {
        #     port     = 80
        #     protocol = "HTTP"
        #     forward = {
        #         target_group_key = "ex_ecs"
        #     }
        # }

        ex_https = {
            port     = 443
            protocol = "HTTPS"
            ssl_policy                  = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
            certificate_arn             = var.acm_certificate_arn
            forward = {
                target_group_key = "ex_ecs"
            }
        }

        ex-http-https-redirect = {
            port     = 80
            protocol = "HTTP"
            redirect = {
                port        = "443"
                protocol    = "HTTPS"
                status_code = "HTTP_301"
            }
        }
    }

    target_groups = {
        ex_ecs = {
            backend_protocol                  = "HTTP"
            backend_port                      = var.container_port
            target_type                       = "ip"
            deregistration_delay              = 5
            load_balancing_cross_zone_enabled = true

            health_check = {
                enabled             = true
                healthy_threshold   = 5
                interval            = 30
                matcher             = "200"
                path                = "/healthcheck"
                port                = "traffic-port"
                protocol            = "HTTP"
                timeout             = 5
                unhealthy_threshold = 2
            }

            # Theres nothing to attach here in this definition. Instead,
            # ECS will attach the IPs of the tasks to this target group
            create_attachment = false
        }
    }

    tags = local.tags
}

##############################################
# ASG
##############################################

module "autoscaling" {
    source  = "terraform-aws-modules/autoscaling/aws"
    version = "~> 6.5"

    name = "${var.cluster_name}-asg"

    image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
    instance_type = "t3.large"

    security_groups                 = [module.autoscaling_sg.security_group_id]
    user_data                       = base64encode(local.user_data)
    ignore_desired_capacity_changes = true

    create_iam_instance_profile = true
    iam_role_name               = var.cluster_name
    iam_role_description        = "ECS role for ${var.cluster_name}"
    iam_role_policies = {
        AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
        AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    vpc_zone_identifier = module.vpc.private_subnets
    health_check_type   = "EC2"
    min_size            = 1
    max_size            = 2
    desired_capacity    = 1

    # https://github.com/hashicorp/terraform-provider-aws/issues/12582
    autoscaling_group_tags = {
        AmazonECSManaged = true
    }

    # Required for  managed_termination_protection = "ENABLED"
    protect_from_scale_in = true

    # # Spot instances
    use_mixed_instances_policy = false
    mixed_instances_policy     = {}

    tags = local.tags
}

module "autoscaling_sg" {
    source  = "terraform-aws-modules/security-group/aws"
    version = "~> 5.0"

    name        = "${var.cluster_name}"
    description = "Autoscaling group security group"
    vpc_id      = module.vpc.vpc_id

    computed_ingress_with_source_security_group_id = [
        {
            rule                     = "http-80-tcp"
            source_security_group_id = module.alb.security_group_id
        }
    ]

    number_of_computed_ingress_with_source_security_group_id = 1

    egress_rules = ["all-all"]

    tags = local.tags
}

##############################################
# ECS cluster
##############################################

module "ecs_cluster" {
    source = "terraform-aws-modules/ecs/aws//modules/cluster"
    version = "~> 5.11"

    cluster_name = var.cluster_name

    # Capacity provider - autoscaling groups
    default_capacity_provider_use_fargate = false

    autoscaling_capacity_providers = {
        # Spot instances
        spot_provider = {
            auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
            managed_termination_protection = "ENABLED"

            managed_scaling = {
            maximum_scaling_step_size = 15
            minimum_scaling_step_size = 1
            status                    = "ENABLED"
            target_capacity           = 90
            }
        }
    }

    tags = local.tags
}

##############################################
# ECS service and task
##############################################

module "ecs_service" {
    source  = "terraform-aws-modules/ecs/aws//modules/service"
    version = "~> 5.11"

    # Service
    name        = "${var.cluster_name}-svc"
    cluster_arn = module.ecs_cluster.arn

    # Task Definition
    requires_compatibilities = ["EC2"]

    # Container definition(s)
    container_definitions = {
        (local.container_name) = {
            image = var.image_uri
            port_mappings = [
                {
                    name          = local.container_name
                    containerPort = var.container_port
                    protocol      = "tcp"
                }
            ]

            enable_cloudwatch_logging              = true
            create_cloudwatch_log_group            = true
            cloudwatch_log_group_name              = "/aws/ecs/${var.cluster_name}/${local.container_name}"
            cloudwatch_log_group_retention_in_days = 1

            log_configuration = {
                logDriver = "awslogs"
            }
        }
    }

    load_balancer = {
        service = {
            target_group_arn = module.alb.target_groups["ex_ecs"].arn
            container_name   = local.container_name
            container_port   = var.container_port
        }
    }

    subnet_ids = module.vpc.private_subnets
    security_group_rules = {
        alb_http_ingress = {
            type                     = "ingress"
            from_port                = var.container_port
            to_port                  = var.container_port
            protocol                 = "tcp"
            description              = "Service port"
            source_security_group_id = module.alb.security_group_id
        }
        egress_all = {
            type        = "egress"
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            description = "Allow all outbound"
            cidr_blocks = ["0.0.0.0/0"]
        }
    }

    tags = local.tags
}