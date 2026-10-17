# NotebookLM · Azure · Terraform · Módulos y entornos

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (el módulo con sus pruebas, las raíces de dev y prod, HCL, CLI, Resource Graph y JSON).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre módulos y entornos de Terraform en Azure (proveedores azurerm y azapi), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es un módulo y qué es un entorno; la analogía de la receta y la cocina; el diagrama de módulos versionados y entornos con su propio estado.
2. Cómo funciona por dentro: la anatomía de un módulo (versions, variables, main, outputs, tests, README), los orígenes de módulos y su versionado, tipos y validaciones, precondition, postcondition y check, count frente a for_each y la dirección en el estado, los bloques moved, import y removed con sus versiones mínimas, terraform test con mock_provider, expect_failures y mock_resource, proveedores con alias para varias suscripciones, azurerm frente a azapi y los módulos verificados de Azure.
3. Para qué sirve y cuándo no (módulos de una sola llamada, envolturas sin valor, navajas suizas).
4. Cómo se usa: la estructura del repositorio, el ciclo de vida de un módulo, las convenciones de nombres, etiquetas y variables, varias aplicaciones con for_each, las recetas para migrar sin destruir y las cuatro formas de equivocarse.
5. Seguridad: la tabla de IAM por plano, la cadena de suministro de módulos, seguro por defecto, escáneres, sin secretos en el contrato.
6. Qué hacer y qué NO hacer; límites, costos y versiones mínimas.
7. Los 11 casos reales como historias con su lección: el módulo copiado cuarenta veces, ref=main y el viernes de sorpresas, count y la lista reordenada, renombrar el módulo, el proveedor dentro del módulo, dev y prod con código copiado, el nombre de cuenta de 26 caracteres, la prueba sin Azure, traer lo heredado, el módulo que pedía un secreto y el uso de -target.
8. Código Java: las reglas de nombres de Azure y el generador de terraform.tfvars.json determinista, los controladores en Spring MVC, WebFlux y Quarkus imperativo y reactivo, y las pruebas de contrato contra el módulo.
9. Ejemplos: el módulo app-base con sus pruebas, la composición con moved, import, removed, azapi y alias, las raíces dev y prod, las consultas de Azure Resource Graph y el script de CLI.
10. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
