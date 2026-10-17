# Oracle OCI · Ingress y API · Network Load Balancer · Troubleshooting

## Lista ordenada
1. **¿Salud?** `oci nlb backend-set-health get`.
2. **¿El chequeo llega?** NSG del backend permite desde la subred del NLB en el puerto del chequeo.
3. **¿Preservas origen?** Entonces el NSG del backend debe permitir las IPs de los clientes.
4. **¿Ruta de retorno?** El backend debe responder por el NLB (sin rutas asimétricas).
5. **¿Protocolo correcto?** UDP requiere listener UDP (o `TCP_AND_UDP`/`ANY`).
6. **¿Backend drenado u *offline*?**
7. **¿Registros de flujo de la VCN?** Muestran si el paquete llega y si se rechaza.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Todos `CRITICAL` | Chequeo bloqueado | Regla desde la subred del NLB |
| Conecta pero no responde | Ruta de retorno o NSG de clientes | Revisa preservación y rutas |
| Sano pero errores de app | Chequeo TCP | Chequeo HTTP |
| UDP no llega | Listener TCP | Listener UDP |
| Conexiones se cortan al escalar | Rehash al cambiar backends | Drenado y conexiones reintentables |
