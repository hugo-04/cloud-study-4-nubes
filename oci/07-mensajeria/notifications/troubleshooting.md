# Oracle OCI · Mensajería · Notifications · Troubleshooting

## Lista ordenada
1. **¿Suscripción `ACTIVE`?** Las `PENDING` no reciben nada.
2. **¿Publicaste en el tema correcto?** OCID y región.
3. **¿Política?** `use ons-topics` para publicar; Monitoring/Events con su política de servicio.
4. **¿Webhook accesible?** HTTPS público con certificado válido; responde 2xx rápido.
5. **¿Correo en spam?** Revisa filtros del dominio.
6. **¿Mensaje demasiado grande?** Recorta el cuerpo.
7. **¿Límites de tasa?** Publicaciones muy seguidas pueden rechazarse (429).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No llega nada | Suscripción pendiente | Reenvía confirmación |
| 404 al publicar | OCID/región o sin permiso | Revisa ambos |
| Webhook recibe duplicados | Respuesta lenta o error | 202 rápido + idempotencia |
| 429 | Tasa de publicación | Agrupa mensajes |
| Correos truncados | Tamaño | Cuerpo corto + enlace |
