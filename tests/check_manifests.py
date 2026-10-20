"""Check rendered overlays for security and availability regressions."""
import sys
from pathlib import Path
import yaml

for filename in sys.argv[1:]:
    docs = list(yaml.safe_load_all(Path(filename).read_text()))
    resources = {d['kind']: d for d in docs if d}
    deployment = resources['Deployment']
    pod = deployment['spec']['template']['spec']
    container = pod['containers'][0]
    assert pod['serviceAccountName'] == 'portfolio-api'
    assert pod['automountServiceAccountToken'] is False
    assert pod['securityContext']['runAsNonRoot'] is True
    assert container['securityContext']['readOnlyRootFilesystem'] is True
    assert container['securityContext']['allowPrivilegeEscalation'] is False
    assert container['securityContext']['capabilities']['drop'] == ['ALL']
    assert {'startupProbe','readinessProbe','livenessProbe'} <= container.keys()
    assert resources['Service']['spec']['type'] == 'ClusterIP'
    assert resources['HorizontalPodAutoscaler']['spec']['minReplicas'] >= 2
    assert resources['PodDisruptionBudget']['spec']['maxUnavailable'] == 1
    assert all(d.get('metadata', {}).get('namespace') == 'portfolio' for d in docs if d)
    print(f'{filename}: security, health, namespace and scaling checks passed')
