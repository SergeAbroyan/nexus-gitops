{{/* A persistent volume claim with consistent ownership labels. */}}
{{- define "nexus-base.persistentVolumeClaim" -}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .name }}
  labels:
    {{- include "nexus-base.labels" (dict "root" .root "name" (default .name .labelName) "partOf" .partOf "component" .component) | nindent 4 }}
  {{- with .claim.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  accessModes:
    {{- toYaml (default (list "ReadWriteOnce") .claim.accessModes) | nindent 4 }}
  {{- with .claim.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  resources:
    requests:
      storage: {{ required "A persistent volume claim size is required" .claim.size }}
{{- end }}

