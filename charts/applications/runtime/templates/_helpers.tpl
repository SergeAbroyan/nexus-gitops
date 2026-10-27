{{- define "nexus-runtime.labels" -}}
{{- include "nexus-base.labels" (dict "root" . "name" "nexus" "partOf" "nexus" "component" "runtime") }}
{{- end }}
