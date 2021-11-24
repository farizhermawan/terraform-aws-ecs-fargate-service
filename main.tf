locals {
  cluster = "${var.service_name}-${var.cluster_role}"

  global_tags = {
    Service       = var.service_name
    Cluster       = local.cluster
    Application   = var.application
    ProductDomain = var.product_domain
    Environment   = var.environment
    ManagedBy     = "terraform"
  }

  service_tags = {
    Name = module.service_name.name
  }

  taskdef_tags = {
    Name = module.taskdef_name.name
  }
}

module "service_name" {
  source = "github.com/traveloka/terraform-aws-resource-naming?ref=v0.19.1"

  name_prefix   = local.cluster
  resource_type = "ecs_service"
}

module "taskdef_name" {
  source = "github.com/traveloka/terraform-aws-resource-naming?ref=v0.19.1"

  name_prefix   = local.cluster
  resource_type = "ecs_task_definition"
}

resource "aws_ecs_service" "ecs_service" {
  name          = module.service_name.name
  cluster       = var.ecs_cluster_arn
  desired_count = var.capacity

  launch_type = var.launch_type

  platform_version                  = var.platform_version
  task_definition                   = aws_ecs_task_definition.task_def.arn
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  enable_ecs_managed_tags = var.enable_ecs_managed_tags

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.main_container_name
    container_port   = var.main_container_port
  }

  deployment_controller {
    type = var.deployment_controller
  }

  propagate_tags = var.propagate_tags
  tags           = merge(local.global_tags, local.service_tags, var.service_tags)

  lifecycle {
    ignore_changes = [
      desired_count,
      load_balancer, # https://github.com/hashicorp/terraform-provider-aws/issues/13192
      platform_version,
      task_definition,
    ]
  }
}

resource "aws_ecs_task_definition" "task_def" {
  family                = module.taskdef_name.name
  container_definitions = var.container_definitions
  task_role_arn         = var.task_role_arn

  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.execution_role_arn
  network_mode             = "awsvpc"

  cpu    = var.cpu
  memory = var.memory

  tags = merge(local.global_tags, local.taskdef_tags, var.taskdef_tags)

  lifecycle {
    create_before_destroy = true
  }
  
   dynamic "volume" {
    for_each = var.volumes
    content {

      host_path = lookup(volume.value, "host_path", null)
      name      = volume.value.name

      dynamic "docker_volume_configuration" {
        for_each = lookup(volume.value, "docker_volume_configuration", [])
        content {
          autoprovision = lookup(docker_volume_configuration.value, "autoprovision", null)
          driver        = lookup(docker_volume_configuration.value, "driver", null)
          driver_opts   = lookup(docker_volume_configuration.value, "driver_opts", null)
          labels        = lookup(docker_volume_configuration.value, "labels", null)
          scope         = lookup(docker_volume_configuration.value, "scope", null)
        }
      }
      dynamic "efs_volume_configuration" {
        for_each = lookup(volume.value, "efs_volume_configuration", [])
        content {
          file_system_id          = lookup(efs_volume_configuration.value, "file_system_id", null)
          root_directory          = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption      = lookup(efs_volume_configuration.value, "transit_encryption", null)
          transit_encryption_port = lookup(efs_volume_configuration.value, "transit_encryption_port", null)
        }
      }
    }
  }
}

