# Nexus GitOps

This repository is the source of truth for everything that runs in the Nexus
Kubernetes clusters. Each environment and region has its own EKS cluster, and
the Argo CD instance in every cluster reconciles this repository. Terraform in
`nexus-platform` installs Argo CD and its ApplicationSets and injects the
values that come from AWS.

## Repository structure

```text
charts/
├── base/                    Helm library: application, workload, namespace, and volume claim templates
├── applications/
│   ├── api/                 Go web page and REST API
│   ├── worker/              Java SQS worker
│   └── runtime/             Nexus namespace, mesh policy, alerts, and dashboards
└── platform/
    ├── cloudbeaver/         Internal database administration UI
    ├── ingress/             Istio gateway, route, and load balancer binding
    ├── karpenter/           EC2 node class and node pools
    └── storage/             Encrypted EBS StorageClass
environments/
├── global-values.yaml       Defaults shared by every Nexus service
├── dev/                     One values file for every chart deployed to DEV
│   ├── api-values.yaml
│   ├── worker-values.yaml
│   ├── runtime-values.yaml
│   ├── cloudbeaver-values.yaml
│   ├── ingress-values.yaml
│   ├── karpenter-values.yaml
│   └── storage-values.yaml
├── staging/                 The same seven files
└── production/              The same seven files
docs/runbooks/               Alert response procedures
policies/                    Kyverno workload security policies
```

The repository contains no Argo CD `Application` or `ApplicationSet`
resources; they live in the `platform` module of `nexus-platform`, so service
registration happens in one place.

## How values are combined

Argo CD renders `api`, `worker`, and `runtime` from four layers, where later
layers win:

1. The chart's `values.yaml` holds the service defaults: image repository,
   port, health checks, resources, placement, autoscaling, and its
   configuration interface.
2. `environments/global-values.yaml` holds conventions shared by every Nexus
   service: security contexts, rollout strategy, zone spreading, autoscaling
   behavior, and the tracing endpoint.
3. `environments/<environment>/<chart>-values.yaml` holds the environment's
   deployment state: environment name, image tag, replica range, and
   disruption budget.
4. Terraform injects what comes from AWS for the cluster's region: the
   regional ECR registry, the AWS Region, the PostgreSQL, Valkey, and SQS
   endpoints, and the database secret with its region.

Platform charts use three layers: the chart's `values.yaml`, the environment
file `environments/<environment>/<chart>-values.yaml`, and the values that
Terraform injects, such as the cluster name, Karpenter node role, EBS key,
application hostname, and load balancer target group. They do not read
`global-values.yaml`, which holds conventions for Nexus services only.

Every chart has a file in every environment, even when it has nothing to
override yet, so each environment folder shows everything that is deployed to
it. Settings that differ per environment today:

| Chart | dev | staging | production |
| --- | --- | --- | --- |
| `api`, `worker` | 1–5 replicas | 2–10 replicas | 3–20 replicas, PDB 2 |
| `cloudbeaver` | 5Gi workspace | 5Gi workspace | 10Gi workspace |
| `karpenter` | CPU limits 8/16/16, consolidate after 2m | 16/32/32, 5m | 32/96/64, 10m |
| `storage` | volume deleted with its claim | volume retained | volume retained |

Image tags live in the environment files too: `image.tag` for `api`,
`worker`, and `cloudbeaver`.

Image tags are immutable commit SHAs. The application pipeline in
`nexus-applications` updates `image.tag` in the DEV files after it publishes an
image; staging and production advance only by a deliberate change of their tag
to an already tested SHA.

## Bootstrap

In each cluster, Terraform installs the pinned Argo CD release and then seeds
one restricted AppProject and three ApplicationSets:

- external platform charts such as Istio, Karpenter, External Secrets, the AWS
  Load Balancer Controller, and the monitoring stack;
- the platform charts in `charts/platform`;
- the Nexus applications in `charts/applications`.

Every cluster follows `main`. Its environment decides which environment files
apply, and Terraform injects its region. Failed syncs retry with backoff, so
Applications that start before another Application has installed their CRDs
still converge on a new cluster.

## Applications

`api` serves the web page and REST API. It reads its PostgreSQL password
through an `ExternalSecret` and a `SecretStore` named `aws-secrets-manager`
that use the External Secrets controller's EKS Pod Identity, so no credentials
are stored anywhere. In a standby region the database is a read replica of the
primary, so the store reads the secret from the primary region through
`externalSecret.region`, and the API skips schema changes while the database is
read-only. It sends traces to the OpenTelemetry gateway.

`worker` runs on Spot capacity and mounts an `emptyDir` at `/tmp`, because
Spring Boot's embedded Tomcat needs a writable temporary directory while the
root filesystem stays read-only.

Both charts call `nexus-base.application`, so they share the same non-root,
read-only container security, health checks, resource limits, autoscaling,
disruption budgets, zone spreading, and Pod Identity service accounts. DEV runs
one replica of each; staging and production run at least two and three.

`runtime` owns the `nexus` namespace with sidecar injection and the Restricted
Pod Security Standard, a `STRICT` mutual TLS `PeerAuthentication`, a
`PodMonitor`, the Prometheus alerts, and the Grafana dashboards. Istio merges
each application's `/metrics` into port `15020`, so Prometheus scrapes it
without weakening mutual TLS. Alert thresholds are chart values, and every
alert links to its runbook.

## Platform charts

`ingress` owns the Istio `Gateway` on port 8443, the Nexus route, and a
`TargetGroupBinding`. CloudFront terminates TLS for the public hostname and
reaches the region's internal Network Load Balancer through a VPC origin;
Terraform creates that load balancer and passes its target group ARN to this
chart, and the binding registers the gateway pods. The gateway namespace
enforces the Restricted Pod Security Standard.

`karpenter` defines one EC2 node class and three node pools: On-Demand
`system` for platform controllers, On-Demand `general` for the API, and a
tainted `spot` pool for tolerant workloads such as the worker. Karpenter uses
only the subnets that Terraform tags for the environment's workload
Availability Zones. Pin `amiAlias` to a tested release before production.

`storage` defines the `nexus-gp3` StorageClass: encrypted with the
infrastructure EBS key and expandable. In DEV a volume is deleted when its
claim is deleted, so volumes do not pile up while DEV changes; staging and
production retain volumes. Destroying a cluster does not delete claims, so
volumes can outlive a teardown in every environment; the `nexus-platform`
README explains the cleanup. Kubernetes cannot change the reclaim policy of an
existing StorageClass, so changing `reclaimPolicy` later requires deleting and
recreating the `nexus-gp3` StorageClass.

`cloudbeaver` provides an internal database administration UI with a
persistent workspace, exposed only through a `ClusterIP` Service.

## Observability

Prometheus, Grafana, Loki, Tempo, and OpenTelemetry collectors come from the
external platform charts. The `Nexus Overview` dashboard shows availability,
request rate, CPU, memory, the Istio 5xx ratio, and 95th-percentile latency;
`Nexus AWS Overview` shows the CloudWatch metrics of the region's PostgreSQL,
Valkey, and SQS. Grafana discovers both dashboards automatically. Response
procedures live in [`docs/runbooks`](docs/runbooks/README.md).

## Validation

`.github/workflows/validate.yaml` runs on pull requests and pushes to `main`.
It lints the library chart, lints and renders every application and platform
chart for every environment, validates the rendered resources
against Kubernetes 1.35 schemas with kubeconform, and enforces the policies in
`policies/` with Kyverno. It never connects to AWS or a cluster. Actions are
pinned to commit SHAs and the kubeconform image to a digest; Dependabot keeps
the pins current.

Validate a chart locally with Helm:

```bash
helm dependency build charts/applications/api
helm lint charts/applications/api \
  --values environments/global-values.yaml \
  --values environments/dev/api-values.yaml
helm template nexus-api charts/applications/api --namespace nexus \
  --values environments/global-values.yaml \
  --values environments/dev/api-values.yaml
```

Platform charts with required values have a `ci-values.yaml` that stands in
for the values Terraform injects, so it comes last:

```bash
helm lint charts/platform/karpenter \
  --values environments/dev/karpenter-values.yaml \
  --values charts/platform/karpenter/ci-values.yaml
```

The workflow finds charts by convention: a chart's folder name matches its
environment files, for example `charts/platform/karpenter` and
`environments/dev/karpenter-values.yaml`. A new chart therefore needs a values
file in every environment. A new platform chart also needs an entry with its
Argo CD release name and namespace in the workflow, and a `ci-values.yaml` if
it has required values.
