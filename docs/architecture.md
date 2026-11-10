# Architecture

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
    ├── ingress-config/      Istio gateway and load balancer binding
    ├── karpenter-config/    EC2 node class and node pools
    ├── policies/            Kyverno workload security and image signature policies
    └── storage-config/      Encrypted EBS StorageClass
environments/
├── global-values.yaml       Conventions shared by the Nexus applications
├── dev/                     Values that differ in DEV
├── staging/                 Values that differ in staging
└── production/              Values that differ in production
docs/                        Architecture, workloads, operations, observability, security, validation
├── runbooks/                Alert response procedures and resilience drills
└── adr/                     Architecture decision records
.github/workflows/
└── validate.yaml            Secret scan and render, schema, and policy checks
renovate.json                Dependency updates for charts, images, and actions
.pre-commit-config.yaml      Local checks before every commit
```

## How Argo CD deploys a cluster

Argo CD reads this repository over SSH with a read-only GitHub deploy key that
Terraform installs from Secrets Manager; the `nexus-platform` README explains
how to create it.

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
| 1 | `istio-base`, `karpenter-crd`, `prometheus-operator-crds`, `aws-load-balancer-controller` | CRDs, and the webhook that admits every Service |
| 2 | `istio-cni`, `istiod`, `karpenter`, `karpenter-config`, `external-secrets`, `metrics-server`, `kyverno`, `argo-rollouts`, `keda`, `vpa` | Controllers that run on the managed `system` nodes, and the Karpenter node pools that add capacity when those nodes are full |
| 3 | `storage-config`, `policies`, `sloth`, `velero` | Storage and snapshot classes, admission policies, the SLO controller, and backups |
| 4 | Everything else | Pods start only after `istiod` can inject their sidecars |

The Prometheus operator CRDs have their own Application in the first wave,
and `kube-prometheus-stack` does not install them, so every add-on can ship a
`ServiceMonitor` or `PrometheusRule` regardless of its wave, and CRD upgrades
are applied by Argo CD instead of being skipped by Helm.

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
| `slackWebhookSecretName` | Secrets Manager secret that holds the Slack webhook URL |
| `backupBucket` | S3 bucket where Velero stores the cluster backups |
| `ciIdentity` | GitHub Actions workflow identity that must have signed every Nexus image |
| `database`, `cache`, `queue` | Connection settings of the API and worker |

An Application whose pods use an AWS identity runs in the namespace that
Terraform bound the identity to, so `_wiring.tpl` sets the namespace of
`aws-load-balancer-controller`, `external-secrets`, `karpenter`,
`karpenter-crd`, `keda`, `kyverno`, `monitoring`, `trivy-operator`, `velero`,
and the Nexus applications from
`serviceAccounts` instead of `values.yaml`.

## Where each value lives

Every value has exactly one home:

| Location | Holds |
| --- | --- |
| `bootstrap/values.yaml` | What runs: chart versions, namespaces, sync waves, the storage class name, the gateway name and selector, the trace port, the trace sampling percentage, and the Slack switch |
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
| `argo-rollouts` | 1 controller replica | 2 | 2 |
| `kyverno` | 1 admission replica | 3 | 3 |
| `runtime` | availability 99.5%, latency 99% | 99.5%, 99% | 99.9%, 99.5% |
| `velero` | backups kept 3 days | 7 days | 30 days |
| `karpenter-config` | Spot first in every pool, CPU limits 8/16/16, consolidate after 2m | On-Demand `system` and `general`, 16/32/32, 5m | On-Demand `system` and `general`, 32/96/64, 10m |
| `storage-config` | volume deleted with its claim | volume retained | volume retained |

Image tags live in the environment files: `image.tag` for `api`, `worker`,
and `cloudbeaver`. Application tags are immutable commit SHAs. The application
pipeline in `nexus-applications` updates `image.tag` in the DEV files after it
publishes and signs an image. Every other change to an application tag comes
from the `Deploy` workflow in `nexus-applications`, described below.

To change the catalog for one environment only, for example to try a new
add-on version in DEV first, create `environments/<env>/bootstrap-values.yaml`
with the override. The root Application loads it when it exists.
