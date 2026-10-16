# Azure · Data Lake Gen2 · Repaso

## Preguntas de repaso
1. ¿Qué es Data Lake Gen2 en una frase?
   - *Blob Storage con espacio de nombres jerárquico (directorios reales, ACL POSIX y endpoint `dfs`).*
2. ¿Qué gana un renombrado con HNS?
   - *Una operación atómica de metadatos en vez de copiar y borrar cada blob.*
3. ¿Cómo se autorizan las operaciones?
   - *Primero RBAC; si ningún rol lo concede, se evalúan las ACL (con `x` en cada directorio del camino).*
4. ¿Por qué un rol amplio es peligroso?
   - *Si el rol concede la acción, las ACL no se miran: salta tu modelo fino.*
5. ¿Qué diferencia hay entre ACL de acceso y por defecto?
   - *Acceso: aplica al objeto existente. Por defecto: plantilla heredada por lo que se cree después.*
6. ¿Cómo aplicas ACL a lo que ya existe?
   - *De forma recursiva (`update-recursive`), con cuidado por tiempo y transacciones.*
7. ¿A quién asignas las ACL?
   - *A grupos de Entra ID, nunca a usuarios sueltos.*
8. ¿Qué es la arquitectura medallion?
   - *Zonas bronce (crudo), plata (limpio) y oro (negocio) con permisos distintos.*
9. ¿Cómo publicas un lote sin que Spark lea archivos a medias?
   - *Escribes en `_tmp/` con `append` + `flush` y renombras a la partición final.*
10. ¿Por qué evitar millones de archivos pequeños?
    - *Lentitud y costo de transacciones; compacta a Parquet/Delta.*
11. ¿Qué endpoints/Private Endpoints necesitas?
    - *`dfs` y `blob` (dos subrecursos) con sus zonas DNS privadas.*
12. ¿Cuándo no usar HNS?
    - *Si solo sirves objetos a una web y necesitas funciones de Blob no soportadas con HNS, o hay pocos archivos pequeños.*
13. ¿Se puede activar HNS después?
    - *Sí, con migración validada, pero es de ida y con ventana de mantenimiento.*

## Entrevista
- Diseña las zonas, los grupos y las ACL de un lago para tres dominios (ventas, logística, finanzas).
- Un analista ve la carpeta pero no los archivos: diagnostica.
- ¿Cómo reprocesas silver tras un borrado accidental?
- ¿SFTP, Data Factory o Event Hubs Capture para una ingesta? Compara.

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf).
2. Crea la jerarquía y aplica ACL con la [CLI](ejemplos/cli/data-lake.sh).
3. Prueba con una identidad del grupo de analistas: listar sí, escribir no.
4. Publica un lote con el código de [uso en Java](uso-en-java.md) y comprueba que aparece completo tras el renombrado.
5. Quita un `x` de un directorio padre y observa el 403.
