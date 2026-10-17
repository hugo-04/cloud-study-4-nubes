# Oracle OCI · Ingress y API · WAF · Troubleshooting

## Lista ordenada
1. **¿El WAF está adjunto y `ACTIVE`?** `oci waf web-app-firewall list`.
2. **¿Registros activos?** Sin registros no sabrás qué regla actuó.
3. **¿Qué regla coincidió?** Busca la petición por ruta/IP en los registros del WAF.
4. **¿Falso positivo?** Pasa la regla a `CHECK` o añade exclusión del argumento.
5. **¿429?** Revisa la regla de tasa y si hay NAT compartida.
6. **¿Condición JMESPATH correcta?** Un error lógico puede bloquear todo o nada.
7. **¿El tráfico llega por el LB?** Si no, el WAF no ve nada.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 403 a usuarios legítimos | Protección demasiado estricta | Exclusión o `CHECK` |
| Ningún bloqueo en pruebas | Política en `CHECK` | Cambia la acción |
| 429 inesperados | Límite bajo o IP compartida | Ajusta por ruta |
| Ataques en el backend | Backend expuesto | NSG solo desde el LB |
| Cambio sin efecto | Política no asociada o en `UPDATING` | Espera el estado / asocia |
