#
# Kubernetes Service Configuration for Teams Webhook
# Creates NodePort service to expose Teams webhook on all nodes
#

resource "kubernetes_service" "openclaw_teams_webhook" {
  metadata {
    name      = "openclaw-teams-webhook"
    namespace = "openclaw"
    labels = {
      app                          = "openclaw"
      "app.kubernetes.io/name"     = "openclaw"
      "app.kubernetes.io/instance" = "openclaw"
      component                    = "teams-webhook"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name"     = "openclaw"
      "app.kubernetes.io/instance" = "openclaw"
    }

    port {
      name        = "teams-webhook"
      port        = 3978
      target_port = 3978
      node_port   = var.k8s_nodeport
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"

    session_affinity_config {
      client_ip {
        timeout_seconds = 10800  # 3 hours
      }
    }
  }
}

# Output NodePort for reference
output "k8s_nodeport" {
  description = "NodePort for Teams webhook on all K8s nodes"
  value       = kubernetes_service.openclaw_teams_webhook.spec[0].port[0].node_port
}

output "k8s_service_name" {
  description = "Kubernetes service name"
  value       = kubernetes_service.openclaw_teams_webhook.metadata[0].name
}
