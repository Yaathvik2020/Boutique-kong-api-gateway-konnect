# k8s-kong — what runs inside each EKS cluster

Deployed by Argo CD from Git (`argocd/<env>/`). Two Applications per cluster:

| Argo CD app | Source | Namespace |
|---|---|---|
| `boutique` | `k8s-kong/overlays/<env>` (Kustomize) | `boutique` (+ the Kong cert ExternalSecret in `kong`) |
| `kong-dp` | Helm chart `kong/kong` + `k8s-kong/kong-dp/values.yaml` + `values-<env>.yaml` | `kong` |

```
 client ─► Route 53 (external-dns) ─► ALB: ACM TLS + AWS WAF (AWS Load Balancer Controller)
                                         │ HTTP inside the VPC, health check :8100/status/ready
 Konnect control plane "<env>"  (routes, plugins from ../kong-config via decK)
          │ mTLS: config down, telemetry up
          ▼
 ┌──────────────── namespace kong ────────────────┐
 │ Kong data planes  (behind ALB + WAF, HTTPS)     │
 │  /  /api/auth  /api/products  /api/orders  ...  │
 └───────────────────────┬────────────────────────┘
                         │ straight to pods (headless <name>-pods Services)
 ┌────────────── namespace boutique ─────────────────────────────────┐
 │ NetworkPolicies: deny all, allow only the arrows                   │
 │ frontend  auth  product-service  orders  user-service  order-service│
 │                         │                                          │
 │   dev: Postgres pod     │   staging/prod: Amazon RDS (outside)     │
 └────────────────────────────────────────────────────────────────────┘
 Secrets: AWS Secrets Manager boutique/<env>/* ──External Secrets──► Kubernetes Secrets
```

## Folders

| Path | What |
|---|---|
| `base/01-namespace.yml` | `boutique` and `kong` namespaces |
| `base/02-external-secrets.yml` | `ClusterSecretStore` (AWS Secrets Manager) + `ExternalSecret`s: `boutique-secrets` (DB URLs, JWT), `kong/kong-cluster-cert` (Konnect certificate). The Redis password is **not** synced: Kong reads it from Secrets Manager itself |
| `base/03-database/` | One-time Job loading `boutique_full.sql` into the env's database (Postgres pod or RDS) |
| `base/04-backend/`, `base/05-frontend/` | Deployments, Services, headless `<name>-pods` Services for Kong |
| `base/06-network-policy/` | Who may call whom |
| `base/08-monitoring/` | Prometheus scraping of the services and the Kong data planes |
| `components/in-cluster-postgres/` | Postgres StatefulSet, **dev only** |
| `overlays/dev/` | Image tags (CI updates them), `boutique/dev/*` secrets, 1 replica, + Postgres pod |
| `overlays/staging/` | Promoted image tags, `boutique/staging/*`, HPA 2–4, PDB 1, zone spread, RDS |
| `overlays/prod/` | Promoted image tags, `boutique/prod/*`, HPA 3–10, PDB 2, zone spread, RDS Multi-AZ |
| `kong-dp/values*.yaml` | Kong data planes: shared settings (ALB Ingress, IAM service account, client IP from X-Forwarded-For) + per env (hostname, ACM/WAF ARNs, IAM role, Konnect hosts, image tag, size) |
| `scripts/put-konnect-cert.sh` | Upload the Konnect certificate for an env to Secrets Manager |
| `scripts/remove-istio.sh` | Only for a cluster still running the old Istio setup |

Preview what an environment gets: `kustomize build k8s-kong/overlays/prod`.

## Per-environment differences

| | dev | staging | prod |
|---|---|---|---|
| App pods per service | 1 | 2–4 (HPA) | 3–10 (HPA) |
| PodDisruptionBudget | — | min 1 | min 2 |
| Spread over AZs/nodes | — | yes | yes |
| Database | Postgres pod (EBS gp3) | RDS | RDS Multi-AZ |
| Kong data planes | 1 | 2–4 (HPA) | 3–10 (HPA), PDB 2, AZ spread |
| Rate-limit counters | Redis, 1 node | Redis, 1 node | Redis, 2 nodes + failover |
| Image tags set by | `ci` workflow | `promote` PR | `promote` PR |

## Who may call whom (`base/06-network-policy/network-policy.yml`)

| Caller | → Allowed |
|---|---|
| Kong (namespace `kong`) | frontend, auth, product-service, orders, user-service |
| orders, order-service | product-service |
| backends + restore Job | Postgres pod (dev) |
| Prometheus (namespace `monitoring`) | backend ports |

Everything else is dropped. Enforced by the VPC CNI (enabled in `terraform-infra/modules/eks`).

## Rate limiting (Redis)

`rate-limiting-advanced` on each API: **300 requests per minute per client IP**, sliding window,
counted in ElastiCache Redis so the limit is the same with 1 or 10 Kong pods.

```
 client ─► Kong pod A ─┐
 client ─► Kong pod B ─┼─► Redis (one counter per IP per API)  ── over limit ──► 429 Too Many Requests
 client ─► Kong pod C ─┘     every 0.5 s (sync_rate)
```

- Redis host: `kong-config/envs/<env>.env` (from `terraform output redis_host`)
- Redis password: Secrets Manager `boutique-<env>-kong-redis`, read by Kong at runtime through its
  AWS vault (`{vault://aws-sm/boutique-<env>-kong-redis/password}`) with the IAM role
  `boutique-<env>-kong-dp` (service account `kong/kong-dp`, read access to that one secret only)
- Client IP: the ALB sends `X-Forwarded-For`; Kong trusts it from the VPC CIDR (`trusted_ips`), so
  limits are per real client, not per ALB node
- TLS to Redis with certificate verification (`ssl_verify: true`)
- If Redis is unreachable, Kong logs errors and keeps serving traffic (fail open). The AWS WAF
  rate rule (per IP per 5 minutes) still applies. Test this in staging (`kubectl -n kong` NetworkPolicy blocking port 6379).

## Timeouts, retries, health checks

Defined in `kong-config/boutique.yaml` (same for every env): product-service 3 s / 10 s / 3 retries;
orders, auth, user-service 5 s / 30 s / **0 retries** (never send an order twice); frontend 3 s / 10 s / 2.
Kong health-checks every pod (`/health`, every 10 s) and drops a pod after 5 errors or 3 timeouts.

## Frontend image

React bakes `REACT_APP_API_URL` in at build time. CI passes `--build-arg REACT_APP_API_URL=/api`;
`projects/boutique-microservices/frontend/Dockerfile` must have, before `npm run build`:

```dockerfile
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
```

## Test an environment

```bash
KONG=https://api-dev.ksysglobaltech.online             # this env's api_hostname
kubectl -n kong get ingress                             # ALB address
curl -I http://api-dev.ksysglobaltech.online/           # 301 -> https (ALB redirect)
curl -I $KONG/                                          # 200 website (TLS by ACM)
curl    $KONG/api/products                       # products
curl -i $KONG/api/products | grep -i x-request-id
curl    $KONG/api/nothing                        # 404 no route

# NetworkPolicy: outside pod blocked (exit 28 = timeout)
kubectl run t --rm -i --restart=Never -n default --image=curlimages/curl -- curl -s -m 5 http://user-service.boutique:3006/health; echo "exit=$?"
# user-service may NOT call orders / orders MAY call product-service
kubectl -n boutique exec deploy/user-service -- wget -q -T 5 -O- http://orders:3005/health
kubectl -n boutique exec deploy/orders -- wget -q -T 5 -O- http://product-service:3003/health

# Rate limit is shared across ALL Kong pods: ~300 x 200, the rest 429
# (with 3 pods and a per-pod counter you'd see ~600-900 x 200 instead)
for i in $(seq 1 400); do curl -s -o /dev/null -w "%{http_code}\n" $KONG/api/products; done | sort | uniq -c
curl -si $KONG/api/products | grep -i ratelimit      # RateLimit-Remaining etc.

# Secrets synced from AWS
kubectl get externalsecret -A                           # STATUS SecretSynced
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `ExternalSecret` not `SecretSynced` | Secret missing in Secrets Manager (`boutique/<env>/…`), wrong region in `base/02-external-secrets.yml`, or the Konnect cert not uploaded yet |
| Kong pods `ContainerCreating` | `kong/kong-cluster-cert` not created yet (see above) |
| Kong pods `0/1`, clustering/cert errors | Hosts in `values-<env>.yaml` and certificate come from different control planes |
| Every request 404 "no Route matched" | `kong-config/deck.sh <env> sync` not run, or wrong control plane name |
| App pods `ImagePullBackOff` with tag `initial` | CI hasn't run yet (dev) / nothing promoted yet (staging, prod) |
| Restore Job fails on RDS with SSL error | `PGSSLMODE` must be `require` in `boutique/<env>/app` (Terraform sets it) |
| HPA shows `<unknown>` | metrics-server not ready, or pod has no CPU request |
| Kong logs `failed to connect to redis` / `NOAUTH` | Wrong `DECK_REDIS_HOST` / `DECK_REDIS_SECRET` in `kong-config/envs/<env>.env` |
| Kong logs vault / `AccessDenied` for secretsmanager | Wrong role ARN annotation in `values-<env>.yaml`, or the service account isn't `kong-dp` |
| Ingress has no ADDRESS | AWS Load Balancer Controller logs (`kubectl -n kube-system logs deploy/aws-load-balancer-controller`): usually a wrong certificate or WAF ARN |
| DNS name doesn't resolve | external-dns logs (`kubectl -n kube-system logs deploy/external-dns`); the zone must be public and match `route53_zone_name` |
| ALB returns 503 | No healthy targets: Kong pods not Ready (no config from Konnect yet) |
| 403 from the ALB | Blocked by AWS WAF: check the web ACL's sampled requests |
| Rate limit ~N× higher than 300 | Plugin still `rate-limiting` with `policy: local`, or Redis errors (fail open): check Kong logs |
| `could not find vault (aws-sm)` | decK sync didn't create the `vaults` entry: run `deck.sh <env> diff` |
| NetworkPolicy tests pass when they should be blocked | VPC CNI without `enableNetworkPolicy` |
