# Oracle OCI · Storage · PAR · Troubleshooting

## Lista ordenada
1. **¿Venció?** Compara `timeExpires` con la hora actual (en UTC).
2. **¿URL completa?** Host regional + `accessUri` exacto (se pierde si se truncó al copiar).
3. **¿Operación correcta?** Una PAR de lectura no acepta `PUT`.
4. **¿Objeto correcto?** Una PAR de objeto solo sirve para ese nombre.
5. **¿El creador sigue teniendo permisos?** Si los perdió, la PAR deja de funcionar.
6. **¿Fue revocada?** `oci os preauth-request list`.
7. **¿Bucket con retención?** Puede impedir sobrescribir.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 con la URL | Vencida, revocada, URL truncada | Genera una nueva |
| 403/404 al subir | PAR de lectura o nombre distinto | Tipo y objeto correctos |
| 404 al crear la PAR | Falta `PAR_MANAGE` o el permiso delegado | Política |
| Funciona y luego no | El creador perdió permisos | Emite desde una identidad estable |
| El navegador bloquea la subida | CORS del cliente o método | Usa `PUT` directo con la URL |
