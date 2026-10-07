# Nexus GitOps

This repository is the deployment source of truth for the Nexus Kubernetes
platform. Terraform creates AWS infrastructure; Helm describes Kubernetes
workloads; Argo CD will continuously reconcile this repository into EKS.

## Application chart

The `charts/nexus` chart deploys the frontend, API, and worker with consistent:

- non-root and read-only container security
- startup, liveness, and readiness probes
- CPU and memory requests and limits
- horizontal pod autoscaling
- pod disruption budgets
- topology spreading across availability zones
- service accounts compatible with EKS Pod Identity

Validate or render the chart locally:

```bash
make lint
make template
make lint-all
```

`ENVIRONMENT` selects the thin environment override and defaults to `dev`:

```bash
make template ENVIRONMENT=staging
make template ENVIRONMENT=production
```

Shared defaults remain in `charts/nexus/values.yaml`. The files under
`environments/` contain only values that differ between DEV, STAGING, and
PRODUCTION. This avoids copying the whole configuration and prevents drift.

Image tags must be immutable. The initial chart uses `0.1.0`; the application
pipeline will later update an environment to a commit SHA after publishing its
images instead of reusing mutable tags such as `latest` or `dev`.

The environment files intentionally leave AWS service endpoints in the shared
defaults until those environments exist. External Secrets integration will
supply credentials without putting them in Git.
