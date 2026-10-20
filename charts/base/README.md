# Nexus base chart

`nexus-base` is a Helm library chart. It cannot be installed by itself. Nexus
application charts declare it as a local dependency and call its named
templates to create consistently labelled and secured Kubernetes resources.

The library intentionally contains only resources with a shared lifecycle:

- `nexus-base.namespace` creates a namespace with Restricted Pod Security labels.
- `nexus-base.workload` creates a ServiceAccount, Deployment, and optional
  Service, HorizontalPodAutoscaler, and PodDisruptionBudget.
- `nexus-base.persistentVolumeClaim` creates a consistently labelled claim.

Domain resources such as Istio routes, Prometheus rules, Karpenter node pools,
and StorageClasses stay in their owning application or platform chart.

