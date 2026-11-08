# Operations

## Deployments

Environments are folders here, not branches. The `Deploy` workflow in
`nexus-applications` writes image tags to any environment: the version you
choose, what the previous environment runs, or the newest build. It verifies
that CI signed each image first, and production waits for the reviewers of the
`production` GitHub environment. Every deployment is a commit, so the history
of `environments/` is the deployment log, and a rollback is a deployment of an
earlier SHA.

## Common changes

- **Upgrade an add-on:** change its `version` in `bootstrap/values.yaml`.
- **Tune an add-on:** edit `addons/<key>.yaml`, or create
  `environments/<env>/<key>-values.yaml` for one environment.
- **Add an add-on:** add an entry under `addons` in `bootstrap/values.yaml`
  and its `addons/<key>.yaml`; wire any cluster facts in `_wiring.tpl`.
- **Add a Nexus service:** create `charts/applications/<key>`, add `<key>`
  under `applications`, and add its environment files. A service that needs
  AWS access also needs a Pod Identity in `nexus-platform`.

## Backups

Velero backs up the `nexus`, `cloudbeaver`, and `monitoring` namespaces every
night at 02:00 UTC: resource definitions go to the cluster's S3 bucket and
volumes are captured as EBS snapshots through the CSI snapshot class. Backups
expire after 3 days in DEV, 7 in staging, and 30 in production. The database is
not in these backups; AWS Backup protects it, as the `nexus-platform` README
describes.

## Dashboards and tools inside the cluster

None of these are exposed outside the cluster; reach them with a port-forward:

| Tool | Command | Address |
| --- | --- | --- |
| Argo CD | `kubectl port-forward -n argocd svc/argocd-server 8080:80` | <http://localhost:8080> |
| Grafana | `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80` | <http://localhost:3000> |
| Policy Reporter | `kubectl port-forward -n policy-reporter svc/policy-reporter-ui 8082:8080` | <http://localhost:8082> |
| Goldilocks | `kubectl port-forward -n goldilocks svc/goldilocks-dashboard 8083:80` | <http://localhost:8083> |
| OpenCost | `kubectl port-forward -n opencost svc/opencost 9090:9090` | <http://localhost:9090> |
| Argo Rollouts | `kubectl argo rollouts get rollout nexus-api -n nexus --watch` | terminal |
