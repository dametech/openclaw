#
# OpenClaw Teams Integration Infrastructure
# Extends existing ALB to route Teams webhooks to Kubernetes cluster
#

# Data source: Get existing ALB
data "aws_lb" "openclaw_alb" {
  arn = var.alb_arn
}

# Data source: Get existing VPC
data "aws_vpc" "dame_vpc" {
  id = var.vpc_id
}

# Data source: Get subnets for ALB
data "aws_subnets" "dame_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
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
    security_groups = [data.aws_lb.openclaw_alb.security_groups[0]]
  }

  ingress {
    description     = "Health checks from ALB"
    from_port       = 18789  # OpenClaw gateway port
    to_port         = 18789
    protocol        = "tcp"
    security_groups = [data.aws_lb.openclaw_alb.security_groups[0]]
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

# ALB Listener Rule for Teams webhook
resource "aws_lb_listener_rule" "teams_webhook" {
  listener_arn = var.alb_listener_arn
  priority     = 100  # Adjust based on existing rules

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
  value       = "https://${data.aws_lb.openclaw_alb.dns_name}${var.teams_webhook_path}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = data.aws_lb.openclaw_alb.dns_name
}

output "target_group_arn" {
  description = "Target group ARN for Kubernetes nodes"
  value       = aws_lb_target_group.openclaw_k8s_teams.arn
}

output "security_group_id" {
  description = "Security group ID for K8s nodes"
  value       = aws_security_group.openclaw_k8s_alb_ingress.id
}
