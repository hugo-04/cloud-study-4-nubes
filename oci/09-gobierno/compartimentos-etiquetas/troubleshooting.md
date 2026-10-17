# Oracle OCI · Gobierno · Compartimentos, etiquetas y cuotas · Troubleshooting

## Lista ordenada
1. **¿Falla la creación por etiqueta?** Una etiqueta por defecto obligatoria no tiene valor o el valor no está en la lista.
2. **¿`use tag-namespaces`?** Quien crea recursos necesita permiso para aplicar etiquetas definidas.
3. **¿Cuota excedida?** El error menciona la cuota del compartimento (distinto del límite de servicio).
4. **¿Límite de servicio?** Si la cuota sobra pero falla, es el límite del tenancy: pide aumento.
5. **¿No se puede borrar el compartimento?** Tiene recursos (incluidos borrados recientes) o políticas que lo referencian.
6. **¿Etiquetas en costos?** Activa la etiqueta como «de costo» y espera el procesamiento.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `TagDefault required` | Etiqueta obligatoria sin valor | Envía la etiqueta en la creación |
| `NotAuthorized` al etiquetar | Falta `use tag-namespaces` | Política |
| `QuotaExceeded` | Cuota del compartimento | Ajusta cuota o libera |
| `LimitExceeded` | Límite del servicio | Solicita aumento |
| Etiqueta no aparece en costos | No marcada como de costo | Actívala |
