# Pinned versions (checked 21 Nov 2026)

Every version below is the latest stable release on that date, except where the
"Why" column says otherwise. Upgrade in **dev first**, then staging, then prod.

## Kong

| Component | Version | Where it is set | Why / notes |
|---|---|---|---|
| Kong Gateway (data planes) | `kong/kong-gateway:3.14.0.12` | `k8s-kong/kong-dp/values-<env>.yaml` | 3.14 is the current **LTS** (supported to 2029). 3.15/3.16 exist but are short-support releases. Take the newest 3.14.x patch Konnect offers. |
| Kong Helm chart | `kong/kong` **3.4.1** | `argocd/<env>/kong-dp.yaml` | Latest chart |
| decK | **1.70.1** | CI (`kong/setup-deck@v1`, `deck-version`), run guide | Latest |
| decK file format | `_format_version: "3.0"` | `kong-config/boutique.yaml` | Current format |

Kong 3.14 note: `tls_certificate_verify` is **on** by default. This project already
verifies TLS (Konnect mTLS, Redis `ssl_verify: true` with the system CA bundle), so
nothing breaks.

## Terraform

| Component | Version | Where |
|---|---|---|
| Terraform CLI | **1.17.2** in CI; `required_version >= 1.11` (minimum for S3 native locking) | `.github/workflows/terraform.yml`, `*/providers.tf` |
| hashicorp/aws | `~> 6.73` | all stacks |
| hashicorp/helm | `~> 3.3` | envs |
| hashicorp/kubernetes | `~> 3.5` | envs |
| hashicorp/random | `~> 3.9` | envs |
| hashicorp/tls | `~> 4.4` | envs |

## AWS services

| Component | Version | Where | Notes |
|---|---|---|---|
| EKS (Kubernetes) | **1.37** | `envs/<env>/terraform.tfvars` | Newest in EKS standard support. EKS upgrades one minor version at a time. |
| RDS PostgreSQL | **18** | `modules/rds` (`engine_major_version`) | Minor versions auto-upgrade |
| ElastiCache | Redis OSS **7.1** | `modules/elasticache` | Newest Redis OSS engine on ElastiCache. Valkey is AWS's newer option; it works with Kong but means a new cluster. |

## Cluster add-ons (Helm, `modules/addons/main.tf`)

| Chart | Version | App version |
|---|---|---|
| argo-cd | **10.18.2** | Argo CD v3.6.2 |
| kube-prometheus-stack | **93.6.1** | Prometheus Operator v0.95.2 |
| external-secrets | **2.15.0** | ESO v2.15.0 (manifests use `external-secrets.io/v1`) |
| aws-load-balancer-controller | **3.6.3** | v3.6.3 |
| external-dns | **1.24.0** | |
| cluster-autoscaler | **9.60.0** | v1.37.0, matches EKS 1.37 |
| metrics-server | **3.14.0** | v0.9.0 |

## Container images

| Image | Version | Where |
|---|---|---|
| postgres (dev in-cluster DB, restore job) | `postgres:18-alpine` | `k8s-kong/components/in-cluster-postgres`, `k8s-kong/base/03-database` |

## GitHub Actions

`actions/checkout@v7`, `actions/upload-artifact@v7`, `actions/github-script@v9`,
`aws-actions/configure-aws-credentials@v6`, `aws-actions/amazon-ecr-login@v2`,
`peter-evans/create-pull-request@v8`, `hashicorp/setup-terraform@v4`, `kong/setup-deck@v1`.

## How to re-check

```bash
# latest tag of any GitHub project
git ls-remote --tags --refs https://github.com/argoproj/argo-helm | grep argo-cd- | sort -V | tail -1
# latest chart from a Helm repo
helm repo update && helm search repo argo/argo-cd
```
