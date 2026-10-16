# NotebookLM · Azure · Data Lake Storage Gen2

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Data Lake Storage Gen2, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Data Lake Gen2, con la analogía de los pasillos reales frente a etiquetas en las cajas, y la diferencia con Blob normal.
2. El espacio de nombres jerárquico: directorios reales, renombrado atómico, endpoint dfs y ABFS; qué funciones cambian.
3. Las piezas: cuenta con HNS, sistema de archivos, directorios, archivos, append y flush, ACL de acceso y por defecto, súper-usuario.
4. Autorización: orden RBAC y luego ACL, permisos r, w y x, la regla de x en toda la ruta, por qué un rol amplio salta las ACL y por qué usar grupos.
5. Arquitectura medallion (landing, bronze, silver, gold), particiones y formatos Parquet y Delta, y el problema de los archivos pequeños.
6. Cómo escribir con seguridad: _tmp y renombrado atómico; ingestas con Data Factory, Event Hubs Capture y SFTP.
7. Red: Private Endpoints de dfs y de blob con DNS privado.
8. Seguridad e IAM completa con tabla de roles y matriz de permisos por grupo.
9. Los 11 casos reales como historias con su lección.
10. Código Java con el SDK de Data Lake: publicar lotes, administrar ACL recursivas por grupos, versión reactiva y Quarkus con Mutiny; configuración de Spark con ABFS.
11. Ejemplos de Terraform, CLI y guía de diseño de ACL; qué hacer y qué NO hacer; límites y costos.
12. Tabla de troubleshooting con la secuencia de diagnóstico y las consultas KQL.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
