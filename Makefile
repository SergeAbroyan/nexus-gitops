CHART := charts/nexus

.PHONY: lint template package

lint:
	helm lint $(CHART)

template:
	helm template nexus $(CHART) --namespace nexus

package:
	helm package $(CHART) --destination charts
