# argo-rollouts-demo

Progressive delivery demo: Argo CD + Argo Rollouts, no Kargo.

CI auto-promotes to dev on every push to `main`. Staging and prod are promoted manually via a values file edit + push.

## Quick Start

```bash
# Bootstrap ArgoCD (one-time)
kubectl apply -f gitops-manifests/clusters/shared/bootstrap-app.yaml
kubectl apply -f gitops-manifests/projects/demo-app/argo/appproject.yaml
kubectl apply -f gitops-manifests/projects/demo-app/argo/applicationset.yaml
```

Open [`docs/argo-links.html`](docs/argo-links.html) in your browser for clickable port-forwards and quick-copy commands.

## Running Locally (OrbStack / kind)

The `shared-{env}-values.yaml` files are set up for local use by default.

**1. Build the image once:**

```bash
docker build -t demo-app:local ./go-app
```

**2. Bootstrap (same as above) — done.**

Argo CD pulls the chart from this repo and the image from the local Docker store. No registry needed.

**Switching to AWS/ECR:**

In each `shared-{env}-values.yaml`, comment out the local block and uncomment the ECR block:

```yaml
# Local (default)
image:
  repository: demo-app
  tag: "local"
  # repository: 819211779624.dkr.ecr.us-west-2.amazonaws.com/demo-app
  # tag: "sha-<commit>"

# AWS/ECR — swap to this:
# image:
#   repository: 819211779624.dkr.ecr.us-west-2.amazonaws.com/demo-app
#   tag: "sha-<commit>"
```

CI (`build-main.yaml`) writes the ECR tag automatically on push to `main` when running against AWS.

## Docs

| Doc | What it covers |
|-----|----------------|
| [`docs/01-architecture.md`](docs/01-architecture.md) | Repo structure, delivery flow, layered stack, design decisions |
| [`docs/02-tutorial.md`](docs/02-tutorial.md) | Trigger deploys, watch rollouts, promote/abort, verify state |
| [`docs/argo-links.html`](docs/argo-links.html) | Quick-access UI links and copy-paste commands |

## Namespaces

| Env | Namespace | Strategy |
|-----|-----------|----------|
| dev | `demo-dev` | instant (CI auto-promotes) |
| staging | `demo-staging` | blueGreen (manual promote) |
| prod | `demo-prod` | canary + AnalysisRun |

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
