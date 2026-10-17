# Google Cloud · IAM · Cuentas de servicio · Casos reales

## 1. La llave en la imagen
**Qué pasó:** una imagen pública de un contenedor de ModaLima incluía una llave JSON con permisos de escritura en buckets.
**Causa:** se copió la llave para «probar en local».
**Arreglo:** revocar la llave, bloquear la creación de llaves por política y usar suplantación/ADC.
**Lección:** las llaves se filtran; los tokens de 1 hora caducan.

## 2. La cuenta por defecto con editor
**Qué pasó:** una VM comprometida pudo borrar recursos de todo el proyecto.
**Causa:** usaba la cuenta por defecto de Compute con `editor`.
**Arreglo:** cuenta propia con roles mínimos; desactivar concesiones automáticas.
**Lección:** nunca la cuenta por defecto.

## 3. Todos podían desplegar como pagos
**Qué pasó:** un servicio de Café Andino se desplegó con la cuenta de pagos para «tener permisos».
**Causa:** `serviceAccountUser` a nivel de proyecto para todo el equipo.
**Arreglo:** el rol solo sobre la cuenta concreta y solo al pipeline.
**Lección:** «actuar como» es un privilegio.

## 4. Borrar la cuenta rompió la app
**Qué pasó:** al limpiar cuentas viejas, una tarea nocturna dejó de funcionar.
**Causa:** se borró sin deshabilitar antes.
**Arreglo:** deshabilitar, esperar un ciclo, revisar registros y recién borrar.
**Lección:** primero deshabilitar.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Llave filtrada | Llave JSON | ADC + suplantación + política |
| 2 | Daño amplio | Cuenta por defecto | Cuenta propia mínima |
| 3 | Escalada | `serviceAccountUser` amplio | Por cuenta |
| 4 | Tarea rota | Borrado directo | Deshabilitar primero |
