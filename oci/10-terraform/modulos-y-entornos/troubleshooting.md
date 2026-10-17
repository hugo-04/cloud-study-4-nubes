# Oracle OCI · Terraform · Módulos y entornos · Troubleshooting

## Lista ordenada
1. **¿`init` descarga el módulo?** Acceso al repo/registro y `ref` existente.
2. **¿Variables válidas?** Mensajes de `validation`.
3. **¿Lock de providers?** `.terraform.lock.hcl` incluido; `init -upgrade` solo a propósito.
4. **¿El plan destruye cosas?** Busca cambios de dirección (falta `moved`) o atributos que fuerzan reemplazo.
5. **¿Ciclo de dependencias?** Salidas de un módulo usadas como entrada del mismo.
6. **¿Stack de Resource Manager?** Variables del stack y versión de Terraform del stack.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Module not installed` | Falta `init` | `init` |
| `Unsupported argument` | Versión del módulo distinta | Revisa la versión fijada |
| Plan con `must be replaced` | Atributo inmutable o renombre | `moved` / revisar atributo |
| `Cycle` | Dependencia circular | Reorganiza salidas |
| Stack con drift | Cambios manuales | Detecta drift y corrige el origen |
