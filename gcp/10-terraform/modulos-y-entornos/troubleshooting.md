# Google Cloud · Terraform · Módulos y entornos · Troubleshooting

## Lista ordenada
1. **¿Qué versión del módulo usa el entorno?** `terraform get -update` y `.terraform/modules/modules.json`.
2. **¿Validación fallida?** El mensaje de `validation` dice la regla.
3. **¿Provider correcto?** El raíz configura proyecto y región.
4. **¿Deriva?** `plan -refresh-only`.
5. **¿Mover recursos al refactorizar?** Bloques `moved`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Plan recrea al refactorizar | Cambió la dirección | Usa `moved` |
| `Invalid value for variable` | Validación | Corrige la variable |
| Módulo no actualiza | Caché de módulos | `terraform init -upgrade` |
| Plan con cambios sin tocar código | Deriva | `-refresh-only` y corrige el origen |
| `Provider configuration not present` | Provider dentro del módulo | Configúralo en el raíz |
