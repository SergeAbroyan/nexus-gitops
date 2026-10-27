{{- define "nexus-base.application" -}}
{{- $root := .root -}}
{{- $values := $root.Values -}}
{{- $name := default $root.Chart.Name $values.nameOverride -}}
{{- $image := printf "%s:%s" $values.image.repository (required "image.tag is required" $values.image.tag | toString) -}}
{{- if $values.image.registry -}}
{{- $image = printf "%s/%s" $values.image.registry $image -}}
{{- end -}}
{{- $env := list -}}
{{- if $values.observability.tracing.enabled -}}
{{- $env = append $env (dict "name" "OTEL_EXPORTER_OTLP_ENDPOINT" "value" (required "observability.tracing.endpoint is required" $values.observability.tracing.endpoint)) -}}
{{- $env = append $env (dict "name" "OTEL_TRACES_SAMPLER_ARG" "value" (required "observability.tracing.sampleRatio is required" $values.observability.tracing.sampleRatio)) -}}
{{- $env = append $env (dict "name" "OTEL_RESOURCE_ATTRIBUTES" "value" (printf "deployment.environment.name=%s" (required "environment is required" $values.environment))) -}}
{{- end -}}
{{- $env = concat $env (default (list) .env) (default (list) $values.env) -}}
{{- $autoscaling := deepCopy $values.autoscaling -}}
{{- $_ := set $autoscaling "behavior" $values.autoscalingBehavior -}}
{{- $workload := dict
  "replicaCount" $values.replicaCount
  "revisionHistoryLimit" 3
  "strategy" $values.deploymentStrategy
  "serviceAccount" $values.serviceAccount
  "image" $image
  "imagePullPolicy" $values.image.pullPolicy
  "command" $values.command
  "port" $values.port
  "env" $env
  "envFrom" (list (dict "configMapRef" (dict "name" $name)))
  "probes" $values.probes
  "resources" $values.resources
  "podSecurityContext" $values.podSecurityContext
  "containerSecurityContext" $values.containerSecurityContext
  "terminationGracePeriodSeconds" $values.terminationGracePeriodSeconds
  "nodeSelector" $values.nodeSelector
  "tolerations" $values.tolerations
  "topologySpread" $values.topologySpread
  "podAnnotations" (dict "prometheus.io/scrape" ($values.observability.enabled | toString) "prometheus.io/path" "/metrics" "prometheus.io/port" ($values.port | toString))
  "service" $values.service
  "autoscaling" $autoscaling
  "disruptionBudget" $values.disruptionBudget
  "volumes" $values.volumes
  "volumeMounts" $values.volumeMounts
-}}
{{- include "nexus-base.workload" (dict "root" $root "name" $name "partOf" "nexus" "component" .component "selectorInstance" "nexus" "workload" $workload) }}
{{- end }}
