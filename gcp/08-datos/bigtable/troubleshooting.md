# Google Cloud · Datos · Bigtable · Troubleshooting

## Lista ordenada
1. **CPU del clúster:** ¿por encima del objetivo? Escala o activa autoescalado.
2. **Key Visualizer:** ¿bandas calientes?
3. **Diseño de lecturas:** ¿por prefijo/rango o escaneo?
4. **Tamaño de filas:** ¿filas enormes por acumular columnas?
5. **Permisos:** `bigtable.user` en la instancia.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Latencia alta | CPU o hotspot | Nodos o nueva clave |
| `DEADLINE_EXCEEDED` en lecturas | Escaneo amplio | Acota el rango |
| Crecimiento de disco | GC ausente | Política de GC |
| `PERMISSION_DENIED` | IAM | Rol en la instancia |
| Lecturas desactualizadas | Replicación asíncrona | Enrutado a un clúster |
