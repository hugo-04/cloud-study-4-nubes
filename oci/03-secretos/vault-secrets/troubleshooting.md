# Oracle OCI · Secretos · Vault: secretos · Troubleshooting

## Lista ordenada
1. **¿Qué identificador usas?** OCID del secreto (o nombre + OCID del vault).
2. **¿Qué etapa pides?** `CURRENT` por defecto; `PENDING` puede no existir.
3. **¿Política?** `read secret-bundles` (no solo `read secrets`).
4. **¿El secreto está activo?** No `PENDING_DELETION` ni vencido por regla de caducidad.
5. **¿Llave de cifrado disponible?** Si la llave está deshabilitada, el secreto no se lee.
6. **¿Red?** Ruta al servicio (NAT o puerta de servicios).
7. **¿Base64?** El contenido llega codificado.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 `NotAuthorizedOrNotFound` | Falta `read secret-bundles` o OCID erróneo | Corrige política/ID |
| Secreto «no existe» en la etapa | Pides `PENDING` sin versión pendiente | Usa `CURRENT` |
| Valor con símbolos raros | No decodificaste base64 | Decodifica |
| Fallo tras rotar | Caché con valor anterior | TTL corto; reintento con `CURRENT` |
| Error de la llave | Llave deshabilitada o borrada | Reactiva/cancela borrado |
