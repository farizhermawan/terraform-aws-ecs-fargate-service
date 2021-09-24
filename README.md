# terraform-aws-ecs-service
[![CircleCI](https://circleci.com/gh/traveloka/terraform-aws-ecs-service/tree/master.svg?style=svg)](https://circleci.com/gh/traveloka/terraform-aws-ecs-service/tree/master)

Terraform module for creating ECS Service

## Usage
```hcl
module "service" {
  source  = "traveloka/terraform-aws-ecs-service"
  version = "0.1.0"
}
```

## Note
If you edit task definition in your `container_definition_template_file` this module will create new task version and deploy the latest image. If you don't want to deploy the latest image but still want to edit task definition, you need to define argument `image_version` with the currently running docker image.
