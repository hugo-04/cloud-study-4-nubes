# Google Cloud · Red · Diagnóstico de conectividad · Troubleshooting

## Lista ordenada
1. **DNS:** `getent hosts <nombre>` desde el origen.
2. **Ruta:** rutas efectivas del origen.
3. **Firewall:** Connectivity Tests o simulación de reglas (salida y entrada, jerárquicas incluidas).
4. **Intermedios:** NAT (puertos), peering (transitividad), VPN (BGP), PSC/PSA.
5. **Destino escucha:** `ss -lntp` en la VM o el puerto del contenedor.
6. **TLS/IAM:** certificado, SNI, rol.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout | Firewall o ruta | Connectivity Tests |
| Connection refused | Nada escucha | Revisa el proceso y la interfaz |
| Intermitente | NAT agotado o túnel inestable | Métricas de NAT/VPN |
| Funciona por IP, no por nombre | DNS | Zonas privadas/reenvío |
| 403/401 | IAM | Roles de la cuenta de servicio |
