# Oracle OCI · Red · DRG, peering e híbrido · Troubleshooting

## Lista ordenada
1. **CIDR:** ¿hay solapamiento?
2. **Ruta de ida:** ¿la subred origen enruta el CIDR remoto a la DRG?
3. **DRG:** ¿la tabla de rutas del adjunto de entrada tiene ruta al adjunto destino (o distribución que la importe)?
4. **Ruta de vuelta** en la red remota.
5. **Seguridad:** listas/NSG en ambos extremos.
6. **Estado del adjunto/túnel:** `ATTACHED`, IPSec arriba, BGP establecido.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Llega pero no hay respuesta | Falta ruta de vuelta | Añade la ruta |
| Solo una VCN no llega | Tabla de la DRG sin ruta a ese adjunto | Revisa distribución de rutas |
| VPN arriba pero sin tráfico | Rutas/estáticas o BGP mal | Revisa el CIDR anunciado |
| *Timeout* tras conectar | Lista de seguridad/NSG | Permite el puerto desde el CIDR remoto |
| El adjunto no se crea | CIDR solapado o permisos | Revisa políticas y CIDR |
