# Azure · Blob Storage · Repaso

## Preguntas de repaso
1. ¿Cuál es la jerarquía de Blob Storage?
   - *Cuenta → contenedor → blob; las "carpetas" son prefijos (salvo namespace jerárquico).*
2. ¿Diferencia entre block, append y page blob?
   - *Block: archivos en bloques; append: logs que crecen; page: discos de VM.*
3. ¿Cuándo existe realmente un block blob que se sube por bloques?
   - *Al confirmar la lista de bloques (`Put Block List`); ahí se emite `BlobCreated`.*
4. Explica Hot, Cool, Cold y Archive.
   - *Frecuencia de acceso vs costo; permanencias mínimas 30/90/180 días; Archive es offline y se rehidrata.*
5. ¿LRS, ZRS, GRS y GZRS?
   - *Copias en un data center; en tres zonas; a otra región; zonas + otra región.*
6. ¿Qué es la inmutabilidad (WORM) y cuándo la usas?
   - *Impide modificar/borrar por un periodo o con legal hold; cumplimiento y defensa ante ransomware.*
7. ¿Cómo evitas sobrescribir un blob que otro modificó?
   - *Escritura condicional con ETag (`If-Match`); `If-None-Match:*` para crear solo si no existe.*
8. ¿Qué rol necesita una app para leer y cuál para emitir SAS?
   - *Lectura: Storage Blob Data Reader. SAS: Storage Blob Delegator + un rol de datos.*
9. ¿Por qué un *Contributor* de la cuenta no puede leer blobs?
   - *Son planos distintos: administración vs datos.*
10. ¿Qué haces ante `503 ServerBusy`?
    - *Reintentos con backoff exponencial, repartir nombres/carga, reducir concurrencia, considerar más cuentas.*
11. ¿Cómo haces una cuenta solo privada?
    - *`publicNetworkAccess=Disabled`, Private Endpoint + zona DNS privada.*
12. ¿Qué ahorra más dinero en Blob Storage?
    - *El ciclo de vida (mover a tiers fríos y borrar).*
13. ¿Por qué no se debe cargar un blob grande en memoria?
    - *Riesgo de `OutOfMemoryError`; usa streaming o `downloadToFile`.*
14. ¿Qué es el namespace jerárquico y qué implica activarlo?
    - *Convierte la cuenta en Data Lake Gen2 (directorios, ACL, renombrado atómico); no se desactiva.*

## Entrevista
- Diseña el almacenamiento de fotos de producto: tiers, seguridad, ciclo de vida, CDN.
- ¿Cómo protegerías los respaldos contra ransomware?
- Una carga masiva está dando 503: ¿qué revisas y qué cambias?
- ¿Cómo migras 50 TB desde un servidor local a Blob con mínimo tiempo de inactividad?

## Ejercicio práctico
1. Crea la cuenta con el Terraform de [ejemplos](ejemplos/terraform/main.tf).
2. Activa soft delete y versionado; borra y recupera un blob.
3. Aplica una regla de ciclo de vida y verifica con el inventario.
4. Sube un archivo grande con bloques y concurrencia 8 usando el SDK y mide.
5. Provoca un `412` con dos escritores y arréglalo con ETag.
