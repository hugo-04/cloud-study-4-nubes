# Oracle OCI · Secretos · Vault: llaves (KMS) · Troubleshooting

## Lista ordenada
1. **¿Endpoint correcto?** Gestión y criptografía son distintos; el de criptografía va por vault.
2. **¿Estado de la llave?** Debe estar `ENABLED` (no `PENDING_DELETION`).
3. **¿Política?** `use keys` (o `use key-delegate` para servicios) sobre esa llave.
4. **¿Red?** Puerta de servicios o NAT hacia el endpoint del vault.
5. **¿Tamaño?** `Encrypt` directo tiene límite pequeño.
6. **¿Base64?** El SDK espera/entrega texto en base64.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 `NotAuthorizedOrNotFound` | Falta `use keys` o llave de otro compartimento | Política con `target.key.id` |
| `InvalidParameter` | Datos demasiado grandes o no base64 | Sobre; codifica |
| Servicio no puede usar tu llave | Falta política del servicio | `Allow service objectstorage-<región> to use keys …` |
| Descifrado falla tras copiar | AAD distinto | Usa el mismo contexto |
| Latencia alta | Llamada a Vault por cada dato | Cachea la DEK un tiempo corto o cifra por lotes |
