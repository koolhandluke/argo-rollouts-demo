# argo-rollouts-demo

Progressive delivery demo: Argo CD + Argo Rollouts, no Kargo.

CI auto-promotes to dev on every push to `main`. Staging and prod are promoted manually via a values file edit + push.

## Quick Start

```bash
# Bootstrap ArgoCD (one-time)
kubectl apply -f gitops-manifests/projects/demo-app/argo/appproject.yaml
kubectl apply -f gitops-manifests/projects/demo-app/argo/applicationset.yaml
```

Open [`docs/argo-links.html`](docs/argo-links.html) in your browser for clickable port-forwards and quick-copy commands.

## Docs

| Doc | What it covers |
|-----|----------------|
| [`docs/01-architecture.md`](docs/01-architecture.md) | Repo structure, delivery flow, layered stack, design decisions |
| [`docs/02-tutorial.md`](docs/02-tutorial.md) | Trigger deploys, watch rollouts, promote/abort, verify state |
| [`docs/argo-links.html`](docs/argo-links.html) | Quick-access UI links and copy-paste commands |

## Namespaces

| Env | Namespace | Strategy |
|-----|-----------|----------|
| dev | `rollouts-dev` | instant (CI auto-promotes) |
| staging | `rollouts-staging` | blueGreen (manual promote) |
| prod | `rollouts-prod` | canary + AnalysisRun |

## Repo Layout

```
go-app/                          # Go HTTP server + Helm chart
gitops-manifests/
  projects/demo-app/
    argo/                        # ApplicationSet + AppProject
    environments/
      {env}/shared-{env}-values.yaml   # image.tag — the only file edited on promotion
      {env}/{cluster}/kustomization.yaml
  clusters/                      # ECR pull secrets (per cluster)
  shared/argo/analysis-templates/      # ClusterAnalysisTemplate (Prometheus)
.github/workflows/
  build-main.yaml                # SHA image + dev auto-promotion
  build-release.yaml             # Semver image + OCI Helm chart
```
