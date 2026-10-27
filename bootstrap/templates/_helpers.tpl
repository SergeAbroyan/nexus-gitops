{{- define "bootstrap.applications" -}}
{{- $cluster := .Values.cluster -}}
{{- $wiring := include "bootstrap.wiring" . | fromYaml -}}
{{- if hasKey $wiring "Error" -}}
{{- fail (printf "bootstrap.wiring does not render valid YAML: %s" $wiring.Error) -}}
{{- end -}}
{{- $keys := concat (keys .Values.addons) (keys .Values.platform) (keys .Values.applications) -}}
{{- if ne (len $keys) (len (uniq $keys)) -}}
{{- fail "Application keys must be unique across addons, platform, and applications" -}}
{{- end -}}
{{- range $key := keys $wiring | sortAlpha -}}
{{- if not (has $key $keys) -}}
{{- fail (printf "bootstrap.wiring configures %s, which is not in values.yaml" $key) -}}
{{- end -}}
{{- end -}}
{{- $gitops := dict "repoURL" $cluster.gitops.repository "targetRevision" $cluster.gitops.revision -}}
{{- $environmentFile := printf "$values/environments/%s/%%s-values.yaml" $cluster.environment -}}
{{- $catalog := list -}}
{{- range $key, $entry := .Values.addons -}}
{{- $source := dict "repoURL" $entry.repoURL "chart" $entry.chart "targetRevision" $entry.version -}}
{{- $files := list (printf "$values/addons/%s.yaml" $key) (printf $environmentFile $key) -}}
{{- $catalog = append $catalog (dict "key" $key "name" $key "entry" $entry "source" $source "valueFiles" $files) -}}
{{- end -}}
{{- range $key, $entry := .Values.platform -}}
{{- $source := merge (dict "path" (printf "charts/platform/%s" $key)) $gitops -}}
{{- $files := list (printf $environmentFile $key) -}}
{{- $catalog = append $catalog (dict "key" $key "name" $key "entry" $entry "source" $source "valueFiles" $files) -}}
{{- end -}}
{{- range $key, $entry := .Values.applications -}}
{{- $source := merge (dict "path" (printf "charts/applications/%s" $key)) $gitops -}}
{{- $files := list "$values/environments/global-values.yaml" (printf $environmentFile $key) -}}
{{- $catalog = append $catalog (dict "key" $key "name" (printf "nexus-%s" $key) "entry" $entry "source" $source "valueFiles" $files) -}}
{{- end -}}
{{- $applications := list -}}
{{- range $catalog -}}
{{- $wired := get $wiring .key | default dict -}}
{{- $namespace := $wired.namespace | default .entry.namespace | required (printf "%s needs a namespace in values.yaml or bootstrap.wiring" .key) -}}
{{- $wave := required (printf "%s needs a wave in values.yaml" .key) .entry.wave -}}
{{- $applications = append $applications (dict "name" .name "namespace" $namespace "wave" $wave "source" .source "valueFiles" .valueFiles "values" ($wired.values | default dict) "ignoreDifferences" (.entry.ignoreDifferences | default list)) -}}
{{- end -}}
{{- toYaml (dict "applications" $applications) -}}
{{- end -}}
