# Oracle OCI · Compute · Instancias · Casos reales

## 1. El dev que nunca dormía
**Qué pasó:** la factura de desarrollo igualaba la de producción.
**Causa:** 30 VM encendidas 24/7, usadas 10 horas al día.
**Arreglo:** etiqueta `horario` y un planificador que apaga y enciende.
**Lección:** lo que no se usa, se apaga.

## 2. SSH abierto al mundo
**Qué pasó:** miles de intentos de acceso a una VM.
**Causa:** IP pública y puerto 22 abierto a `0.0.0.0/0`.
**Arreglo:** subred privada y Bastion con sesiones temporales.
**Lección:** administración por canal controlado.

## 3. La llave en el disco
**Qué pasó:** una llave API quedó en una imagen personalizada.
**Causa:** el script de la app leía `~/.oci/config`.
**Arreglo:** instance principal y revocar la llave.
**Lección:** la VM ya tiene identidad.

## 4. Forma Arm sin imagen compatible
**Qué pasó:** la VM Ampere arrancaba pero la app no.
**Causa:** imagen y binarios x86.
**Arreglo:** imagen aarch64 y contenedor multi-arquitectura.
**Lección:** forma e imagen deben coincidir en arquitectura.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Costo alto en dev | Siempre encendidas | Apagado programado |
| 2 | Ataques SSH | IP pública | Bastion |
| 3 | Llave filtrada | Config de usuario | Instance principal |
| 4 | App no arranca | Arquitectura | Imagen aarch64 |
