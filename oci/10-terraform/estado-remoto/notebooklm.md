# NotebookLM · Oracle OCI · Estado remoto de Terraform

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Estado remoto de Terraform en Oracle OCI, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de el libro de inventario de una bodega compartida y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: backend oci nativo, backend s3 contra Object Storage con Customer Secret Key, backend http con PAR, Resource Manager, bloqueo, versionado del bucket, claves por componente y entorno, políticas por prefijo.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: bloqueo, versionado, drift, terraform_remote_state, clave del estado.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: un auditor de solo lectura del bucket del estado con ObjectStorageClient; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
