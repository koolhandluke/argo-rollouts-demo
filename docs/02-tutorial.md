# Operations Guide: Triggering Deployments & Watching Rollouts

Open [`argo-links.html`](./argo-links.html) in your browser for one-click port-forwards and copy-paste commands covering everything below.

## Prerequisites

- `kubectl` configured for the target cluster
- `kubectl argo rollouts` plugin ([install guide](https://argoproj.github.io/argo-rollouts/installation/#kubectl-plugin-installation))
- Argo CD UI or `argocd` CLI access
- Prometheus running in `monitoring` namespace (required for prod analysis)

---

## First-Time Bootstrap

Apply the AppProject and ApplicationSet once. Argo CD generates all three Applications automatically by scanning `environments/*/*`.

```bash
kubectl apply -f gitops-manifests/projects/demo-app/argo/appproject.yaml
kubectl apply -f gitops-manifests/projects/demo-app/argo/applicationset.yaml
```

Verify:

```bash
kubectl get applications -n argocd | grep rollouts
# rollouts-dev-cluster-default      Synced  Healthy
# rollouts-staging-cluster-us-east  Synced  Healthy
# rollouts-prod-cluster-us-west     Synced  Healthy
```

---

## Dev — Automatic (CI-Driven)

Every push to `main` in `go-app/` triggers `build-main.yaml`:
1. Builds and pushes a SHA image to ECR
2. Commits the new `image.tag` to `environments/dev/shared-dev-values.yaml`
3. Argo CD auto-syncs `rollouts-dev`
4. Argo Rollouts executes the instant strategy (100% immediately, no gates)

No manual action needed for dev.

To deploy a specific tag to dev without a code change:

```bash
# Edit the tag
vim gitops-manifests/projects/demo-app/environments/dev/shared-dev-values.yaml

git add gitops-manifests/projects/demo-app/environments/dev/shared-dev-values.yaml
git commit -m "chore: deploy sha-<new> to dev"
git push origin main
```

Verify:

```bash
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-dev

kubectl get pods -n rollouts-dev \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```

---

## Staging — BlueGreen (Manual Promotion)

Edit `shared-staging-values.yaml` with the semver tag you want to promote:

```yaml
# gitops-manifests/projects/demo-app/environments/staging/shared-staging-values.yaml
image:
  tag: "1.2.3"   # ← update this
```

```bash
git add gitops-manifests/projects/demo-app/environments/staging/shared-staging-values.yaml
git commit -m "chore: promote demo-app 1.2.3 to staging"
git push origin main
```

Force sync immediately (instead of waiting ~3 min):

```bash
kubectl annotate application rollouts-staging-cluster-us-east -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Watch the BlueGreen Rollout

```bash
# Watch — pauses when preview pod is ready (stable still serving)
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-staging --watch

# Promote: cut traffic from stable → preview
kubectl argo rollouts promote demo-app-demo-app -n rollouts-staging

# Abort: keep stable, delete preview
kubectl argo rollouts abort demo-app-demo-app -n rollouts-staging
```

---

## Prod — Canary + Analysis (Manual Promotion)

Edit `shared-prod-values.yaml` with the semver tag:

```yaml
# gitops-manifests/projects/demo-app/environments/prod/shared-prod-values.yaml
image:
  tag: "1.2.3"   # ← update this
```

```bash
git add gitops-manifests/projects/demo-app/environments/prod/shared-prod-values.yaml
git commit -m "chore: promote demo-app 1.2.3 to prod"
git push origin main
```

> **Note:** `loadgen.enabled: true` is set in `shared-prod-values.yaml`. Wait ~2 minutes after first deploy for Prometheus to have data, or the AnalysisRun will get inconclusive results.

### Watch the Canary Rollout

Canary steps: `setWeight 20 → pause {} → setWeight 50 → pause {} → setWeight 100`

AnalysisRun starts at step 1 (after 20% weight) and runs Prometheus checks every 30s. Auto-aborts if success rate < 95%.

```bash
# Watch rollout progression and current step
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-prod --watch

# Watch AnalysisRun (one created per rollout)
kubectl get analysisruns -n rollouts-prod -w

# Inspect analysis measurements
kubectl get analysisrun <name> -n rollouts-prod \
  -o jsonpath='{.status.metricResults}' | python3 -m json.tool

# Advance past a manual pause (once satisfied with canary health)
kubectl argo rollouts promote demo-app-demo-app -n rollouts-prod

# Abort and revert to stable
kubectl argo rollouts abort demo-app-demo-app -n rollouts-prod

# Retry after abort
kubectl argo rollouts retry rollout demo-app-demo-app -n rollouts-prod
```

### Force Sync

```bash
kubectl annotate application rollouts-prod-cluster-us-west -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## Simulate a Failure (Prod Canary)

To test automatic rollback, cause the canary pod to return errors during the analysis window:

```bash
# Find a canary pod
kubectl get pods -n rollouts-prod -l rollouts-pod-template-hash=<canary-hash>

# Exec in and hit a 5xx endpoint
kubectl exec -n rollouts-prod <pod> -- wget -qO- http://localhost:8080/fail

# Watch the AnalysisRun detect the degraded success rate and abort
kubectl get analysisruns -n rollouts-prod -w
```

The AnalysisRun will record a failure measurement. After `failureLimit: 1` failures, it marks itself `Failed`, and Argo Rollouts immediately aborts the canary and reverts to stable.

---

## Verify: Full State Snapshot

```bash
# All Argo CD apps in this demo
kubectl get applications -n argocd | grep rollouts

# Rollout status per environment
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-dev
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-staging
kubectl argo rollouts get rollout demo-app-demo-app -n rollouts-prod

# AnalysisRuns for prod (one per rollout)
kubectl get analysisruns -n rollouts-prod

# What image is running in each environment
for ns in rollouts-dev rollouts-staging rollouts-prod; do
  echo "$ns: $(kubectl get pods -n $ns -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)"
done
```

---

## Common States

| sync.status | health.status | Meaning |
|---|---|---|
| Synced | Healthy | All good |
| OutOfSync | Healthy | Git change not yet applied |
| Synced | Progressing | Rollout in progress |
| OutOfSync | Degraded | Something broken — check `kubectl describe` |

---

## UI Access

| UI | Port-forward | Address |
|----|-------------|---------|
| Argo CD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 |
| Rollouts Dashboard | `kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100` | http://localhost:3100/rollouts |
| Prometheus (prod analysis) | `kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090` | http://localhost:9090 |
