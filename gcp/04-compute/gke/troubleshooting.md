# Google Cloud · Compute · GKE · Troubleshooting

## Lista ordenada
1. **¿El pod está `Pending`?** `kubectl describe pod`: falta de recursos, cuotas, afinidad.
2. **¿`CrashLoopBackOff`?** Registros del contenedor y probes.
3. **¿`ImagePullBackOff`?** Ruta de la imagen y permisos de Artifact Registry para la cuenta del nodo.
4. **¿Sin acceso a APIs?** Workload Identity y roles.
5. **¿Servicio no responde?** Endpoints listos, NetworkPolicy, firewall de los rangos del balanceador.
6. **¿Actualización atascada?** PDB demasiado estricto.
7. **¿Cuotas?** IPs de pods, CPU regional.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Pending` | Sin capacidad o cuota | Autoscaler, cuota, requests |
| `OOMKilled` | Límite de memoria | Ajusta limits/requests |
| `ImagePullBackOff` | Permiso o ruta | `artifactregistry.reader` |
| 403 desde el pod | Workload Identity | Principal y rol |
| Nodo no drena | PDB `maxUnavailable: 0` | Ajusta PDB |
