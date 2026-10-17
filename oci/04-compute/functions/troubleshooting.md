# Oracle OCI · Compute · Functions · Troubleshooting

## Lista ordenada
1. **¿La imagen arranca?** `fn invoke` local o `docker run`.
2. **¿Registros?** Activa el registro de la aplicación (Logging).
3. **¿Salida a Internet o a servicios?** Subred con NAT o puerta de servicios.
4. **¿Identidad?** Grupo dinámico `resource.type = 'fnfunc'` y política.
5. **¿Tiempo y memoria?** Un `502/504` suele ser tiempo agotado o falta de memoria.
6. **¿Quien invoca tiene `use fn-invocation`?**
7. **¿Endpoint correcto?** Cada función tiene su propio endpoint de invocación.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 `NotAuthorizedOrNotFound` al invocar | Falta `use fn-invocation` o OCID erróneo | Política / ID |
| 502 | La función falló o no responde | Registros; prueba local |
| 504 | Tiempo máximo | Optimiza o cambia de servicio |
| La función no llega a Object Storage | Sin ruta de salida | NAT / puerta de servicios |
| Primera llamada lenta | Arranque en frío | Concurrencia aprovisionada |
