{{/*
Shared labels for resources created by Nexus-owned charts.

Required input:
  root:      the calling chart's root context
  name:      the Kubernetes application name
  partOf:    the higher-level platform name
  component: the workload's responsibility
*/}}
{{- define "nexus-base.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | quote }}
app.kubernetes.io/name: {{ .name | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service | quote }}
app.kubernetes.io/part-of: {{ .partOf | quote }}
app.kubernetes.io/component: {{ .component | quote }}
{{- with .extraLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Immutable labels used by workload and Service selectors. */}}
{{- define "nexus-base.selectorLabels" -}}
app.kubernetes.io/name: {{ .name | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/instance: {{ default .root.Release.Name .instance | quote }}
{{- end }}

