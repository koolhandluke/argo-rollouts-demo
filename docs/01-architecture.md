# Argo CD + Argo Rollouts: Architecture

**What this repo proves:** CI builds an image → Argo CD detects the tag commit in Git → Argo Rollouts executes the per-environment delivery strategy. No Kargo, no promotion orchestrator — promotion is a Git commit.

---

## Cluster Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          AWS EKS Cluster (single)                            │
│                                                                              │
│  ┌─────────────────────── Control Plane ──────────────────────────────────┐  │
│  │                                                                         │  │
│  │  ┌───────────────┐  ┌──────────────────┐  ┌──────────────────────┐    │  │
│  │  │    argocd     │  │  argo-rollouts   │  │      monitoring      │    │  │
│  │  │               │  │                  │  │                      │    │  │
│  │  │ API Server    │  │ Rollout          │  │ Prometheus           │    │  │
│  │  │ App Ctrl      │  │ Controller       │  │ (kube-prometheus-    │    │  │
│  │  │ Repo Server   │  │ Dashboard        │  │  stack)              │    │  │
│  │  │ AppSet Ctrl   │  │                  │  │                      │    │  │
│  │  └───────┬───────┘  └────────┬─────────┘  └──────────┬───────────┘    │  │
│  └──────────┼──────────────────┼─────────────────────────┼────────────────┘  │
│             │                  │                         │                   │
│  ┌──────────┼──────────────────┼─────────────────────────┼────────────────┐  │
│  │          │   Application Namespaces                   │                │  │
│  │          ▼                  ▼                         │                │  │
│  │  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────────┐    │  │
│  │  │ rollouts-dev │  │rollouts-staging│  │      rollouts-prod       │    │  │
│  │  │              │  │               │  │                          │    │  │
│  │  │ Rollout      │  │ Rollout       │  │ Rollout (canary)         │    │  │
│  │  │ (instant)    │  │ (blueGreen)   │  │ AnalysisRun ◄────────────┼────┘  │
│  │  │ Service      │  │ Active Svc    │  │ Stable Service           │    │  │
│  │  │              │  │ Preview Svc   │  │ Canary Service           │    │  │
│  │  └──────────────┘  └───────────────┘  └──────────────────────────┘    │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
       ▲  git sync (ApplicationSet)                     ▲  image pull
       │                                                │
┌──────┴───────────────────────┐           ┌────────────┴────────────┐
│  GitHub (gitops-manifests/)  │           │        AWS ECR          │
│                              │           │  demo-app:sha-<commit>  │
│  CI auto-commits image.tag   │           │  demo-app:<semver>      │
│  to shared-dev-values.yaml   │           └─────────────────────────┘
└──────────────────────────────┘
```

---

## Delivery Flow

**Dev** (automatic — every push to `main`):

```
Push to go-app/ on main
  → GitHub Actions builds image, pushes to ECR (sha-<commit>)
  → CI commits image.tag to environments/dev/shared-dev-values.yaml
  → Argo CD detects change, syncs rollouts-dev
  → Argo Rollouts executes instant strategy (100% immediately)
```

**Staging and prod** (manual promotion):

```
Edit shared-{env}-values.yaml (image.tag: <semver>)
  → commit + push to main
  → Argo CD detects change, syncs rollouts-{env}
  → Argo Rollouts executes blueGreen / canary strategy
```

---

## Repo Structure

```
argo-rollouts-demo/
├── go-app/
│   ├── cmd/server/                   # Go HTTP server
│   ├── deploy/demo-app/              # Base Helm chart — no env-specific values
│   └── Dockerfile
├── gitops-manifests/
│   ├── projects/demo-app/
│   │   ├── argo/
│   │   │   ├── applicationset.yaml   # Generates one Application per env/cluster dir
│   │   │   └── appproject.yaml
│   │   └── environments/
│   │       ├── dev/
│   │       │   ├── shared-dev-values.yaml       # CI writes image.tag here
│   │       │   └── cluster-default/
│   │       │       ├── kustomization.yaml        # Stacks chart + shared + override
│   │       │       └── values-override.yaml      # Static cluster config
│   │       ├── staging/
│   │       │   ├── shared-staging-values.yaml    # Manual edit on promotion
│   │       │   └── cluster-us-east/
│   │       └── prod/
│   │           ├── shared-prod-values.yaml       # Manual edit on promotion
│   │           └── cluster-us-west/
│   ├── clusters/                     # Cluster-wide resources (ECR pull secret)
│   └── shared/argo/analysis-templates/
│       └── prometheus-success-rate.yaml          # ClusterAnalysisTemplate
└── .github/workflows/
    ├── build-main.yaml               # SHA image + dev tag commit on push to main
    └── build-release.yaml            # Semver image + OCI Helm chart on git tag
```

---

## Namespace Topology

**Control plane:**

| Namespace | Contents |
|-----------|----------|
| `argocd` | Argo CD API server, application controller, repo server, applicationset controller |
| `argo-rollouts` | Argo Rollouts controller + dashboard |
| `monitoring` | Prometheus (kube-prometheus-stack) — scraped by canary AnalysisRun |

**Application namespaces:**

| Namespace | Argo CD Application | Strategy |
|-----------|---------------------|----------|
| `rollouts-dev` | `rollouts-dev-cluster-default` | instant |
| `rollouts-staging` | `rollouts-staging-cluster-us-east` | blueGreen (manual promote) |
| `rollouts-prod` | `rollouts-prod-cluster-us-west` | canary + AnalysisRun |

---

## Layered Stack

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 3 — CI (GitHub Actions)                              │
│  Builds images, pushes to ECR, writes image.tag to Git      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2 — GitOps Sync (Argo CD)                            │
│  ApplicationSet watches environments/*/                      │
│  Renders Helm chart via Kustomize, applies diff to cluster  │
├─────────────────────────────────────────────────────────────┤
│  Layer 1 — Progressive Delivery (Argo Rollouts)             │
│  Rollout CRD executes per-env strategy                      │
│  canary: replica-weighted split (no service mesh required)  │
│  blueGreen: preview pod + manual cutover                    │
│  analysis: ClusterAnalysisTemplate → Prometheus query       │
├─────────────────────────────────────────────────────────────┤
│  Layer 0 — Platform                                         │
│  AWS EKS + ECR, single cluster, namespace-per-environment   │
└─────────────────────────────────────────────────────────────┘
```

Each layer has one responsibility. Swapping a layer (e.g. Flagger for Argo Rollouts, or a different registry) only affects that layer.

---

## Key CRDs by Layer

### Argo CD — GitOps Sync (`argoproj.io/v1alpha1`)

| CRD | Scope | Role in this demo |
|-----|-------|-------------------|
| `AppProject` | Namespace | Defines source repos, destination clusters/namespaces, and RBAC boundaries for the `demo-app` project |
| `ApplicationSet` | Namespace | Single template that generates one `Application` per `environments/{env}/{cluster}` directory |
| `Application` | Namespace | One per environment (`rollouts-dev-cluster-default`, `rollouts-staging-cluster-us-east`, `rollouts-prod-cluster-us-west`). Reconciles Git → cluster continuously |

### Argo Rollouts — Progressive Delivery (`argoproj.io/v1alpha1`)

| CRD | Scope | Role in this demo |
|-----|-------|-------------------|
| `Rollout` | Namespace | Replaces `Deployment`. Owns the pod template and declares the delivery strategy (`instant` / `blueGreen` / `canary`). One per app namespace |
| `ClusterAnalysisTemplate` | Cluster | Defines the Prometheus success-rate query used to gate canary progression. Deployed once to `shared/argo/analysis-templates/`, referenced by name from every namespace |
| `AnalysisRun` | Namespace | Created automatically by the Rollout controller when the canary starts. Executes the `ClusterAnalysisTemplate` metrics; aborts and reverts on failure |

### Prometheus Operator — Observability (`monitoring.coreos.com/v1`)

| CRD | Scope | Role in this demo |
|-----|-------|-------------------|
| `ServiceMonitor` | Namespace | Tells Prometheus which pods to scrape. Deployed per app namespace via the Helm chart (`metrics.enabled: true`). Required for `AnalysisRun` queries to have data |

---

## Helm + Kustomize Layering

Each environment's `kustomization.yaml` stacks two value files on top of the base Helm chart:

```
go-app/deploy/demo-app/values.yaml      ← safe defaults (never edited)
  + shared-{env}-values.yaml            ← image.tag, strategy, replicas, loadgen
  + values-override.yaml                ← static cluster config (region, host, etc.)
```

The base chart has no environment-specific values. All environment behavior is injected by the overlay.

**Dev** (references local chart via `helmGlobals.chartHome`):

```yaml
# environments/dev/cluster-default/kustomization.yaml
helmGlobals:
  chartHome: ../../../../../../go-app/deploy

helmCharts:
  - name: demo-app
    releaseName: demo-app
    valuesFile: ../shared-dev-values.yaml
    additionalValuesFiles:
      - ./values-override.yaml
```

**Prod** (references versioned OCI chart from ECR — updated on each release):

```yaml
# environments/prod/cluster-us-west/kustomization.yaml
helmCharts:
  - name: demo-app
    repo: oci://819211779624.dkr.ecr.us-west-2.amazonaws.com/demo-app-chart
    version: "0.0.0"   # update to semver on promotion
    releaseName: demo-app
    valuesFile: ../shared-prod-values.yaml
    additionalValuesFiles:
      - ./values-override.yaml
```

Dev pulls from the local chart on disk (fast iteration, no chart publish required). Staging and prod pull a published OCI chart from ECR — the chart version is pinned and updated explicitly on promotion, giving an independent artifact trail.

**Helm naming note:** `releaseName: demo-app` matches `Chart.name: demo-app`. The `_helpers.tpl` `fullname` helper uses a `contains` guard — if the release name already includes the chart name, it returns the release name as-is instead of appending it again. Without this guard the Rollout would be named `demo-app-demo-app`.

---

## Per-Stage Rollout Strategies

The `rollout.strategy` key in `shared-{env}-values.yaml` controls which branch of the Rollout template renders:

| Env | Strategy | Steps | Replicas |
|-----|----------|-------|----------|
| dev | `instant` | `setWeight: 100` — immediate | 1 |
| staging | `blueGreen` | Preview pod starts; `autoPromotionEnabled: false` | 2 |
| prod | `canary` | `20% → pause {} → 50% → pause {} → 100%` | 3 |

The three strategies share one Rollout template in the Helm chart:

```yaml
# go-app/deploy/demo-app/templates/rollout.yaml (strategy section)

{{- if eq .Values.rollout.strategy "instant" }}
strategy:
  canary:
    steps:
      - setWeight: 100

{{- else if eq .Values.rollout.strategy "blueGreen" }}
strategy:
  blueGreen:
    activeService: demo-app-stable
    previewService: demo-app-canary
    autoPromotionEnabled: false

{{- else if eq .Values.rollout.strategy "canary" }}
strategy:
  canary:
    stableService: demo-app-stable
    canaryService: demo-app-canary
    # trafficRouting omitted — Rollouts uses replica-weighted traffic
    # approximation (basic K8s Services). No service mesh required for the demo.
    steps:
      - setWeight: 20
      - pause: {}
      - setWeight: 50
      - pause: {}
      - setWeight: 100
    analysis:
      templates:
        - templateName: prometheus-success-rate
      startingStep: 1
      args:
        - name: service-name
          value: demo-app-canary
{{- end }}
```

The prod canary pauses indefinitely at 20% and 50% (no `duration`), requiring a manual `kubectl argo rollouts promote` to advance — or an abort if the AnalysisRun fails.

### ClusterAnalysisTemplate

Deployed once per cluster to `shared/argo/analysis-templates/`. Referenced by name from every namespace — no per-environment duplication.

```yaml
# gitops-manifests/shared/argo/analysis-templates/prometheus-success-rate.yaml
apiVersion: argoproj.io/v1alpha1
kind: ClusterAnalysisTemplate
metadata:
  name: prometheus-success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 30s
      count: 3
      failureLimit: 1
      successCondition: result[0] >= 0.95
      provider:
        prometheus:
          address: http://prometheus-operated.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{status="2xx"}[2m]))
            /
            sum(rate(http_requests_total{}[2m]))
```

The AnalysisRun runs in parallel with the canary starting at step 1 (20% weight). It queries Prometheus every 30s for 3 measurements. If HTTP success rate drops below 95%, Argo Rollouts aborts and reverts to stable automatically. `loadgen.enabled: true` in `shared-prod-values.yaml` ensures traffic exists during the analysis window.

---

## Design Considerations

### Single Cluster, Namespace Isolation

The demo uses a single EKS cluster with namespace-per-environment:

- **Simpler to operate** — one kubeconfig, one set of controllers, one Argo CD instance
- **Sufficient to prove the model** — progressive delivery, analysis, and multi-environment promotion work identically in multi-cluster
- **Easy to extend** — Argo CD supports multiple destination servers natively; only `destination.server` in the ApplicationSet changes when adding clusters

**Production consideration:** Real workloads typically use separate clusters for prod (blast radius isolation, independent scaling, compliance boundaries). The delivery model here does not change — namespace references become cluster references.

### Git as Single Source of Truth

Every environment change is a Git commit:

- CI writes `image.tag` to `shared-dev-values.yaml` on every push to `main`
- Staging and prod promotions are a human edit to `shared-{env}-values.yaml` + a push
- Argo CD reconciles continuously — no out-of-band `kubectl apply`

Full audit trail, easy rollback (`git revert`), reproducibility. If the cluster is destroyed, `git + argocd sync` rebuilds every environment.

### Separation of Concerns

| Concern | Owner |
|---------|-------|
| What runs where | Argo CD — ApplicationSet generates Applications from Git |
| How it rolls out | Argo Rollouts — Rollout CRD executes the strategy |
| Whether it's healthy | Prometheus + AnalysisRun — metrics gate progression |
| When to advance | Human — `kubectl argo rollouts promote` at each pause step |

No component does two jobs. Each can be upgraded or replaced independently.

### Per-Stage Strategy via Values

Using a single Helm chart with `rollout.strategy` as a values key:

- Dev gets **instant rollout** — fast feedback, no ceremony
- Staging gets **blue-green** — validates the full release against a live preview before switching traffic
- Prod gets **canary with analysis** — gradual replica shift with automatic abort on metric degradation

Same chart, same templates, different behavior per environment. No chart duplication, no forking.

### Credential Scope

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| ECR pull secret | `rollouts-dev`, `rollouts-staging`, `rollouts-prod` | Pull application image |
| Git credentials | `argocd` | Read gitops repo |

ECR access via IRSA (IAM Roles for Service Accounts) on the node role or a dedicated service account — no static credentials, no rotation burden, automatic token refresh.

---

## Tradeoffs

| Decision | Upside | Downside | Mitigation |
|----------|--------|----------|------------|
| **Rollout CRD replaces Deployment** | Enables canary/blue-green natively; explicit strategy control per env | Apps must use Rollout instead of Deployment; migration cost for existing workloads | Rollout is a superset of Deployment — drop-in replacement with identical pod spec |
| **Replica-weighted canary (no service mesh)** | No Istio/Gateway API dependency; simpler setup for a demo | Traffic split is approximate — actual split depends on replica counts, not request weights | Sufficient for the demo; add `trafficRouting.plugins.gatewayAPI` to the Rollout for request-level precision |
| **Single Helm chart, strategy as a values key** | No chart duplication; per-stage behavior is a one-line diff | Helm complexity grows if strategies diverge significantly | Keep strategy branches thin — strategy-specific services and analysis live in the chart, not in overlays |
| **Manual promotion for staging/prod** | Enforces a human gate at every environment boundary without a promotion orchestrator | Requires a deliberate edit + push; no approval audit trail in the tool itself | Git commit history is the audit trail; add PR-based promotion for a formal review step |
| **`shared-{env}-values.yaml` as the promotion record** | Single file to edit, clear diff on every promotion | All environment config in one file — mixing promotion-time and static config | `values-override.yaml` holds static cluster config; `shared-{env}-values.yaml` holds only what changes on promotion |
| **Single cluster for the demo** | Simple to operate; one kubeconfig | No blast-radius isolation between environments | Namespace-level RBAC; the architecture supports multi-cluster without changing the delivery model |
| **Prometheus for analysis** | Already needed for observability; no extra infra | Requires the app to expose HTTP metrics; NaN results if no traffic during analysis window | App exposes `/metrics`; `loadgen.enabled: true` in prod ensures traffic during analysis windows |

---

## CI Workflows

### `build-main.yaml` — push to `main`

1. Build and push `819211779624.dkr.ecr.us-west-2.amazonaws.com/demo-app:sha-<commit>`
2. Commit `image.tag: sha-<commit>` to `environments/dev/shared-dev-values.yaml`
3. Push commit to `main` — Argo CD auto-syncs dev

### `build-release.yaml` — git tag (`v*`)

1. Build and push `demo-app:<semver>` (e.g. `1.2.3`)
2. Package and push OCI Helm chart to ECR
3. No automatic gitops commit — staging/prod promotion is manual
