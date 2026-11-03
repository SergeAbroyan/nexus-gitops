# Nexus GitOps

This repository is the source of truth for everything that runs in the Nexus
Kubernetes clusters. Each environment and region has its own EKS cluster, and
the Argo CD instance in every cluster reconciles this repository.

The split with `nexus-platform` follows the GitOps Bridge pattern: Terraform
creates the AWS resources, installs Argo CD, and hands the cluster one root
Application named `bootstrap` together with the facts it knows about AWS.
Everything that runs inside Kubernetes, including every add-on, is defined
here.

## Repository structure

```text
bootstrap/                   Root chart: the AppProject and every Argo CD Application
├── values.yaml              Catalog of Applications: chart, version, namespace, sync wave
├── values.schema.json       Contract for the cluster facts that Terraform passes
├── ci-values.yaml           Stand-in cluster facts for CI
└── templates/
    ├── _wiring.tpl          Values that come from cluster facts or connect one Application to another
    ├── _helpers.tpl         Turns the catalog into Applications
    ├── applications.yaml
    └── project.yaml
addons/                      Values for third-party charts, one file per Application
charts/
├── base/                    Helm library: application, workload, namespace, and volume claim templates
├── applications/
│   ├── api/                 Go web page and REST API
│   ├── worker/              Java SQS worker
│   └── runtime/             Nexus namespace, mesh policy, alerts, and dashboards
└── platform/
    ├── cloudbeaver/         Internal database administration UI
    ├── ingress-config/      Istio gateway, route, and load balancer binding
    ├── karpenter-config/    EC2 node class and node pools
    └── storage-config/      Encrypted EBS StorageClass
environments/
├── global-values.yaml       Conventions shared by the Nexus applications
├── dev/                     Values that differ in DEV
├── staging/                 Values that differ in staging
└── production/              Values that differ in production
docs/runbooks/               Alert response procedures
policies/                    Kyverno workload security policies
```

## How Argo CD deploys a cluster

This repository is private. Argo CD reads it over SSH with a read-only GitHub
deploy key that Terraform installs from Secrets Manager; the `nexus-platform`
README explains how to create it.

Terraform creates two Argo CD objects in each cluster:

- the `bootstrap` AppProject, which may only create Argo CD `Application` and
  `AppProject` objects in the Argo CD namespace;
- the `bootstrap` Application, which renders `bootstrap/` with the cluster
  facts as Helm values.

The `bootstrap` chart renders the `nexus-platform` AppProject and one
Application for every entry in `bootstrap/values.yaml`. Each entry belongs to
one of three groups, and the group decides where the chart and its values come
from:

| Group | Argo CD Application | Chart | Values files, in order |
| --- | --- | --- | --- |
| `addons` | `<key>` | `chart` and `version` from `repoURL` | `addons/<key>.yaml`, `environments/<env>/<key>-values.yaml` |
| `platform` | `<key>` | `charts/platform/<key>` | `environments/<env>/<key>-values.yaml` |
| `applications` | `nexus-<key>` | `charts/applications/<key>` | `environments/global-values.yaml`, `environments/<env>/<key>-values.yaml` |

The values from `_wiring.tpl` come last and win. Environment files exist only
where an environment differs, because every Application sets
`ignoreMissingValueFiles`. CI fails when a values file under `addons/` or
`environments/` is not loaded by any Application, so a misspelled file name
cannot be silently ignored.

### Sync waves

The root Application creates the Applications in waves and waits for every
Application in a wave to be healthy before it starts the next one. Terraform
configures the Argo CD health check for `Application` objects that makes this
wait possible.

| Wave | Applications | Why |
| --- | --- | --- |
| 0 | `nexus-platform` AppProject | Every Application belongs to it |
| 1 | `istio-base`, `karpenter-crd`, `aws-load-balancer-controller` | CRDs, and the webhook that admits every Service |
| 2 | `istio-cni`, `istiod`, `karpenter`, `external-secrets`, `metrics-server` | Controllers that run on the managed `system` nodes |
| 3 | `karpenter-config`, `storage-config` | Node pools and the storage class the workloads need |
| 4 | Everything else | Pods start only after `istiod` can inject their sidecars |

Failed syncs retry with backoff, so an Application that needs a CRD from
another Application in the same wave, such as a `ServiceMonitor` that needs
the monitoring stack, still converges.

### Cluster facts

Terraform passes these values under `cluster`, and `values.schema.json` rejects
a missing, misspelled, or mistyped fact before anything renders:

| Fact | Used for |
| --- | --- |
| `environment` | Environment values files, alert and trace labels |
| `name`, `region`, `vpcId` | Karpenter, the AWS Load Balancer Controller, CloudWatch, Alertmanager, Secrets Manager |
| `gitops` | Repository and revision of every Application |
| `hostname`, `ingress` | Istio gateway port and host, load balancer target group |
| `ecrRegistry` | Image registry of the Nexus applications |
| `ebsKmsKeyArn`, `karpenter` | Node volume encryption, Karpenter node role and interruption queue |
| `serviceAccounts` | Namespace and name of every service account that has an AWS identity |
| `alertTopicArn`, `grafanaAdminSecretArn` | Alertmanager notifications, Grafana administrator password |
| `database`, `cache`, `queue` | Connection settings of the API and worker |

An Application whose pods use an AWS identity runs in the namespace that
Terraform bound the identity to, so `_wiring.tpl` sets the namespace of
`aws-load-balancer-controller`, `external-secrets`, `karpenter`,
`karpenter-crd`, `monitoring`, and the Nexus applications from
`serviceAccounts` instead of `values.yaml`.

## Where each value lives

Every value has exactly one home:

| Location | Holds |
| --- | --- |
| `bootstrap/values.yaml` | What runs: chart versions, namespaces, sync waves, the storage class name, the gateway selector, the trace port, and the trace sampling percentage |
| `bootstrap/templates/_wiring.tpl` | Values derived from cluster facts, and values that point one Application at another |
| `addons/<key>.yaml` | How a third-party chart is configured, the same in every environment |
| chart `values.yaml` | Defaults of a Nexus chart that are the same in every environment |
| `environments/global-values.yaml` | Conventions shared by the Nexus applications: security contexts, rollout strategy, zone spreading, autoscaling behavior, image pull policy |
| `environments/<env>/<key>-values.yaml` | Values that differ per environment |
| Terraform in `nexus-platform` | Everything that comes from AWS, and the service accounts its IAM roles trust |

A value that must come from an environment file or from the wiring has no
default in the chart and is marked `required`, so a missing value fails the
render instead of silently using a stale default.

Values that differ per environment today:

| Application | dev | staging | production |
| --- | --- | --- | --- |
| `api`, `worker` | 1–5 replicas, PDB 1 | 2–10 replicas, PDB 1 | 3–20 replicas, PDB 2 |
| `cloudbeaver` | 5Gi workspace | 5Gi workspace | 10Gi workspace |
| `karpenter` | 1 controller replica | 2 | 2 |
| `karpenter-config` | Spot first in every pool, CPU limits 8/16/16, consolidate after 2m | On-Demand `system` and `general`, 16/32/32, 5m | On-Demand `system` and `general`, 32/96/64, 10m |
| `storage-config` | volume deleted with its claim | volume retained | volume retained |

Image tags live in the environment files: `image.tag` for `api`, `worker`,
and `cloudbeaver`. Application tags are immutable commit SHAs. The application
pipeline in `nexus-applications` updates `image.tag` in the DEV files after it
publishes an image; staging and production advance only by a deliberate change
of their tag to an already tested SHA.

To change the catalog for one environment only, for example to try a new
add-on version in DEV first, create `environments/<env>/bootstrap-values.yaml`
with the override. The root Application loads it when it exists.

## Common changes

- **Upgrade an add-on:** change its `version` in `bootstrap/values.yaml`.
- **Tune an add-on:** edit `addons/<key>.yaml`, or create
  `environments/<env>/<key>-values.yaml` for one environment.
- **Add an add-on:** add an entry under `addons` in `bootstrap/values.yaml`
  and its `addons/<key>.yaml`; wire any cluster facts in `_wiring.tpl`.
- **Add a Nexus service:** create `charts/applications/<key>`, add `<key>`
  under `applications`, and add its environment files. A service that needs
  AWS access also needs a Pod Identity in `nexus-platform`.

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

`ingress-config` owns the Istio `Gateway` on port 8443, the Nexus route, and a
`TargetGroupBinding`. CloudFront terminates TLS for the public hostname and
reaches the region's internal Network Load Balancer through a VPC origin;
Terraform creates that load balancer and passes its target group ARN as a
cluster fact, and the binding registers the gateway pods. The gateway
namespace enforces the Restricted Pod Security Standard.

`karpenter-config` defines one EC2 node class and three node pools: `system`
for platform controllers, `general` for the API and the monitoring stack, and a
tainted `spot` pool for tolerant workloads such as the worker. Each pool lists
the capacity types it may use in `capacityTypes`. Staging and production run
`system` and `general` On-Demand; DEV allows Spot and On-Demand, so Karpenter
picks the cheaper Spot capacity and falls back to On-Demand only when Spot is
unavailable. The `spot` pool is Spot everywhere. Karpenter receives AWS
interruption notices through the queue Terraform creates, so it replaces a Spot
node before AWS reclaims it. Karpenter uses only the subnets that Terraform tags
for the environment's workload Availability Zones. Pin `amiAlias` to a tested
release before production.

`storage-config` defines the `nexus-gp3` StorageClass: encrypted with the
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

Prometheus, Grafana, Loki, Tempo, and the OpenTelemetry collectors are add-ons.
Istio and the API send traces to `otel-traces`, which forwards them to Tempo;
`otel-logs` ships container logs to Loki. `tracing.samplingPercentage` in
`bootstrap/values.yaml` sets the share of traced requests for both the mesh and
the API. The `Nexus Overview` dashboard shows availability, request rate, CPU,
memory, the Istio 5xx ratio, and 95th-percentile latency; `Nexus AWS Overview`
shows the CloudWatch metrics of the region's PostgreSQL, Valkey, and SQS.
Grafana discovers both dashboards automatically. Response procedures live in
[`docs/runbooks`](docs/runbooks/README.md).

Istio's validating webhook is changed by `istiod` at runtime, so `istio-base`
ignores differences in that webhook's `failurePolicy` instead of fighting
`istiod` on every sync.

## Validation

`.github/workflows/validate.yaml` runs on pull requests and pushes to `main`
and never connects to AWS or a cluster. For every environment it renders the
`bootstrap` chart with `bootstrap/ci-values.yaml`, then renders every
Application it produces exactly as Argo CD would: the same chart and version,
the same values files in the same order, and the wired values. It lints the
Nexus charts, checks that every values file is loaded, validates all rendered
resources against Kubernetes 1.36 schemas with kubeconform, and enforces the
policies in `policies/` on the Nexus charts with Kyverno. Actions are pinned to
commit SHAs and the kubeconform image to a digest; Dependabot keeps the pins
current.

Render the Applications of one environment locally:

```bash
helm template bootstrap bootstrap --namespace argocd \
  --values bootstrap/ci-values.yaml \
  --set cluster.environment=dev
```

Render one Application with the values Argo CD would give it:

```bash
helm dependency build charts/applications/api
helm template bootstrap bootstrap --namespace argocd \
  --values bootstrap/ci-values.yaml \
  --set cluster.environment=dev \
  | yq 'select(.metadata.name == "nexus-api") | .spec.sources[0].helm.valuesObject' > /tmp/nexus-api.yaml
helm template nexus-api charts/applications/api --namespace nexus \
  --values environments/global-values.yaml \
  --values environments/dev/api-values.yaml \
  --values /tmp/nexus-api.yaml
```
