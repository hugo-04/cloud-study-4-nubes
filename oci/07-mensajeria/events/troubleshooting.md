# Oracle OCI · Mensajería · Events · Troubleshooting

## Lista ordenada
1. **¿El servicio emite ese evento?** Revisa el nombre exacto en su catálogo.
2. **¿Regla en el compartimento correcto?** Aplica a su compartimento y descendientes.
3. **¿Condición válida?** JSON correcto; listas = O, campos = Y.
4. **¿Regla habilitada y acción habilitada?**
5. **¿Política de servicio hacia el destino?**
6. **¿El destino funciona?** Suscripción confirmada, función sana, stream activo.
7. **¿Haz el cambio de prueba?** Crea un recurso real para disparar.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Nunca dispara | Tipo mal escrito o compartimento | Catálogo / mover regla |
| Error al crear la regla | Condición inválida | Valida el JSON |
| Dispara pero no llega | Falta política de servicio | `use ons-topics` / `fn-invocation` |
| Dispara de más | Condición amplia | Añade filtros de `data` |
| Duplicados | Al menos una vez | Deduplica por `eventID` |
