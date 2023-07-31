resource "aws_security_group" "ALB-SG" {
  name   = "ALB-SG"
  vpc_id = aws_vpc.My-VPC.id
  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_alb" "ALB" {
  subnets         = aws_subnet.public[*].id
  security_groups = [aws_security_group.ALB-SG.id]
}

data "aws_acm_certificate" "my-domain" {
  domain   = var.Domain
  statuses = ["ISSUED"]
}

resource "aws_alb_listener" "HTTPS" {
  load_balancer_arn = aws_alb.ALB.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.my-domain.arn
  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Hello world!"
      status_code  = "200"
    }
  }
}

resource "aws_alb_listener" "HTTP" {
  load_balancer_arn = aws_alb.ALB.arn
  port              = 80
  protocol          = "HTTP"
  # Redirect to HTTPS
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

output "elb-https" {
  value = "https://${aws_alb.ALB.dns_name}"
}