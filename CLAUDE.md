# CLAUDE.md

GitOps demo repo: Argo CD + Argo Rollouts without Kargo.
Promotion is manual — update `image.tag` in `projects/demo-app/environments/{env}/shared-{env}-values.yaml` and open a PR.
CI auto-commits `image.tag` to dev on every push to `main`.

## Layout

| Path | Purpose |
|------|---------|
| `go-app/cmd/server/` | Go HTTP server entry point |
| `go-app/deploy/demo-app/` | Base Helm chart — no env-specific values |
| `go-app/Dockerfile` | Two-stage distroless build |
| `gitops-manifests/projects/demo-app/argo/` | ApplicationSet + AppProject |
| `gitops-manifests/projects/demo-app/environments/{env}/shared-{env}-values.yaml` | image.tag lives here — the only file edited during promotion |
| `gitops-manifests/projects/demo-app/environments/{env}/{cluster}/kustomization.yaml` | Layers chart + shared values + cluster overrides |
| `gitops-manifests/projects/demo-app/environments/{env}/{cluster}/values-override.yaml` | Static cluster config — never edited during promotion |
| `gitops-manifests/clusters/{env}/{cluster}/` | Cluster-wide resources (ECR pull secret) |
| `gitops-manifests/shared/argo/analysis-templates/` | ClusterAnalysisTemplate deployed to every cluster |

## Commands

```bash
cd go-app && go test ./...
helm lint go-app/deploy/demo-app --set image.repository=test --set image.tag=test
helm template demo-app go-app/deploy/demo-app \
  -f gitops-manifests/projects/demo-app/environments/prod/shared-prod-values.yaml
```

## Namespaces

| Env | Namespace |
|-----|-----------|
| dev | rollouts-dev |
| staging | rollouts-staging |
| prod | rollouts-prod |

## Docs

| File | Purpose |
|------|---------|
| `docs/01-architecture.md` | Repo structure, delivery flow, design decisions |
| `docs/02-tutorial.md` | Operational how-to: trigger, watch, promote, abort |
| `docs/argo-links.html` | Quick-access UI links and copy-paste kubectl commands |
