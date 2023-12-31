locals {
  cluster = "${var.service_name}-${var.cluster_role}"

  global_tags = {
    Service       = var.service_name
    Cluster       = local.cluster
    Application   = var.application
    ProductDomain = var.product_domain
    Environment   = var.environment
    ManagedBy     = "Terraform"
  }

  service_tags = {
    Name = module.service_name.name
  }

  taskdef_tags = {
    Name = module.taskdef_name.name
  }

  container_definitions = templatefile(var.container_definition_template_file != "" ? var.container_definition_template_file : "${path.module}/templates/container-definition.json.tpl", {
    aws_region     = data.aws_region.current.name
    container_name = var.main_container_name
    image_name     = var.image_name
    version        = var.image_version
    port           = var.main_container_port
    log_group      = aws_cloudwatch_log_group.log_group.name
    environment    = jsonencode(var.environment_variables)
    product_domain = var.product_domain
  })
}

module "service_name" {
  source = "github.com/traveloka/terraform-aws-resource-naming?ref=v0.22.0"

  name_prefix   = local.cluster
  resource_type = "ecs_service"
}

module "taskdef_name" {
  source = "github.com/traveloka/terraform-aws-resource-naming?ref=v0.22.0"

  name_prefix   = local.cluster
  resource_type = "ecs_task_definition"
}

module "log_group_name" {
  source = "github.com/traveloka/terraform-aws-resource-naming?ref=v0.22.0"

  name_prefix   = "/tvlk/${var.cluster_role}-${var.application}/${var.service_name}"
  resource_type = "cloudwatch_log_group"
}

resource "aws_ecs_service" "ecs_service" {
  name          = module.service_name.name
  cluster       = var.ecs_cluster_arn
  desired_count = var.capacity

  launch_type = length(var.capacity_provider_strategies) > 0 ? null : "FARGATE"

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      base              = capacity_provider_strategy.value.base
      weight            = capacity_provider_strategy.value.weight
    }
  }

  platform_version = var.platform_version

  task_definition = "${aws_ecs_task_definition.task_def.family}:${max(aws_ecs_task_definition.task_def.revision, data.aws_ecs_task_definition.task_def.revision)}"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  enable_execute_command            = var.enable_execute_command

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker.enable
    rollback = var.deployment_circuit_breaker.rollback
  }

  deployment_controller {
    type = var.deployment_controller.type
  }

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

  propagate_tags = "SERVICE"
  tags           = merge(local.global_tags, local.service_tags, var.service_tags)

  lifecycle {
    ignore_changes = [
      desired_count,
      launch_type,     // somehow it conflict with capacity provider
    ]
  }
}

data "aws_ecs_task_definition" "task_def" {
  task_definition = aws_ecs_task_definition.task_def.family
}

resource "aws_ecs_task_definition" "task_def" {
  family                = module.taskdef_name.name
  container_definitions = local.container_definitions
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

resource "aws_cloudwatch_log_group" "log_group" {
  name              = module.log_group_name.name
  retention_in_days = var.log_retention_in_days

  tags = merge(local.global_tags, var.log_tags)
}
