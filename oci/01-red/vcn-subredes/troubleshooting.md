# Oracle OCI · Red · VCN y subredes · Troubleshooting

## Lista ordenada
1. **¿Tiene el recurso IP privada en la subred correcta?** Revisa la VNIC.
2. **¿La tabla de rutas de la subred tiene la ruta que necesitas?** (`0.0.0.0/0` → NAT o IGW; CIDR de servicios → SGW).
3. **¿La lista de seguridad o el NSG permiten el tráfico?** Entrada **y** salida (si es sin estado).
4. **¿DNS resuelve?** Opciones DHCP y resolutor de la VCN.
5. **¿Hay solapamiento de CIDR** con la red remota?

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La VM privada no sale a Internet | Falta ruta a la NAT o NAT sin recursos | Añade `0.0.0.0/0` → NAT en la tabla de rutas |
| La VM pública no responde | Sin IP pública o sin ruta al IGW | Asigna IP pública; ruta `0.0.0.0/0` → IGW |
| No se puede crear la subred | CIDR fuera de la VCN o solapado | Ajusta el bloque |
| Pods sin IP | Subred sin direcciones libres | Amplía o crea otra subred |
| Object Storage tarda o sale por Internet | Sin Service Gateway | Crea SGW y la ruta |
| Peering no sube | CIDR solapados | Renumera |
