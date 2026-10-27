# Nexus base chart

`nexus-base` is a Helm library chart. It cannot be installed by itself. Nexus
charts declare it as a local dependency and call its named templates to create
consistently labelled and secured Kubernetes resources.

- `nexus-base.application` renders a complete Nexus service from the calling
  chart's values: image, probes, resources, security contexts, autoscaling,
  disruption budget, volumes, a ConfigMap reference, and OpenTelemetry
  variables when `observability.tracing.enabled` is true. A chart can pass
  extra environment variables, such as the API's database password.
- `nexus-base.workload` creates a ServiceAccount, Deployment, and optional
  Service, HorizontalPodAutoscaler, and PodDisruptionBudget from an explicit
  workload description. `nexus-base.application` uses it, and charts that are
  not Nexus services, such as CloudBeaver, call it directly.
- `nexus-base.namespace` creates a namespace with Restricted Pod Security labels.
- `nexus-base.persistentVolumeClaim` creates a consistently labelled claim.

Domain resources such as Istio routes, Prometheus rules, Karpenter node pools,
and StorageClasses stay in their owning chart.
