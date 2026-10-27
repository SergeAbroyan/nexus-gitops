{{- define "bootstrap.wiring" -}}
{{- $cluster := .Values.cluster -}}
{{- $accounts := $cluster.serviceAccounts -}}
{{- $gateway := index .Values.addons "istio-ingress" -}}
{{- $traceHost := printf "otel-traces.%s.svc.cluster.local" (index .Values.addons "otel-traces").namespace -}}
istiod:
  values:
    meshConfig:
      extensionProviders:
        - name: otel-tracing
          opentelemetry:
            service: {{ $traceHost }}
            port: {{ .Values.tracing.port }}
            resource_detectors:
              environment: {}
istio-ingress:
  values:
    service:
      ports:
        - name: http
          port: {{ $cluster.ingress.port }}
          targetPort: {{ $cluster.ingress.port }}
          protocol: TCP
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            {{- toYaml .Values.ingressGateway.selector | nindent 12 }}
karpenter-crd:
  namespace: {{ $accounts.karpenter.namespace }}
karpenter:
  namespace: {{ $accounts.karpenter.namespace }}
  values:
    serviceAccount:
      name: {{ $accounts.karpenter.name }}
    settings:
      clusterName: {{ $cluster.name | quote }}
      interruptionQueue: {{ $cluster.karpenter.interruptionQueue | quote }}
aws-load-balancer-controller:
  namespace: {{ $accounts.loadBalancerController.namespace }}
  values:
    clusterName: {{ $cluster.name | quote }}
    region: {{ $cluster.region | quote }}
    vpcId: {{ $cluster.vpcId | quote }}
    serviceAccount:
      name: {{ $accounts.loadBalancerController.name }}
external-secrets:
  namespace: {{ $accounts.externalSecrets.namespace }}
  values:
    serviceAccount:
      name: {{ $accounts.externalSecrets.name }}
monitoring:
  namespace: {{ $accounts.grafana.namespace }}
  values:
    prometheus:
      prometheusSpec:
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: {{ .Values.storageClassName }}
    alertmanager:
      serviceAccount:
        name: {{ $accounts.alertmanager.name }}
      config:
        receivers:
          - name: "null"
          - name: nexus-sns
            sns_configs:
              - topic_arn: {{ $cluster.alertTopicArn | quote }}
                send_resolved: true
                sigv4:
                  region: {{ $cluster.region | quote }}
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: {{ .Values.storageClassName }}
    grafana:
      serviceAccount:
        name: {{ $accounts.grafana.name }}
      persistence:
        storageClassName: {{ .Values.storageClassName }}
      additionalDataSources:
        - name: CloudWatch
          type: cloudwatch
          uid: cloudwatch
          access: proxy
          isDefault: false
          jsonData:
            authType: default
            defaultRegion: {{ $cluster.region | quote }}
        - name: Loki
          type: loki
          uid: loki
          access: proxy
          url: http://loki-gateway.monitoring.svc.cluster.local
          isDefault: false
          jsonData:
            maxLines: 1000
        - name: Tempo
          type: tempo
          uid: tempo
          access: proxy
          url: http://tempo.monitoring.svc.cluster.local:3200
          isDefault: false
          jsonData:
            httpMethod: GET
            nodeGraph:
              enabled: true
            tracesToLogsV2:
              datasourceUid: loki
              spanStartTimeShift: -1m
              spanEndTimeShift: 1m
              filterByTraceID: true
              filterBySpanID: false
    extraManifests:
      aws-secrets-manager:
        spec:
          provider:
            aws:
              region: {{ $cluster.region | quote }}
      grafana-admin:
        spec:
          data:
            - secretKey: adminPassword
              remoteRef:
                key: {{ $cluster.grafanaAdminSecretArn | quote }}
loki:
  values:
    singleBinary:
      persistence:
        storageClass: {{ .Values.storageClassName }}
tempo:
  values:
    persistence:
      storageClassName: {{ .Values.storageClassName }}
otel-traces:
  values:
    fullnameOverride: otel-traces
    ports:
      otlp:
        servicePort: {{ .Values.tracing.port }}
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/instance: otel-traces
    extraManifests:
      - apiVersion: telemetry.istio.io/v1
        kind: Telemetry
        metadata:
          name: mesh-default
          namespace: istio-system
        spec:
          tracing:
            - providers:
                - name: otel-tracing
              randomSamplingPercentage: {{ .Values.tracing.samplingPercentage }}
karpenter-config:
  values:
    clusterName: {{ $cluster.name | quote }}
    nodeRoleName: {{ $cluster.karpenter.nodeRoleName | quote }}
    ebsKmsKeyArn: {{ $cluster.ebsKmsKeyArn | quote }}
storage-config:
  values:
    storageClassName: {{ .Values.storageClassName }}
    kmsKeyArn: {{ $cluster.ebsKmsKeyArn | quote }}
cloudbeaver:
  values:
    persistence:
      storageClassName: {{ .Values.storageClassName }}
ingress-config:
  namespace: {{ $gateway.namespace }}
  values:
    host: {{ $cluster.hostname | quote }}
    targetGroupArn: {{ $cluster.ingress.targetGroupArn | quote }}
    gateway:
      port: {{ $cluster.ingress.port }}
      service: istio-ingress
      selector:
        {{- toYaml .Values.ingressGateway.selector | nindent 8 }}
    nexus:
      namespace: {{ $accounts.api.namespace }}
runtime:
  namespace: {{ $accounts.api.namespace }}
  values:
    environment: {{ $cluster.environment }}
api:
  namespace: {{ $accounts.api.namespace }}
  values:
    environment: {{ $cluster.environment }}
    image:
      registry: {{ $cluster.ecrRegistry | quote }}
    serviceAccount:
      name: {{ $accounts.api.name }}
    observability:
      tracing:
        endpoint: {{ printf "http://%s:%v" $traceHost .Values.tracing.port | quote }}
        sampleRatio: {{ divf .Values.tracing.samplingPercentage 100 | toString | quote }}
    config:
      awsRegion: {{ $cluster.region | quote }}
      database:
        host: {{ $cluster.database.host | quote }}
        port: {{ $cluster.database.port | toString | quote }}
        name: {{ $cluster.database.name | quote }}
        user: {{ $cluster.database.username | quote }}
      valkey:
        host: {{ $cluster.cache.host | quote }}
        port: {{ $cluster.cache.port | toString | quote }}
        username: {{ $cluster.cache.username | quote }}
        cacheName: {{ $cluster.cache.replicationGroupId | quote }}
      sqs:
        queueURL: {{ $cluster.queue.url | quote }}
    externalSecret:
      remoteSecretKey: {{ $cluster.database.secretArn | quote }}
      region: {{ index (splitList ":" $cluster.database.secretArn) 3 | quote }}
worker:
  namespace: {{ $accounts.worker.namespace }}
  values:
    environment: {{ $cluster.environment }}
    image:
      registry: {{ $cluster.ecrRegistry | quote }}
    serviceAccount:
      name: {{ $accounts.worker.name }}
    config:
      awsRegion: {{ $cluster.region | quote }}
      sqs:
        queueURL: {{ $cluster.queue.url | quote }}
        waitTimeSeconds: {{ $cluster.queue.receiveWaitTimeSeconds | toString | quote }}
        visibilityTimeoutSeconds: {{ $cluster.queue.visibilityTimeoutSeconds | toString | quote }}
{{- end -}}
