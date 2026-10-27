# Nexus GitOps

This repository is the deployment source of truth for the Nexus Kubernetes
platform. Terraform creates AWS infrastructure; Helm describes Kubernetes
workloads; Argo CD will continuously reconcile this repository into EKS.

## Repository structure

```text
charts/base/                    Shared Helm library for standard resources
charts/applications/api/        Nexus Go web application and API
charts/applications/worker/     Nexus Java asynchronous queue worker
charts/applications/nexus-runtime/ Shared namespace, mesh, alerts, and dashboards
charts/platform/karpenter/      Node provisioning configuration
charts/platform/storage/        Encrypted EBS StorageClass
charts/platform/ingress/        Internal Istio gateway routing
charts/platform/cloudbeaver/    Internal database administration UI
environments/global-values.yaml Settings shared by every environment
environments/<environment>/     One state file per deployable Nexus component
```

Every deployable project-owned Helm chart lives below `charts/`. This repository
does not contain Argo CD `Application` or `ApplicationSet` resources.

`charts/base` is a Helm library chart, not a deployable application. It owns the
reusable templates for restricted namespaces, standard stateless workloads, and
persistent volume claims. Application charts keep only their domain-specific
configuration and call the library through a local, versioned dependency. The
Karpenter and storage charts remain independent because their custom resources
do not share the normal Deployment/Service lifecycle.

## GitOps bootstrap

In each region, Terraform installs the pinned Argo CD Helm release after
creating EKS. A second Helm release then seeds one restricted AppProject and
three focused ApplicationSets:

- external platform charts such as Istio and Karpenter;
- local platform and operations charts from this repository;
- Nexus application environments.

The ownership chain is:

```text
Terraform/Terragrunt -> Argo CD -> ApplicationSets -> Helm charts
```

ApplicationSet definitions and infrastructure-derived Helm values live in the
Terraform `platform` module of `nexus-platform`. This keeps service registration in one location and
avoids duplicating pointer files in this repository.

External Secrets uses the `external-secrets` service account. Its name and
namespace exactly match the EKS Pod Identity association created by Terraform.

The external-platform ApplicationSet installs the essential cluster controllers:

- Metrics Server supplies resource metrics to the Horizontal Pod Autoscalers.
- AWS Load Balancer Controller registers the Istio gateway pods in the
  Terraform-managed load balancer target group.
- Karpenter CRDs are managed separately from the Karpenter controller so they
  can be upgraded safely.

Terraform injects the EKS cluster name, AWS region, VPC ID, Karpenter
interruption queue, node IAM role, KMS key, and managed-service endpoints into
the generated Argo CD Applications.

## Karpenter capacity

The `charts/platform/karpenter` chart defines one hardened EC2 node class and three
capacity pools:

- `system` uses On-Demand capacity for platform controllers.
- `general` uses On-Demand capacity for the Go API.
- `spot` is tainted and accepts only explicitly tolerant workloads such as the
  asynchronous worker.

Karpenter discovers private subnets and the EKS node security group through the
`karpenter.sh/discovery` tag created by Terraform. The default AL2023 alias tracks
the latest EKS-optimized image for DEV. Pin `amiAlias` to a tested release before
promoting the configuration to production.

## Nexus application delivery

The Nexus ApplicationSet generates three Argo CD applications for the environment:
runtime, Go API and Java worker. Argo CD combines three value layers:

1. Each chart's `values.yaml` defines service-specific defaults and its public interface.
2. `environments/global-values.yaml` and the component file under
   `environments/<environment>/` contain versioned deployment state.
3. Terraform injects non-secret AWS outputs such as service endpoints, the ECR
   registry, and the RDS Secrets Manager ARN.

External Secrets reads the password from that ARN inside EKS. The password is
never placed in Terraform state, Argo CD parameters, or Git.

## Istio service mesh

The external-platform ApplicationSet installs Istio base, Istio CNI, and Istiod
at the same pinned version. Istio CNI removes the need for privileged init
containers in application pods. The `nexus-runtime` chart owns namespace labels,
enables automatic sidecar injection, and enforces the Restricted Pod Security
Standard.

The `nexus-runtime` chart creates a namespace-wide `PeerAuthentication` policy in
`STRICT` mode, so mesh traffic must use mutual TLS. External AWS service traffic
remains allowed until explicit ServiceEntry policies are introduced.

## Application observability

The `nexus-runtime` chart creates a PodMonitor for the API and worker. Istio
merges each application's `/metrics` endpoint into its monitoring endpoint, so
Prometheus scrapes port `15020` without weakening the namespace's strict mTLS
policy. The worker therefore remains without a Kubernetes Service.

The runtime chart also creates Prometheus alerts for an unavailable scrape target, an
elevated Istio 5xx response rate, and sustained high 95th-percentile request
latency. The alert durations and thresholds are chart values, so each
environment can tune them without modifying the templates. Terraform configures
the Prometheus Operator selectors to discover PodMonitor and PrometheusRule
resources in the Nexus namespace.

The global values file supplies the Go API with the internal OpenTelemetry
trace-gateway endpoint and the current deployment environment. API spans are
sent to the gateway, then batched and forwarded to Tempo. The Java worker
exposes Prometheus metrics through Spring Boot Actuator; distributed tracing can
be added later when the example needs cross-language trace propagation.

The version-controlled `Nexus Overview` Grafana dashboard shows target
availability, application request rate, CPU usage, memory working set, Istio
5xx ratio, and 95th-percentile request latency by destination service. Grafana's
sidecar discovers the dashboard ConfigMap across namespaces, so no dashboard
needs to be imported manually.

Operational response procedures live in [`docs/runbooks`](docs/runbooks/README.md).
Every Prometheus application alert includes a `runbook_url` annotation, while
the runbook index maps AWS CloudWatch alarm names to their response procedure.

The `charts/platform/ingress` chart owns the shared Istio `Gateway`, the Nexus
route, and a `TargetGroupBinding`. All application traffic goes to the Go API,
which serves both the web page and the REST endpoints. CloudFront terminates
TLS for the public hostname and reaches each region's internal Network Load
Balancer through a VPC origin. Terraform creates that load balancer and its
target group and passes the target group ARN to this chart; the
`TargetGroupBinding` registers the gateway pods, which listen for HTTP on port
8443. Grafana and CloudBeaver remain unexposed.

## Multiple regions

An environment can run the same applications in a primary and a standby
region; `nexus-platform` decides per environment whether the standby is
deployed. Each cluster's Argo CD reconciles this repository with the same environment files;
Terraform injects the region-specific endpoints, the regional ECR registry, and
the database secret. In the standby region the database is a read replica of
the primary, so the API's External Secrets store reads the password from the
primary region through `externalSecret.region`, and the API skips schema
changes while the database is read-only.

Staging and production run at least two and three replicas of the API and
worker so that pods spread across Availability Zones. DEV runs in one region
and one zone, so it starts with one replica of each.

## CloudBeaver

The `charts/platform/cloudbeaver` chart provides an internal database administration
UI for development and operations. It uses a persistent workspace, runs as the
non-root UID published by CloudBeaver, and is exposed only by a `ClusterIP`
Service. Database connections and external ingress are intentionally configured
later so credentials and public access are not introduced implicitly.

Its workspace uses the `nexus-gp3` StorageClass from `charts/platform/storage`. Volumes
are encrypted with the infrastructure-managed EBS KMS key, expand in place, and
are retained if the claim is deleted.

## Application charts

The Go API and Java worker are separate deployable charts. They call the same
base workload template, so both retain consistent:

- non-root and read-only container security
- startup, liveness, and readiness probes
- CPU and memory requests and limits
- horizontal pod autoscaling
- pod disruption budgets
- topology spreading across availability zones
- service accounts compatible with EKS Pod Identity

The Java worker also mounts an `emptyDir` volume at `/tmp`, because Spring
Boot's embedded Tomcat needs a writable temporary directory while the root
filesystem stays read-only.

Validate or render the chart locally:

```bash
make dependencies
make lint
make template
make lint-all
```

## Continuous validation

`.github/workflows/validate.yaml` runs on pull requests and pushes to `main`.
It uses a pinned Helm version to lint every project-owned chart and render all
application environments plus every platform chart. Kubeconform validates the
rendered built-in resources against Kubernetes 1.35 schemas, while Kyverno
enforces the repository's workload security policies. Custom resources are
still rendered and evaluated by policy, but schema validation skips them when
their external CRD schema is unavailable. The workflow has only read access
and never connects to AWS or the Kubernetes cluster. Actions are pinned to
commit SHAs and the kubeconform image to a digest; Dependabot opens grouped
weekly updates for the action pins.

`ENVIRONMENT` selects the thin environment override and defaults to `dev`:

```bash
make template ENVIRONMENT=staging
make template ENVIRONMENT=production
```

Cross-service settings live in `environments/global-values.yaml`. Each environment
then has a small values file for runtime, API and worker. Chart values
contain reusable service defaults only; environment files are the desired
deployment state.

Image tags must be immutable. Each component environment file explicitly starts
at `0.1.0`. The application pipeline updates the corresponding DEV file to a
commit SHA after publishing that service image. Staging and production advance
only through deliberate GitOps promotion of an already tested SHA.

Environment files intentionally omit infrastructure-generated AWS endpoints.
Terraform injects the current RDS, Valkey, SQS, and ECR outputs into each Argo
CD application. External Secrets supplies credentials without putting them in
Git.

## Database credentials

The API chart synchronizes the RDS-managed password from AWS Secrets
Manager. Terraform passes the environment's secret ARN through the Nexus
ApplicationSet; the ARN is not hard-coded in an environment values file.

The External Secrets controller uses EKS Pod Identity. The `SecretStore`
therefore contains no static credentials, IAM role annotation, or authentication
block. It creates the `nexus-database` Kubernetes Secret consumed by the API.
