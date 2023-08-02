locals {
  HTTP_PORT = 80
  DB_HOST     = "nextcloud-db"
  DB_DATABASE = "nextcloud"
  DB_USER     = "nextcloud"
  DB_PASSWORD = "nextcloud"

  MARIADB_ENV_VARIABLES = {
    MARIADB_ROOT_PASSWORD = "234QWE.rtysdfg"
    MARIADB_DATABASE      = local.DB_DATABASE
    MARIADB_USER          = local.DB_USER
    MARIADB_PASSWORD      = local.DB_PASSWORD
  }

  NEXTCLOUD_ENV_VARIABLES = {
    MYSQL_HOST               = "127.0.0.1"
    MYSQL_DATABASE           = local.DB_DATABASE
    MYSQL_USER               = local.DB_USER
    MYSQL_PASSWORD           = local.DB_PASSWORD
    NEXTCLOUD_ADMIN_USER     = "admin"
    NEXTCLOUD_ADMIN_PASSWORD = "admin"
    NEXTCLOUD_DATA_DIR       = "/nextcloud"
  }

  # Normalize to AWS format
  NEXTCLOUD_ENV_VARIABLES_AWS = [
    for key, value in local.NEXTCLOUD_ENV_VARIABLES : {
      name  = key
      value = value
    }
  ]

  MARIADB_ENV_VARIABLES_AWS = [
    for key, value in local.MARIADB_ENV_VARIABLES : {
      name  = key
      value = value
    }
  ]
}

resource "aws_security_group" "ECS-SG" {
  name   = "ECS-SG"
  vpc_id = aws_vpc.My-VPC.id
  ingress {
    from_port       = local.HTTP_PORT
    to_port         = local.HTTP_PORT
    protocol        = "tcp"
    security_groups = [aws_security_group.ALB-SG.id]
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    self = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_alb_target_group" "ECS-TG" {
  name        = "ECS-Nextcloud"
  port        = local.HTTP_PORT
  protocol    = "HTTP"
  vpc_id      = aws_vpc.My-VPC.id
  target_type = "ip" # For Fargate ECS, it just uses IP type
  health_check {
    path     = "/"
    port     = "traffic-port"
    protocol = "HTTP"
    matcher  = "200-499"
    interval = 30
    timeout  = 5
    healthy_threshold = 5
    unhealthy_threshold = 5
  }
}

resource "aws_ecs_task_definition" "Nextcloud-Task" {
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.Task-Role.arn
  task_role_arn            = aws_iam_role.Task-Role.arn
  family                   = "Nextcloud-Maria-Task"

  volume {
    name = "nextcloud-storage"
    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.MyEFS.id
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2049
      authorization_config {
        access_point_id = aws_efs_access_point.Nextcloud-Access-Point.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = local.DB_HOST
      image     = "mariadb:10.6"
      essential = true
      portMappings = [{
        containerPort = 3306
        hostPort      = 3306
        protocol      = "tcp"
      }]
      environment = local.MARIADB_ENV_VARIABLES_AWS
      logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group = "/ecs/nextcloud-logs"
            awslogs-region = "eu-central-1"
            awslogs-stream-prefix = "maria"
          }
      }
    },
    {
      name      = "Nextcloud"
      image     = "nextcloud:latest"
      essential = true
      portMappings = [{
        containerPort = local.HTTP_PORT
        hostPort      = local.HTTP_PORT
        protocol      = "tcp"
      }]
      logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group = "/ecs/nextcloud-logs"
            awslogs-region = "eu-central-1"
            awslogs-stream-prefix = "ecs"
          }
      }
      environment = concat(
        local.NEXTCLOUD_ENV_VARIABLES_AWS,
        [{
          name  = "NEXTCLOUD_TRUSTED_DOMAINS"
          value = aws_alb.ALB.dns_name
        }]
      )
      dependsOn = [{
        containerName = local.DB_HOST
        condition     = "START"
      }]
      mountPoints = [{
        sourceVolume = "nextcloud-storage"
        containerPath = "/nextcloud"
        readOnly = false
      }]
  }])
}

resource "aws_ecs_cluster" "Nextcloud" {
  name = "Nextcloud"
}

resource "aws_ecs_service" "Nextcloud" {
  name            = "nextcloud3"
  cluster         = aws_ecs_cluster.Nextcloud.id
  task_definition = aws_ecs_task_definition.Nextcloud-Task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  force_new_deployment = true
  network_configuration {
    subnets          = [aws_subnet.public[0].id]
    security_groups  = [aws_security_group.ECS-SG.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_alb_target_group.ECS-TG.arn
    container_name   = "Nextcloud"
    container_port   = local.HTTP_PORT
  }
}

resource "aws_ecs_task_set" "Nextcloud" {
  cluster         = aws_ecs_cluster.Nextcloud.id
  launch_type     = "FARGATE"
  task_definition = "aws_ecs_task_definition.Nextcloud-Task.arn"
  service         = aws_ecs_service.Nextcloud.id
}