# Validation

`.github/workflows/validate.yaml` runs on pull requests and pushes to `main`
and never connects to AWS or a cluster. Gitleaks scans the whole history for
committed secrets. For every environment the workflow renders the `bootstrap`
chart with `bootstrap/ci-values.yaml`, then renders every Application it
produces exactly as Argo CD would: the same chart and version, the same values
files in the same order, and the wired values. It lints the Nexus charts,
checks that every values file is loaded, validates all rendered resources with
kubeconform against Kubernetes 1.36 schemas and the custom resource schemas of
the CRDs catalog, and enforces `require-workload-security` on the Nexus charts
with the Kyverno CLI.

Actions are pinned to commit SHAs with their version alongside, and the
kubeconform image to a digest.

Install the hooks once to run the fast checks before every commit: whitespace,
YAML and JSON syntax, Gitleaks, actionlint, and Helm lint of the library and
bootstrap charts.

```bash
pre-commit install
```

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
