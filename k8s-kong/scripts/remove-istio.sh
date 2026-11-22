#!/usr/bin/env bash
# ONE-TIME MIGRATION for a cluster that already runs the old Kong + Istio setup.
# A new cluster built from terraform-infra does NOT need this.
#
# Order matters:
#   1. Deploy the new Kong-only manifests FIRST (Istio policies are removed,
#      NetworkPolicies + Kong health checks are added). Pods still have sidecars,
#      which keep working without the STRICT mTLS policy.
#   2. Then this script: stop sidecar injection, restart pods without sidecars,
#      uninstall Istio.
#
# Needs: kubectl, istioctl (same version as the installed Istio)
set -euo pipefail

echo "==> 0. Safety check: Istio policies must already be gone (step 1 done)"
if kubectl -n boutique get peerauthentication,authorizationpolicy 2>/dev/null | grep -q .; then
  echo "    Istio policies still exist in boutique."
  echo "    First deploy the new manifests:  sync the Argo CD boutique app (prune on),"
  echo "    then delete leftovers:           kubectl -n boutique delete peerauthentication,authorizationpolicy,virtualservice,destinationrule --all"
  exit 1
fi

echo "==> 1. Stop sidecar injection"
kubectl label namespace boutique istio-injection- --overwrite || true
kubectl label namespace kong istio-injection- --overwrite || true

echo "==> 2. Restart pods so they come back WITHOUT a sidecar"
kubectl -n kong rollout restart deployment
kubectl -n kong rollout status deployment --timeout=5m
kubectl -n boutique rollout restart deployment
kubectl -n boutique rollout restart statefulset boutique-postgres
kubectl -n boutique rollout status deployment --timeout=5m
kubectl -n boutique rollout status statefulset boutique-postgres --timeout=5m

echo "==> 3. Check: every pod should now be READY 1/1 (no istio-proxy container)"
kubectl -n boutique get pods
kubectl -n kong get pods
if kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].name}{"\n"}{end}' | grep -q istio-proxy; then
  echo "    Some pods still have istio-proxy. Restart them before uninstalling Istio."
  exit 1
fi

echo "==> 4. Uninstall Istio"
istioctl uninstall --purge -y
kubectl delete namespace istio-system --ignore-not-found

echo
echo "Istio removed. Run the tests in README.md (Kong routing, NetworkPolicies)."
