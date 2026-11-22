# Boutique-kong-api-gateway-konnect

Production setup for the Boutique microservices on AWS EKS, with **Kong Gateway in hybrid mode
managed by Kong Konnect**.

```bash
git clone https://github.com/Yaathvik2020/Boutique-kong-api-gateway-konnect.git
```

Three environments — **dev, staging, prod** — each with its own VPC, EKS cluster, Konnect control
plane and secrets. One set of code, promoted from dev to prod.

**Request path (every environment):**

```
client ─► Route 53 ─► ALB (ACM TLS, AWS WAF) ─► Kong data planes (EKS) ─► boutique services
  api[-dev|-staging].ksysglobaltech.online          │ rate limits in ElastiCache Redis
                                                    │ Redis password read from AWS Secrets Manager (IAM role)
                                                    └─ config from Konnect over mTLS
```

**Environments:**

```
                       ┌──────────────── Konnect (Kong-hosted) ────────────────┐
  kong-config/ ─decK─► │  control plane "dev"   "staging"   "prod"              │
                       └──────┬──────────────────┬──────────────────┬───────────┘
                              │ mTLS             │ mTLS             │ mTLS
  ┌───────── dev (us-east-1) ─▼──┐ ┌──── staging ──▼──────────┐ ┌──── prod ─▼──────────────────┐
  │ VPC 10.10/16, 2 AZ, 1 NAT    │ │ VPC 10.20/16, 3 AZ       │ │ VPC 10.30/16, 3 AZ, 3 NAT    │
  │ EKS (Spot)                   │ │ EKS                      │ │ EKS (private API)            │
  │  Kong DP x1  ─► boutique x1  │ │  Kong DP 2-4 ─► 2-4 pods │ │  Kong DP 3-10 ─► 3-10 pods   │
  │  Postgres pod                │ │  RDS single-AZ           │ │  RDS Multi-AZ                │
  │  Redis 1 node (rate limits)  │ │  Redis 1 node            │ │  Redis 2 nodes, failover     │
  │  Argo CD, Prometheus, ESO    │ │  Argo CD, Prometheus,ESO │ │  Argo CD, Prometheus, ESO    │
  └──────────────────────────────┘ └──────────────────────────┘ └──────────────────────────────┘
        ▲ images (same tag)                   ▲                              ▲
  ECR (global) ◄── CI builds once ── promote dev → staging → prod (pull requests)
```

## Versions

All tools, charts, providers and images are pinned to the latest stable release (checked 21 Nov 2026). The full list, and how to re-check it, is in [VERSIONS.md](VERSIONS.md). Highlights: Kong Gateway 3.14 LTS, Kong chart 3.4.1, decK 1.70.1, EKS 1.37, Terraform 1.17.2 with AWS provider 6.x, RDS PostgreSQL 18.

## Repository layout

| Folder | What | Applied by |
|---|---|---|
| `terraform-infra/` | VPC, EKS, add-ons (ALB controller, external-dns, Argo CD …), ACM, WAF, RDS, Redis, Secrets Manager, ECR, CI roles | Terraform ([README](terraform-infra/README.md)) |
| `k8s-kong/base/` | App manifests shared by all envs | Argo CD (via overlays) |
| `k8s-kong/overlays/<env>/` | Per env: image tags, secret names, replicas/HPA/PDB, Postgres (dev only) | Argo CD `boutique` app |
| `k8s-kong/kong-dp/` | Kong data plane Helm values: shared + `values-<env>.yaml` | Argo CD `kong-dp` app |
| `argocd/<env>/` | The two Argo CD Applications for that cluster | `kubectl apply -f`, once per cluster |
| `kong-config/` | Routes, plugins (rate limiting in Redis), health checks, timeouts (decK). Per-env values in `kong-config/envs/<env>.env` | `deck.sh <env> sync` / workflow |
| `.github/workflows/` | `ci` (build → dev), `promote` (→ staging/prod PR), `kong-config`, `terraform` | GitHub Actions |
| `projects/boutique-microservices/` | Application source code | — |

## How a change reaches production

| Change | dev | staging | prod |
|---|---|---|---|
| **App code** | push to main → `ci` builds images (tag = commit SHA) → commits tag to `overlays/dev` → Argo CD deploys | run `promote` (target staging) → review + merge PR | run `promote` (target prod) → review + merge PR |
| **Gateway config** (`kong-config/`) | PR shows decK diff for all 3 → merge → synced to Konnect `dev` | approve the `staging` environment in the workflow | approve `prod` |
| **Infrastructure** (`terraform-infra/`) | PR shows plans for all 3 → run `terraform` workflow env=dev | env=staging (approval) | env=prod (approval) |
| **Kong version / chart** | edit `kong-dp/values-dev.yaml` / `argocd/dev/kong-dp.yaml` | then staging | then prod |

Rule: nothing is built twice and nothing reaches prod without passing dev and staging.

## First-time setup (do dev completely, then staging, then prod)

### 1. AWS (Terraform)

Follow [terraform-infra/README.md](terraform-infra/README.md): `bootstrap` → `global` → `envs/dev`.

### 2. Konnect

1. Create control plane **`dev`**: API Gateway → New gateway → **Self-managed**, Kubernetes, Helm.
2. Data plane nodes → New data plane node → Kubernetes:
   - **Generate certificate**, download certificate + key, then:
     ```bash
     k8s-kong/scripts/put-konnect-cert.sh dev ~/Downloads/tls.crt ~/Downloads/tls.key
     ```
   - Copy the **image tag** and the **two hosts** into `k8s-kong/kong-dp/values-dev.yaml`.
   - Don't run the `helm install` shown there.
3. Organization → System accounts → create one for CI → **Generate token** (used by decK).

### 3. Repo settings (once)

- Create the GitHub repo **`Boutique-kong-api-gateway-konnect`** and push this folder to it
  (`git init && git add . && git commit -m "initial" && git branch -M main && git remote add origin
  https://github.com/Yaathvik2020/Boutique-kong-api-gateway-konnect.git && git push -u origin main`).
  Using another owner or name? Change it in `argocd/*/*.yaml` and `terraform-infra/bootstrap/terraform.tfvars`.
- `k8s-kong/overlays/*/kustomization.yaml`: replace `<account-id>`.
- Route 53: a **public hosted zone** for your domain must exist in this AWS account
  (`route53_zone_name` in `terraform-infra/envs/<env>/terraform.tfvars`).
- `k8s-kong/base/02-external-secrets.yml`: region, if not us-east-1.
- GitHub → Settings → Environments: `dev`, `staging`, `prod` (required reviewers on staging/prod).
  Per environment variable `KONG_PUBLIC_URL` = `https://api-dev.ksysglobaltech.online`,
  `https://api-staging.ksysglobaltech.online`, `https://api.ksysglobaltech.online`.
- Secrets: `AWS_CI_ROLE_ARN`, `AWS_TERRAFORM_ROLE_ARN` (bootstrap outputs), `KONNECT_TOKEN`.
  Variables: `AWS_ACCOUNT_ID`, `AWS_REGION`.
- Frontend Dockerfile accepts `ARG REACT_APP_API_URL` (see k8s-kong/README.md).

### 4. Deploy to the dev cluster

```bash
$(terraform -chdir=terraform-infra/envs/dev output -raw configure_kubectl)   # kubectl -> dev
# Fill k8s-kong/kong-dp/values-dev.yaml from the Terraform outputs:
terraform -chdir=terraform-infra/envs/dev output   # acm_certificate_arn, waf_acl_arn, kong_dp_role_arn,
                                                   # vpc_cidr, alb_logs_bucket, redis_host, redis_secret_name
git push                                       # Argo CD reads from Git: commit everything first
# Build images once: run the "ci" workflow (Actions -> ci -> Run workflow), wait until it commits the dev tags
kubectl apply -f argocd/dev/                   # Argo CD: boutique app + kong-dp
kubectl -n argocd get applications             # both Synced / Healthy
kubectl -n kong get pods                       # Kong data plane Ready = connected to Konnect
kubectl -n kong get ingress                    # ADDRESS = the ALB (created by the AWS LB controller)
# kong-config/envs/dev.env: DECK_REDIS_HOST (output redis_host), DECK_REDIS_SECRET (output redis_secret_name)
kong-config/deck.sh dev sync                   # token read from Secrets Manager: boutique/konnect-deck-token
dig +short api-dev.ksysglobaltech.online       # Route 53 record created by external-dns (1-2 min)
```

Check: Konnect → `dev` → Data plane nodes **Connected**; `curl https://api-dev.ksysglobaltech.online/api/products`
returns products; `http://` redirects to `https://`; AWS console → WAF → web ACL `boutique-dev-api` shows requests.

### 5. Staging, then prod

Repeat 1 (envs/staging, envs/prod), 2 (control planes `staging`, `prod`), 4 (`argocd/<env>/`,
`kong-dp/values-<env>.yaml` and `kong-config/envs/<env>.env` from that env's Terraform outputs, `deck.sh <env> sync`). Images come with `promote`, not CI. Prod's API is private: run kubectl from
the VPN/bastion/self-hosted runner.

## Operations

| Question | Where |
|---|---|
| Argo CD UI | `kubectl -n argocd port-forward svc/argocd-server 8080:80`, password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| Grafana | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` (Kong dashboard: import ID 7424) |
| Gateway analytics, data plane status, audit log | Konnect → control plane `<env>` |
| Roll back an app release | Revert the promote PR (or the CI commit in dev) → Argo CD rolls back |
| Roll back gateway config | `deck gateway sync <backup.yaml>` from the workflow artifact |
| Rate limiting | `rate-limiting-advanced`, 300/min per client IP per API, **one counter across all Kong pods** (ElastiCache Redis). Change limits in `kong-config/boutique.yaml` |
| What runs where | `kubectl -n boutique get deploy -o wide` / Argo CD UI |
| Migrate from the old single cluster | Build the new dev env next to it, test, switch DNS, then `terraform destroy` the old stack from the previous code version |
