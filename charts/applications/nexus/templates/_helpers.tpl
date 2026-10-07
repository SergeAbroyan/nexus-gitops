{{- define "nexus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "nexus.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "nexus.name" . }}
{{- end }}
{{- end }}

{{- define "nexus.labels" -}}
app.kubernetes.io/part-of: {{ include "nexus.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "nexus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nexus.name" .root }}-{{ .serviceName }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{- define "nexus.serviceName" -}}
{{ include "nexus.fullname" .root }}-{{ .serviceName }}
{{- end }}

{{- define "nexus.image" -}}
{{- if .root.Values.image.registry }}{{ .root.Values.image.registry }}/{{ end }}{{ .service.imageRepository }}:{{ .root.Values.image.tag }}
{{- end }}
