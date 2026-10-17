# Google Cloud · Compute · Compute Engine · Casos reales

## 1. La VM «mascota»
**Qué pasó:** la única VM del ERP de ModaLima se dañó y nadie sabía cómo recrearla.
**Causa:** configuración hecha a mano durante años.
**Arreglo:** imagen endurecida, plantilla y MIG de tamaño 1 con autocuración.
**Lección:** si no puedes recrearla con código, no la tienes.

## 2. El minero en la VM de pruebas
**Qué pasó:** una VM con IP externa y SSH abierto terminó minando criptomonedas.
**Causa:** llave SSH débil y puerto expuesto.
**Arreglo:** sin IP externa, OS Login con IAP y política de organización.
**Lección:** la VM no debe ser alcanzable desde Internet.

## 3. Lotes que costaban demasiado
**Qué pasó:** el procesamiento nocturno de imágenes de Café Andino costaba más que la tienda.
**Causa:** VMs estándar para trabajo interrumpible.
**Arreglo:** VMs Spot en un MIG con reintentos por tarea.
**Lección:** lo que tolera interrupciones, en Spot.

## 4. El despliegue que bajó todo
**Qué pasó:** actualizar la plantilla reemplazó todas las VMs a la vez.
**Causa:** actualización con `maxUnavailable` alto.
**Arreglo:** actualización progresiva `maxSurge 1`, `maxUnavailable 0` y chequeo de salud.
**Lección:** las actualizaciones también se planifican.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | No se puede recrear | Configuración manual | Plantilla + MIG |
| 2 | VM comprometida | IP externa + SSH | IAP + OS Login |
| 3 | Costo alto | VMs estándar en lotes | Spot |
| 4 | Caída al actualizar | Reemplazo masivo | Progresiva |
