# Find default encryption key
data "aws_kms_key" "aws-efs" {
  key_id = "alias/aws/elasticfilesystem"
}

locals {
  EFS_SG_PORTS = [ 111, 2049, 2999 ]
}

# Create EFS
resource "aws_efs_file_system" "MyEFS" {
  creation_token = "MyEFS"
  encrypted      = true
  kms_key_id     = data.aws_kms_key.aws-efs.arn
  tags = {
    Name = "MyEFS"
  }
}

resource "aws_security_group" "mount-point-sg" {
  vpc_id = aws_vpc.My-VPC.id
  name   = "mount-point-sg"

  dynamic "ingress" {
    for_each = local.EFS_SG_PORTS
    content {
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.ECS-SG.id]
    }
  }

  dynamic "ingress" {
    for_each = local.EFS_SG_PORTS
    content {
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "udp"
      security_groups = [aws_security_group.ECS-SG.id]
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Create a mount target. At least one is required to mount the EFS
# even with an Access Point.
resource "aws_efs_mount_target" "Nextcloud-Mount-Target" {
  file_system_id  = aws_efs_file_system.MyEFS.id
  subnet_id       = aws_subnet.public[0].id
  security_groups = [aws_security_group.mount-point-sg.id]
}

# Create Access Point
resource "aws_efs_access_point" "Nextcloud-Access-Point" {
  file_system_id = aws_efs_file_system.MyEFS.id
  root_directory {
    path = "/nextcloud"
    creation_info {
      owner_gid   = 33
      owner_uid   = 33
      permissions = "777"
    }
  }
  posix_user {
    gid = 33
    uid = 33
  }
  tags = { Name = "Nextcloud-Access-Point" }
}

# Create EFS Resource policy that will allow access to the EFS
# only for the IAM role of EC2/ECS.
resource "aws_efs_file_system_policy" "EFS-Policy" {
  file_system_id = aws_efs_file_system.MyEFS.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EFSPolicy"
    Statement = [{
      Sid       = "Allow EC2 access to EFS"
      Effect    = "Allow"
      Principal = { AWS = [aws_iam_role.Task-Role.arn] }
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ]
      Resource = aws_efs_file_system.MyEFS.arn
      Condition = {
        StringEquals = {
          "elasticfilesystem:AccessPointArn" = aws_efs_access_point.Nextcloud-Access-Point.arn
        }
      }
    }]
  })
}