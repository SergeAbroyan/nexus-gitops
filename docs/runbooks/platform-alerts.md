# Platform alert runbooks

These alerts come from Argo CD metrics scraped by Prometheus. They cover every
Application that the `bootstrap` chart renders, so a failing add-on and a
failing Nexus service raise the same alerts. The commands are read-only unless
a step says otherwise.

## ArgoCDApplicationDegraded

An Application has reported `Degraded` health for 15 minutes: at least one of
its resources is failing, for example a crashing pod, an aborted canary, or a
failed Job.

1. Find the failing resources:

   ```bash
   kubectl get application -n argocd <name> -o jsonpath='{.status.resources}' | jq '.[] | select(.health.status != "Healthy")'
   kubectl get application -n argocd <name> -o jsonpath='{.status.conditions}'
   ```

2. Inspect the failing resource and its events in its own namespace. For the
   API, check the canary first:

   ```bash
   kubectl describe rollout -n nexus nexus-api
   kubectl get analysisrun -n nexus
   ```

3. An aborted canary keeps the previous version serving. Fix the image or the
   configuration in Git; Argo Rollouts starts a new canary from the next commit.
4. Resolve after the Application reports `Healthy`.

## ArgoCDApplicationOutOfSync

An Application has differed from Git for 30 minutes. Automated sync normally
corrects drift within minutes, so a lasting difference means Argo CD cannot
apply the desired state or a controller keeps changing a field.

1. Show what differs:

   ```bash
   kubectl get application -n argocd <name> -o jsonpath='{.status.sync}'
   kubectl get application -n argocd <name> -o jsonpath='{.status.operationState.message}'
   ```

2. When a controller owns the field, such as the canary weights that Argo
   Rollouts writes into the API VirtualService, add an `ignoreDifferences`
   entry for that Application in `bootstrap/values.yaml`.
3. When someone changed the resource by hand, let Argo CD restore it. Commit the
   change to Git if it should stay.
4. Resolve after the Application reports `Synced`.

## ArgoCDSyncFailed

A sync operation ended in `Error` or `Failed` in the last 15 minutes. Typical
causes are an invalid manifest, a rejected admission request, or a missing CRD.

1. Read the operation result:

   ```bash
   kubectl get application -n argocd <name> -o jsonpath='{.status.operationState}' | jq
   ```

2. When Kyverno rejected a resource, the message names the policy. Fix the
   chart in Git; never weaken the policy to make a sync pass. An unsigned image
   is rejected by `require-signed-nexus-images` and must be rebuilt by CI in
   `nexus-applications`.
3. When a CRD is missing, check that the Application that installs it has a
   lower sync wave and is healthy.
4. Resolve after the next sync succeeds.
