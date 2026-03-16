#
# OpenClaw Teams Integration Infrastructure
# Creates new ALB and routes Teams webhooks to Kubernetes cluster
#

# Data source: Get VPC
data "aws_vpc" "dame_vpc" {
  id = var.vpc_id
}

# Data source: Get public subnets for ALB
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Type = "public"  # Adjust tag filter based on your subnet tagging
  }
}

# Security Group for ALB
resource "aws_security_group" "openclaw_alb" {
  name_prefix = "openclaw-alb-"
  description = "Security group for OpenClaw ALB (Teams webhook)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from Internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "openclaw-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for K8s nodes to receive ALB traffic
resource "aws_security_group" "openclaw_k8s_alb_ingress" {
  name_prefix = "openclaw-k8s-alb-ingress-"
  description = "Allow ALB traffic to Kubernetes nodes for OpenClaw Teams webhook"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Teams webhook from ALB"
    from_port       = var.k8s_nodeport
    to_port         = var.k8s_nodeport
    protocol        = "tcp"
    security_groups = [aws_security_group.openclaw_alb.id]
  }

  ingress {
    description     = "Health checks from ALB"
    from_port       = 18789  # OpenClaw gateway port
    to_port         = 18789
    protocol        = "tcp"
    security_groups = [aws_security_group.openclaw_alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "openclaw-k8s-alb-ingress"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "openclaw" {
  name               = "openclaw-teams-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.openclaw_alb.id]
  subnets            = data.aws_subnets.public_subnets.ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  enable_waf_fail_open             = false

  tags = {
    Name = "openclaw-teams-alb"
  }
}

# Target Group for Kubernetes nodes
resource "aws_lb_target_group" "openclaw_k8s_teams" {
  name_prefix = "oc-k8s-"
  port        = var.k8s_nodeport
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "18789"  # Health check on gateway port
    matcher             = "200-299"
  }

  deregistration_delay = 30

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 10800  # 3 hours
    enabled         = true
  }

  tags = {
    Name = "openclaw-k8s-teams-webhook"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register Kubernetes worker nodes as targets
resource "aws_lb_target_group_attachment" "k8s_nodes" {
  count            = length(var.k8s_worker_nodes)
  target_group_arn = aws_lb_target_group.openclaw_k8s_teams.arn
  target_id        = var.k8s_worker_nodes[count.index]
  port             = var.k8s_nodeport
}

# HTTPS Listener (uses ACM certificate from acm-certificate.tf)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.openclaw.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.openclaw.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openclaw_k8s_teams.arn
  }

  tags = {
    Name = "openclaw-https-listener"
  }

  depends_on = [aws_acm_certificate_validation.openclaw]
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.openclaw.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "openclaw-http-redirect"
  }
}

# Listener Rule for Teams webhook path
resource "aws_lb_listener_rule" "teams_webhook" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openclaw_k8s_teams.arn
  }

  condition {
    path_pattern {
      values = [var.teams_webhook_path]
    }
  }

  tags = {
    Name = "openclaw-teams-webhook-route"
  }
}

# Output the webhook URL
output "teams_webhook_url" {
  description = "Public webhook URL for Azure Bot messaging endpoint"
  value       = "https://${aws_lb.openclaw.dns_name}${var.teams_webhook_path}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.openclaw.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.openclaw.arn
}

output "alb_zone_id" {
  description = "ALB Zone ID (for Route53 alias records)"
  value       = aws_lb.openclaw.zone_id
}

output "target_group_arn" {
  description = "Target group ARN for Kubernetes nodes"
  value       = aws_lb_target_group.openclaw_k8s_teams.arn
}

output "security_group_alb_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.openclaw_alb.id
}

output "security_group_k8s_id" {
  description = "Security group ID for K8s nodes"
  value       = aws_security_group.openclaw_k8s_alb_ingress.id
}
