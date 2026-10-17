# Google Cloud · Storage · Filestore · Troubleshooting

## Lista ordenada
1. **¿Red?** El cliente está en la red conectada (PSA/PSC) y el firewall permite NFS.
2. **¿Opciones de exportación?** La IP del cliente dentro de algún rango.
3. **¿Montaje?** `mount -t nfs -o vers=3 <ip>:/<share> /mnt/x` *(verifica versión según nivel)*.
4. **¿Permisos UNIX?** UID/GID y squash.
5. **¿GKE?** Driver CSI habilitado, StorageClass correcta, eventos del PVC.
6. **¿Rendimiento?** Nivel y capacidad.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `mount: timed out` | Red o firewall | Revisa conectividad |
| `access denied` | IP fuera de las opciones | Ajusta rango |
| `Permission denied` | Squash/UID | UID coherente |
| PVC `Pending` | CSI o capacidad mínima | Eventos y StorageClass |
| Lento | Nivel/capacidad | Sube nivel o capacidad |
