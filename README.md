# Nexus GitOps

This repository is the deployment source of truth for the Nexus Kubernetes
platform. Terraform creates AWS infrastructure; Helm describes Kubernetes
workloads; Argo CD will continuously reconcile this repository into EKS.

## GitOps bootstrap

After Terraform creates EKS and `kubectl` points to the cluster, bootstrap the
GitOps controller and register the root applications:

```bash
make bootstrap-argocd
make bootstrap-root
```

`bootstrap-argocd` installs the pinned Argo CD chart. `bootstrap-root` creates a
restricted Argo CD project and registers External Secrets. After these two
commands, Argo CD owns the managed platform components; do not install those
components manually.

External Secrets uses the `external-secrets` service account. Its name and
namespace exactly match the EKS Pod Identity association created by Terraform.

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

## Database credentials

The application chart can synchronize the RDS-managed password from AWS
Secrets Manager. After Terraform creates an environment, set its RDS secret ARN
and enable synchronization in that environment's values file:

```yaml
externalSecret:
  enabled: true
  remoteSecretKey: arn:aws:secretsmanager:REGION:ACCOUNT:secret:rds-secret
```

The External Secrets controller uses EKS Pod Identity. The `SecretStore`
therefore contains no static credentials, IAM role annotation, or authentication
block. It creates the `nexus-database` Kubernetes Secret consumed by the API.
