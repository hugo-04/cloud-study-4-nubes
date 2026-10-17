# Google Cloud · Storage · Claim check · Troubleshooting

## Lista ordenada
1. **¿Existe la generación del ticket?**
2. **¿Huella igual?**
3. **¿Permisos del consumidor sobre el bucket?**
4. **¿Ciclo de vida más corto que la retención de la suscripción/DLQ?**
5. **¿Mensajes rechazados por tamaño?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 al canjear | Generación inexistente | Orden y retención |
| Huella distinta | Objeto alterado | Investiga escritores |
| 403 | Rol | `objectViewer` |
| `INVALID_ARGUMENT` al publicar | Mensaje grande | Baja el umbral |
| Costo creciente | Huérfanos | Ciclo de vida |
