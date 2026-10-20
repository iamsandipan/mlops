{{- define "gpu-workload.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "gpu-workload.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "gpu-workload.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "gpu-workload.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "gpu-workload.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gpu-workload.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Pod template shared by the Job and the Deployment */}}
{{- define "gpu-workload.podTemplate" -}}
metadata:
  labels:
    {{- include "gpu-workload.selectorLabels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- $annotations := deepCopy (.Values.podAnnotations | default dict) }}
  {{- if and (eq .Values.kind "Job") .Values.job.doNotDisrupt }}
  {{- $_ := set $annotations "karpenter.sh/do-not-disrupt" "true" }}
  {{- end }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  serviceAccountName: {{ include "gpu-workload.serviceAccountName" . }}
  {{- if eq .Values.kind "Job" }}
  restartPolicy: Never
  {{- end }}
  containers:
    - name: main
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.env }}
      env:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.envFrom }}
      envFrom:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if eq .Values.kind "Deployment" }}
      ports:
        - name: http
          containerPort: {{ .Values.deployment.port }}
      {{- with .Values.deployment.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      resources:
        {{- $resources := deepCopy (.Values.resources | default dict) }}
        {{- $limits := get $resources "limits" | default dict }}
        {{- $_ := set $limits "nvidia.com/gpu" (int .Values.gpus) }}
        {{- $_ := set $resources "limits" $limits }}
        {{- toYaml $resources | nindent 8 }}
      volumeMounts:
        {{- if .Values.shmSize }}
        - name: dshm
          mountPath: /dev/shm
        {{- end }}
        {{- with .Values.volumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
  volumes:
    {{- if .Values.shmSize }}
    - name: dshm
      emptyDir:
        medium: Memory
        sizeLimit: {{ .Values.shmSize }}
    {{- end }}
    {{- with .Values.volumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
