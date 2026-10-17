# Google Cloud · Secretos · Cloud KMS · Troubleshooting

## Lista ordenada
1. **¿Nombre completo de la llave?** `projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>`.
2. **¿Rol en la llave?** Para la app o para el agente de servicio (CMEK).
3. **¿Versión habilitada?** Para descifrar, la versión que cifró debe estar `ENABLED`.
4. **¿AAD igual?** Si cambia, el descifrado falla.
5. **¿Ubicación compatible?** CMEK requiere llave en ubicación compatible con el recurso.
6. **¿Cuotas?** Operaciones por minuto.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `PERMISSION_DENIED` | Falta rol | Rol en la llave |
| `FAILED_PRECONDITION` | Versión deshabilitada/destruida | Habilita o restaura (si está programada) |
| Falla de autenticación de AES-GCM | AAD o datos alterados | Revisa contexto |
| CMEK no se puede usar | Ubicación distinta | Llave en la misma ubicación |
| 429 | Demasiadas operaciones | Sobre y caché de DEK descifradas (con cuidado) |
