# Oracle OCI · Red · Diagnóstico de conectividad · Troubleshooting

Cuando falla **el propio diagnóstico**:

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No hay registros de flujo | Registro no habilitado o grupo sin retención | Habilita el log en la subred |
| Los registros no muestran el tráfico | Subred equivocada o filtro | Revisa el recurso del log |
| Path Analyzer dice «alcanzable» pero falla | Problema fuera de la red (servicio, TLS, IAM) | Sigue la escalera 4–6 |
| `nslookup` funciona y la app no | La JVM cachea DNS o usa otro resolutor | `networkaddress.cache.ttl`, mismo pod |
| No puedes entrar al recurso privado | Falta Bastion o regla | Crea la sesión de Bastion |
| El pod de diagnóstico ve distinto | Otra cuenta de servicio o subred | Usa la misma identidad y nodo |
