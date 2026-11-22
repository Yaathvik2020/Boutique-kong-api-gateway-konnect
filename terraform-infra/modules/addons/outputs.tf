output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "kong_dp_role_arn" {
  description = "Put in k8s-kong/kong-dp/values-<env>.yaml (service account annotation)"
  value       = aws_iam_role.kong_dp.arn
}

output "aws_lb_controller_role_arn" {
  value = aws_iam_role.aws_lb_controller.arn
}
