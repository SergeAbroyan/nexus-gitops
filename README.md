# Nexus GitOps

This repository is the deployment source of truth for the Nexus Kubernetes
platform. Terraform creates AWS infrastructure; Helm describes Kubernetes
workloads; Argo CD will continuously reconcile this repository into EKS.

## Repository structure

```text
charts/applications/nexus/      Frontend, API, and worker Helm chart
charts/platform/karpenter/      Node provisioning configuration
charts/platform/storage/        Encrypted EBS StorageClass
charts/platform/ingress/        Internal Istio gateway routing
charts/tools/cloudbeaver/       Internal database administration UI
environments/<environment>/     Environment-specific Nexus values
```

Every deployable project-owned Helm chart lives below `charts/`. This repository
does not contain Argo CD `Application` or `ApplicationSet` resources.

## GitOps bootstrap

Terraform installs the pinned Argo CD Helm release after creating EKS. That
release seeds one restricted AppProject and three focused ApplicationSets:

- external platform charts such as Istio and Karpenter;
- local platform and operations charts from this repository;
- Nexus application environments.

The ownership chain is:

```text
Terraform/Terragrunt -> Argo CD -> ApplicationSets -> Helm charts
```

ApplicationSet definitions and infrastructure-derived Helm values live in the
Terraform Argo CD module. This keeps service registration in one location and
avoids duplicating pointer files in this repository.

External Secrets uses the `external-secrets` service account. Its name and
namespace exactly match the EKS Pod Identity association created by Terraform.

The external-platform ApplicationSet installs the essential cluster controllers:

- Metrics Server supplies resource metrics to the Horizontal Pod Autoscalers.
- AWS Load Balancer Controller manages AWS load balancers for Kubernetes.
- ExternalDNS publishes annotated load-balancer Services in the delegated
  Route 53 zone.
- Karpenter CRDs are managed separately from the Karpenter controller so they
  can be upgraded safely.

Terraform injects the EKS cluster name, AWS region, VPC ID, Karpenter
interruption queue, node IAM role, KMS key, and managed-service endpoints into
the generated Argo CD Applications.

## Karpenter capacity

The `charts/platform/karpenter` chart defines one hardened EC2 node class and three
capacity pools:

- `system` uses On-Demand capacity for platform controllers.
- `general` uses On-Demand capacity for the frontend and API.
- `spot` is tainted and accepts only explicitly tolerant workloads such as the
  asynchronous worker.

Karpenter discovers private subnets and the EKS node security group through the
`karpenter.sh/discovery` tag created by Terraform. The default AL2023 alias tracks
the latest EKS-optimized image for DEV. Pin `amiAlias` to a tested release before
promoting the configuration to production.

## Nexus application delivery

The Nexus ApplicationSet generates one Argo CD application for the environment
being created by Terraform. Argo CD combines two sources of values:

1. `environments/<environment>/values.yaml` contains versioned operational
   choices such as replica counts and scaling limits.
2. Terraform injects non-secret AWS outputs such as service endpoints, the ECR
   registry, and the RDS Secrets Manager ARN.

External Secrets reads the password from that ARN inside EKS. The password is
never placed in Terraform state, Argo CD parameters, or Git.

## Istio service mesh

The external-platform ApplicationSet installs Istio base, Istio CNI, and Istiod
at the same pinned version. Istio CNI removes the need for privileged init
containers in application pods. The Nexus chart owns its namespace labels,
enables automatic sidecar injection, and enforces the Restricted Pod Security
Standard.

The Nexus chart creates a namespace-wide `PeerAuthentication` policy in
`STRICT` mode, so mesh traffic must use mutual TLS. External AWS service traffic
remains allowed until explicit ServiceEntry policies are introduced.

## Application observability

The Nexus chart creates a PodMonitor for the frontend, API, and worker. Istio
merges each application's `/metrics` endpoint into its monitoring endpoint, so
Prometheus scrapes port `15020` without weakening the namespace's strict mTLS
policy. The worker therefore remains without a Kubernetes Service.

The chart also creates Prometheus alerts for an unavailable scrape target, an
elevated Istio 5xx response rate, and sustained high 95th-percentile request
latency. The alert durations and thresholds are chart values, so each
environment can tune them without modifying the templates. Terraform configures
the Prometheus Operator selectors to discover PodMonitor and PrometheusRule
resources in the Nexus namespace.

The chart supplies every service with the internal OpenTelemetry trace-gateway
endpoint and the current deployment environment. Application spans are sent to
the gateway, then batched and forwarded to Tempo. The endpoint is a shared chart
setting because all Nexus services use the same in-cluster collector; individual
service `env` lists remain available for service-specific overrides. The shared
1% sampling ratio also covers root spans created by asynchronous workers.

The version-controlled `Nexus Overview` Grafana dashboard shows target
availability, application request rate, CPU usage, memory working set, Istio
5xx ratio, and 95th-percentile request latency by destination service. Grafana's
sidecar discovers the dashboard ConfigMap across namespaces, so no dashboard
needs to be imported manually.

The `charts/platform/ingress` chart owns the shared Istio `Gateway` and Nexus
route. `/api` traffic goes to the API service and all other paths go to the
frontend. Port 80 redirects to HTTPS. The internal AWS NLB terminates TLS with
the ACM certificate supplied by Terraform and forwards decrypted HTTP to the
gateway's port 8443. ExternalDNS creates the hostname from the Service
annotation. Because the NLB remains internal, clients still need VPC network
access; Grafana and CloudBeaver remain unexposed.

## CloudBeaver

The `charts/tools/cloudbeaver` chart provides an internal database administration
UI for development and operations. It uses a persistent workspace, runs as the
non-root UID published by CloudBeaver, and is exposed only by a `ClusterIP`
Service. Database connections and external ingress are intentionally configured
later so credentials and public access are not introduced implicitly.

Its workspace uses the `nexus-gp3` StorageClass from `charts/platform/storage`. Volumes
are encrypted with the infrastructure-managed EBS KMS key, expand in place, and
are retained if the claim is deleted.

## Application chart

The `charts/applications/nexus` chart deploys the frontend, API, and worker with consistent:

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
make template-all
```

## Continuous validation

`.github/workflows/validate.yaml` runs on pull requests and pushes to `main`.
It uses a pinned Helm version to lint every project-owned chart and render all
application environments plus every platform chart. Kubeconform validates the
rendered built-in resources against Kubernetes 1.35 schemas, while Kyverno
enforces the repository's workload security policies. Custom resources are
still rendered and evaluated by policy, but schema validation skips them when
their external CRD schema is unavailable. The workflow has only read access
and never connects to AWS or the Kubernetes cluster.

`ENVIRONMENT` selects the thin environment override and defaults to `dev`:

```bash
make template ENVIRONMENT=staging
make template ENVIRONMENT=production
```

Shared defaults remain in `charts/applications/nexus/values.yaml`. The files under
`environments/` contain only values that differ between DEV, STAGING, and
PRODUCTION. This avoids copying the whole configuration and prevents drift.

Image tags must be immutable. The initial chart uses `0.1.0`; the application
pipeline will later update an environment to a commit SHA after publishing its
images instead of reusing mutable tags such as `latest` or `dev`.

The environment files intentionally leave AWS service endpoints in the shared
defaults until those environments exist. External Secrets integration will
supply credentials without putting them in Git.

## Database credentials

The application chart synchronizes the RDS-managed password from AWS Secrets
Manager. Terraform passes the environment's secret ARN through the Nexus
ApplicationSet; the ARN is not hard-coded in an environment values file.

The External Secrets controller uses EKS Pod Identity. The `SecretStore`
therefore contains no static credentials, IAM role annotation, or authentication
block. It creates the `nexus-database` Kubernetes Secret consumed by the API.
