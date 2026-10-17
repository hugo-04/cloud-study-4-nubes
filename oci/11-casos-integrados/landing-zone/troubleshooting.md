# Oracle OCI · Caso integrado · Landing zone · Troubleshooting

## Lista ordenada
1. **¿Región home?** Compartimentos, grupos y políticas se crean allí.
2. **¿Profundidad de compartimentos?** Límite de niveles.
3. **¿CIDR libre?** Contra VCN existentes y redes locales conectadas.
4. **¿Políticas válidas?** Errores de sintaxis o nombres de grupo inexistentes.
5. **¿Etiquetas obligatorias?** Recursos fallan si falta la etiqueta.
6. **¿Verificación con permisos de lectura suficientes?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Error al crear política | Grupo aún no existe | `depends_on` o crear antes |
| `TagDefault required` al crear VCN | Etiqueta obligatoria | Pásala en el módulo |
| DRG no enruta | CIDR solapado | Replanifica |
| Verificador «no pudo comprobar» | Falta permiso de lectura | Política de `inspect` |
| Compartimento no se borra | Recursos dentro | Limpia antes |
