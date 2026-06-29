# Argo CD + Argo Rollouts: Architecture

**What this repo proves:** CI builds an image → Argo CD detects the tag commit in Git → Argo Rollouts executes the per-environment delivery strategy. No Kargo, no promotion orchestrator — promotion is a Git commit.

---

## Delivery Flow

```
Push to go-app/ on main
  → GitHub Actions builds image, pushes to ECR (sha-<commit>)
  → CI commits image.tag to environments/dev/shared-dev-values.yaml
  → Argo CD detects change, syncs rollouts-dev
  → Argo Rollouts executes instant strategy (100% immediately)
```

For staging and prod (manual promotion):

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
│   ├── deploy/helm/                  # Base Helm chart — no env-specific values
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

---

## Helm + Kustomize Layering

Each environment's `kustomization.yaml` stacks two value files on top of the base Helm chart:

```
go-app/deploy/helm/values.yaml          ← safe defaults (never edited)
  + shared-{env}-values.yaml            ← image.tag, strategy, replicas, loadgen
  + values-override.yaml                ← static cluster config (region, host, etc.)
```

The base chart has no environment-specific values. All environment behavior is injected by the overlay.

---

## Per-Stage Rollout Strategies

The `rollout.strategy` key in `shared-{env}-values.yaml` controls which branch of the Rollout template runs:

| Env | Strategy | Steps | Replicas |
|-----|----------|-------|----------|
| dev | `instant` | `setWeight: 100` — immediate | 1 |
| staging | `blueGreen` | Preview pod starts; `autoPromotionEnabled: false` | 2 |
| prod | `canary` | `20% → pause {} → 50% → pause {} → 100%` | 3 |

Prod canary uses replica-weighted traffic splitting — no Istio or Gateway API required for the POC.

The `ClusterAnalysisTemplate` (`prometheus-success-rate`) runs in parallel with the canary starting at step 1. It queries Prometheus every 30s for 3 measurements. If the HTTP success rate drops below 95%, Argo Rollouts aborts automatically and reverts to stable.

---

## Key Design Decisions

**Single Helm chart, no duplication.** Strategy is a values key. The same chart produces the correct behavior for all three environments.

**`shared-{env}-values.yaml` is the promotion record.** The only field that changes on promotion is `image.tag`. This is the single source of truth for what is deployed to each environment.

**CI writes to dev only.** SHA-tagged images auto-promote to dev. Staging and prod require a deliberate human edit. This enforces a promotion gate at every environment boundary without needing Kargo.

**`ClusterAnalysisTemplate` (not namespace-scoped).** Deployed once per cluster via `shared/argo/analysis-templates/`. All environment namespaces reference it by name — no duplication across dev/staging/prod.

**ECR pull secret via placeholder.** `gitops-manifests/clusters/{env}/{cluster}/ecr-pull-secret.yaml` are placeholders. IRSA (IAM Roles for Service Accounts) is the production solution — no secret rotation, automatic token refresh.

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
