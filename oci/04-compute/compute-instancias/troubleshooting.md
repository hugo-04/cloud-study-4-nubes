# Oracle OCI · Compute · Instancias · Troubleshooting

## Lista ordenada
1. **¿Estado?** `PROVISIONING` largo suele ser capacidad: prueba otro dominio de disponibilidad o forma.
2. **¿Red?** Subred, tabla de rutas, lista de seguridad/NSG y reglas del firewall del SO.
3. **¿Acceso?** Bastion, llave pública correcta, usuario (`opc` en Oracle Linux, `ubuntu` en Ubuntu).
4. **¿cloud-init?** `/var/log/cloud-init-output.log`.
5. **¿Identidad?** Grupo dinámico + política; prueba `oci os ns get --auth instance_principal`.
6. **¿Metadatos?** `curl -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Out of host capacity` | Sin capacidad en el dominio | Otro AD / otra forma / reintentar |
| No hay SSH | NSG, ruta o firewall del SO | Revisa los tres |
| La app no llega a Object Storage | Sin puerta de servicios/NAT | Ruta en la subred |
| Instance principal falla | Regla del grupo dinámico | Revisa atributos |
| Disco lleno | Volumen de arranque pequeño | Amplía y `growfs` |
