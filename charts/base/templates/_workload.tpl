{{/*
Render the resources that make one stateless application unit:
ServiceAccount, Deployment, optional Service, HPA, and PodDisruptionBudget.
*/}}
{{- define "nexus-base.workload" -}}
{{- $root := .root -}}
{{- $workload := .workload -}}
{{- $serviceAccount := default (dict) $workload.serviceAccount -}}
{{- $rollout := default (dict) $workload.rollout -}}
{{- $selectorContext := dict "root" $root "name" .name "instance" .selectorInstance -}}
{{- $labelContext := dict "root" $root "name" .name "partOf" .partOf "component" .component -}}
{{- if $serviceAccount.create }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ required "A service account name is required when creation is enabled" $serviceAccount.name }}
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
automountServiceAccountToken: {{ default false $serviceAccount.automountServiceAccountToken }}
{{- end }}
---
{{- if $rollout.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
{{- else }}
apiVersion: apps/v1
kind: Deployment
{{- end }}
metadata:
  name: {{ .name }}
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
spec:
  {{- if not $workload.autoscaling.enabled }}
  replicas: {{ default 1 $workload.replicaCount }}
  {{- end }}
  revisionHistoryLimit: {{ default 3 $workload.revisionHistoryLimit }}
  {{- if $rollout.enabled }}
  strategy:
    canary:
      stableService: {{ .name }}
      canaryService: {{ .name }}-canary
      trafficRouting:
        istio:
          virtualService:
            name: {{ .name }}
            routes:
              - primary
      {{- with $rollout.analysisTemplate }}
      analysis:
        startingStep: 1
        templates:
          - templateName: {{ . }}
      {{- end }}
      steps:
        {{- toYaml (required "rollout.steps is required" $rollout.steps) | nindent 8 }}
  {{- else }}
  {{- with $workload.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "nexus-base.selectorLabels" $selectorContext | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "nexus-base.selectorLabels" $selectorContext | nindent 8 }}
        app.kubernetes.io/part-of: {{ .partOf | quote }}
        app.kubernetes.io/component: {{ .component | quote }}
        {{- with $workload.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with $workload.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with $serviceAccount.name }}
      serviceAccountName: {{ . }}
      {{- end }}
      automountServiceAccountToken: {{ default false $serviceAccount.automountServiceAccountToken }}
      {{- with $workload.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ default 30 $workload.terminationGracePeriodSeconds }}
      {{- with $workload.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $workload.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $workload.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $workload.topologySpread.enabled }}
      topologySpreadConstraints:
        - maxSkew: {{ default 1 $workload.topologySpread.maxSkew }}
          topologyKey: {{ default "topology.kubernetes.io/zone" $workload.topologySpread.topologyKey }}
          whenUnsatisfiable: {{ default "ScheduleAnyway" $workload.topologySpread.whenUnsatisfiable }}
          labelSelector:
            matchLabels:
              {{- include "nexus-base.selectorLabels" $selectorContext | nindent 14 }}
      {{- end }}
      containers:
        - name: {{ default .component $workload.containerName }}
          image: {{ required "A workload image is required" $workload.image | quote }}
          imagePullPolicy: {{ default "IfNotPresent" $workload.imagePullPolicy }}
          {{- with $workload.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.args }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.port }}
          ports:
            - name: http
              containerPort: {{ . }}
              protocol: TCP
          {{- end }}
          {{- with $workload.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.probes.startup }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.probes.liveness }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.probes.readiness }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $workload.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with $workload.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- if $workload.service.enabled }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
spec:
  type: {{ default "ClusterIP" $workload.service.type }}
  selector:
    {{- include "nexus-base.selectorLabels" $selectorContext | nindent 4 }}
  ports:
    - name: http
      port: {{ required "A Service port is required when the Service is enabled" $workload.service.port }}
      targetPort: http
      protocol: TCP
{{- if $rollout.enabled }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}-canary
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "nexus-base.selectorLabels" $selectorContext | nindent 4 }}
  ports:
    - name: http
      port: {{ $workload.service.port }}
      targetPort: http
      protocol: TCP
{{- end }}
{{- end }}
{{- if $workload.autoscaling.enabled }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
spec:
  scaleTargetRef:
    {{- if $rollout.enabled }}
    apiVersion: argoproj.io/v1alpha1
    kind: Rollout
    {{- else }}
    apiVersion: apps/v1
    kind: Deployment
    {{- end }}
    name: {{ .name }}
  minReplicas: {{ required "autoscaling.minReplicas is required" $workload.autoscaling.minReplicas }}
  maxReplicas: {{ required "autoscaling.maxReplicas is required" $workload.autoscaling.maxReplicas }}
  behavior:
    {{- toYaml (required "autoscaling.behavior is required" $workload.autoscaling.behavior) | nindent 4 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ required "autoscaling.cpuUtilization is required" $workload.autoscaling.cpuUtilization }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ required "autoscaling.memoryUtilization is required" $workload.autoscaling.memoryUtilization }}
{{- end }}
{{- if $workload.disruptionBudget.enabled }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  labels:
    {{- include "nexus-base.labels" $labelContext | nindent 4 }}
spec:
  {{- if hasKey $workload.disruptionBudget "minAvailable" }}
  minAvailable: {{ $workload.disruptionBudget.minAvailable }}
  {{- else if hasKey $workload.disruptionBudget "maxUnavailable" }}
  maxUnavailable: {{ $workload.disruptionBudget.maxUnavailable }}
  {{- else }}
  {{- fail "disruptionBudget needs minAvailable or maxUnavailable" }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "nexus-base.selectorLabels" $selectorContext | nindent 6 }}
{{- end }}
{{- end }}

