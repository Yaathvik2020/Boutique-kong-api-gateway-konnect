# terraform-infra

AWS infrastructure for the boutique platform: **one VPC + one EKS cluster per environment**
(dev, staging, prod), built from the same reusable modules.

```
terraform-infra/
├── bootstrap/            # run ONCE per account (local state): S3 state bucket (native locking),
│                         #   GitHub OIDC roles for CI (images) and Terraform
├── global/               # run once: ECR repos shared by all envs (build once, promote the same image)
├── modules/              # reusable building blocks (written once)
│   ├── vpc/              #   public / private / database subnets, NAT, S3 endpoint, flow logs
│   ├── eks/              #   cluster (KMS, logs, private nodes), node group, managed add-ons, OIDC
│   ├── addons/           #   AWS Load Balancer Controller, external-dns, Argo CD, kube-prometheus-stack,
│   │                     #   External Secrets, cluster-autoscaler, metrics-server, gp3 StorageClass,
│   │                     #   IAM roles (incl. Kong data planes: read the Redis secret)
│   ├── rds/              #   PostgreSQL, encrypted, forced SSL, backups, Multi-AZ optional
│   ├── elasticache/      #   Redis for Kong rate limiting: TLS, AUTH password, failover optional
│   ├── edge/             #   ACM certificate (Route 53 validated), AWS WAF web ACL, ALB access-log bucket
│   └── app-secrets/      #   Secrets Manager: boutique/<env>/app, boutique/<env>/konnect-cluster-cert,
│                         #   boutique-<env>-kong-redis (read directly by Kong)
├── envs/                 # one folder per environment
│   ├── dev/              #   backend.tf, providers.tf, main.tf, variables.tf, outputs.tf, terraform.tfvars
│   ├── staging/          #   same files, staging values
│   └── prod/             #   same files, prod values (big, HA)
└── .gitignore            # .terraform/, *.tfstate, secret tfvars
```

`main.tf`, `providers.tf`, `variables.tf` and `outputs.tf` are **identical** in the three env
folders. Only `backend.tf` (state file key) and `terraform.tfvars` (sizes) differ. Change a module
once, then roll it out dev → staging → prod.

## What each environment gets

| | dev | staging | prod |
|---|---|---|---|
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| Availability zones | 2 | 3 | 3 |
| NAT gateways | 1 | 1 | 3 (one per AZ) |
| Kubernetes API | public (restrict to your IP) | public, office/VPN IP only | **private only** |
| Nodes | t3/t3a/m5.large **Spot**, 1–3 | m6i.large, 2–5 | m6i.xlarge, 3–9 |
| Database | Postgres pod in the cluster | RDS db.t4g.medium, single AZ | RDS db.r6g.large, **Multi-AZ**, 14-day backups |
| Public API | https://api-dev.ksysglobaltech.online | https://api-staging.ksysglobaltech.online | https://api.ksysglobaltech.online |
| Edge | ALB + WAF + ACM | ALB + WAF + ACM | ALB + WAF + ACM, deletion protection |
| Redis (Kong rate limits) | cache.t4g.micro, 1 node | cache.t4g.small, 1 node | cache.t4g.medium, **2 nodes + failover** |
| Add-ons HA (2 replicas) | no | yes | yes |
| Prometheus retention | 3 days | 7 days | 15 days |
| Deletion protection | off (rebuild any time) | on | on |
| Konnect control plane | `dev` | `staging` | `prod` |

Every environment has: private worker nodes, KMS-encrypted Kubernetes secrets, control plane audit
logs, VPC flow logs, NetworkPolicy enforcement (VPC CNI), EBS CSI driver, External Secrets with
read access to `boutique/<env>/*` only.

## Order of first-time setup

```bash
# 0. Tools: terraform 1.17.2 (minimum 1.11 for S3 native state locking), AWS CLI v2 (logged in to the target account), kubectl

# 1. Bootstrap (once per account, local state)
cd terraform-infra/bootstrap
# edit terraform.tfvars: github_repo
terraform init && terraform apply
terraform output       # state_bucket, github_ci_role_arn, github_terraform_role_arn

# 2. Put the bucket name into every backend.tf (replace <account-id>)
cd ..
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/<account-id>/$ACCOUNT/" global/backend.tf envs/*/backend.tf

# 3. Shared ECR repositories
cd global && terraform init && terraform apply && cd ..

# 4. Each environment, dev first
cd envs/dev
# edit terraform.tfvars: cluster_public_access_cidrs = your IP, cluster_admin_role_arns
terraform init
terraform plan
terraform apply                      # ~20 minutes
$(terraform output -raw configure_kubectl)
kubectl get nodes

# then envs/staging, then envs/prod
```

**Prod has a private Kubernetes API.** Terraform's Helm/Kubernetes providers and `kubectl` must run
from inside the prod VPC: a VPN, a bastion with SSM, or a self-hosted GitHub runner in the VPC
(`TF_RUNNER_PROD` in `.github/workflows/terraform.yml`). For the very first build you can
temporarily set `cluster_public_access_cidrs = ["<your-ip>/32"]` and remove it afterwards.

## After Terraform: what's next

Terraform stops at "cluster + add-ons + secrets". Then, per environment:

0. Copy the outputs `acm_certificate_arn`, `waf_acl_arn`, `kong_dp_role_arn`, `vpc_cidr`,
   `alb_logs_bucket` into `k8s-kong/kong-dp/values-<env>.yaml`, and `redis_host`,
   `redis_secret_name` into `kong-config/envs/<env>.env`
1. Konnect: create control plane `<env>`, generate the data plane certificate →
   `k8s-kong/scripts/put-konnect-cert.sh <env> tls.crt tls.key`
2. Fill `k8s-kong/kong-dp/values-<env>.yaml` (Konnect hosts + image tag)
3. `kubectl apply -f argocd/<env>/` → Argo CD deploys the app and the Kong data planes
4. Put `terraform output -raw redis_host` into `kong-config/envs/<env>.env`, then
   `kong-config/deck.sh <env> sync` → routes and plugins

Full walkthrough: [../README.md](../README.md).

## Day-2

| Task | How |
|---|---|
| Change a module | Edit `modules/…`, then `terraform plan/apply` in dev → staging → prod |
| Upgrade Kubernetes | Bump `kubernetes_version` one minor version, dev first. Add-ons follow automatically unless pinned in `eks_addon_versions` |
| Bigger nodes / more nodes | `node_instance_types`, `node_max_size` in that env's tfvars |
| Rotate DB password | `terraform apply -replace=module.rds[0].random_password.master` (staging/prod): updates RDS and `boutique/<env>/app`; then restart the pods |
| Tear down dev | `cd envs/dev && terraform destroy` (dev has deletion protection off) |

## Secrets

No secret is ever in a `.tfvars` file or in Git:

- DB password and JWT secrets are **generated** by Terraform and written to Secrets Manager
  (they are also in the encrypted, versioned S3 state, so restrict bucket access).
- The Redis password (AUTH token) is generated by Terraform and stored in Secrets Manager as
  `boutique-<env>-kong-redis`. Kong reads it **directly from Secrets Manager** at runtime
  (`{vault://aws-sm/boutique-<env>-kong-redis/password}`) with its own IAM role that can read only
  that secret. It is not copied into Kubernetes.
- The Konnect certificate is uploaded with `put-konnect-cert.sh`.
- External Secrets copies them into the cluster.

If you ever need secret variables, put them in `*.secret.tfvars` (git-ignored) or `TF_VAR_…` env vars.

## State locking

State is in S3 (versioned, encrypted). Locking uses **S3 native lock files** (`use_lockfile = true`):
while a `plan`/`apply` runs, Terraform writes `<key>.tflock` next to the state file; a second run
waits or fails with "state locked". No DynamoDB table is needed (Terraform >= 1.11).

A run that crashed can leave the lock behind: `terraform force-unlock <LOCK_ID>` (ID is in the error).
