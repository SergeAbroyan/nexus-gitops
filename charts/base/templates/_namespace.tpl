{{/* A namespace hardened with the Kubernetes Restricted Pod Security Standard. */}}
{{- define "nexus-base.namespace" -}}
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .root.Release.Namespace }}
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    {{- if .meshEnabled }}
    istio-injection: enabled
    {{- end }}
    {{- with .extraLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}

