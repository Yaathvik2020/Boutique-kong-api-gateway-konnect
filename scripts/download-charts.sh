#!/usr/bin/env bash
# Download every Helm chart this project installs, as .tgz files, with curl (long timeouts + retries).
# Use it when "helm install" / "terraform apply" fail with
#   "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
# on a slow or throttled connection to GitHub's download servers.
#
#   scripts/download-charts.sh [folder]          # default folder: ~/charts
#
# Then:
#   Terraform add-ons:  terraform -chdir=terraform-infra/envs/dev apply -var="local_chart_dir=$HOME/charts"
#   Kong data plane:    helm upgrade --install kong-dp ~/charts/kong-3.4.1.tgz -n kong --create-namespace \
#                         -f k8s-kong/kong-dp/values.yaml -f k8s-kong/kong-dp/values-dev.yaml
#
# Versions must match terraform-infra/modules/addons/main.tf (local.v) and argocd/<env>/kong-dp.yaml.
set -euo pipefail
DIR="${1:-$HOME/charts}"
mkdir -p "$DIR"

CHARTS=(
  "kong-3.4.1.tgz|https://github.com/Kong/charts/releases/download/kong-3.4.1/kong-3.4.1.tgz"
  "external-secrets-2.15.0.tgz|https://github.com/external-secrets/external-secrets/releases/download/helm-chart-2.15.0/external-secrets-2.15.0.tgz"
  "aws-load-balancer-controller-3.6.3.tgz|https://raw.githubusercontent.com/aws/eks-charts/gh-pages/aws-load-balancer-controller-3.6.3.tgz"
  "external-dns-1.24.0.tgz|https://github.com/kubernetes-sigs/external-dns/releases/download/external-dns-helm-chart-1.24.0/external-dns-1.24.0.tgz"
  "cluster-autoscaler-9.60.0.tgz|https://github.com/kubernetes/autoscaler/releases/download/cluster-autoscaler-chart-9.60.0/cluster-autoscaler-9.60.0.tgz"
  "metrics-server-3.14.0.tgz|https://github.com/kubernetes-sigs/metrics-server/releases/download/metrics-server-helm-chart-3.14.0/metrics-server-3.14.0.tgz"
  "kube-prometheus-stack-93.6.1.tgz|https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-93.6.1/kube-prometheus-stack-93.6.1.tgz"
  "argo-cd-10.18.2.tgz|https://github.com/argoproj/argo-helm/releases/download/argo-cd-10.18.2/argo-cd-10.18.2.tgz"
)

fail=0
for entry in "${CHARTS[@]}"; do
  file="${entry%%|*}"; url="${entry#*|}"
  if [[ -s "$DIR/$file" ]] && tar tzf "$DIR/$file" >/dev/null 2>&1; then
    echo "ok (already here)  $file"; continue
  fi
  if curl -fsSL --retry 8 --retry-all-errors --retry-delay 3 --connect-timeout 30 --max-time 300 \
       -o "$DIR/$file.part" "$url" && tar tzf "$DIR/$file.part" >/dev/null 2>&1; then
    mv "$DIR/$file.part" "$DIR/$file"
    echo "ok                 $file"
  else
    rm -f "$DIR/$file.part"; echo "FAILED             $file  ($url)" >&2; fail=1
  fi
done

echo
ls -l "$DIR"/*.tgz
if [[ $fail -ne 0 ]]; then
  echo "Some downloads failed: run the script again." >&2
  exit 1
fi
echo "All charts are in $DIR"
