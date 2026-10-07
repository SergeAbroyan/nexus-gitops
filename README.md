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
```

The default values intentionally leave AWS endpoints and the ECR registry empty.
Environment-specific values and External Secrets integration will supply them
without putting credentials in Git.
