# Oracle OCI · Gobierno · Compartimentos, etiquetas y cuotas · Casos reales

## 1. La factura sin dueño
**Qué pasó:** el 40 % del gasto de ModaLima no se podía asignar a ningún producto.
**Causa:** etiquetas libres escritas de diez formas (`Tienda`, `tienda`, `store`…).
**Arreglo:** etiqueta definida `Gobierno.centro_costo` con lista de valores y etiqueta por defecto obligatoria.
**Lección:** sin validación, las etiquetas no sirven para costos.

## 2. La GPU de prueba
**Qué pasó:** alguien probó un modelo en no-prod con una GPU y la dejó encendida un mes.
**Causa:** sin cuotas.
**Arreglo:** `zero gpu-family` en no-prod y cuota de OCPU.
**Lección:** pon topes donde se experimenta.

## 3. El recurso que perdió permisos
**Qué pasó:** una base movida de `no-prod` a `prod` dejó de ser accesible para la app.
**Causa:** las políticas efectivas cambiaron con el compartimento.
**Arreglo:** revisar políticas antes de mover y limitar quién puede mover.
**Lección:** el compartimento es parte del permiso.

## 4. La jerarquía laberinto
**Qué pasó:** Café Andino tenía 6 niveles de compartimentos y nadie sabía dónde crear nada.
**Causa:** se copió el organigrama completo.
**Arreglo:** 3 niveles: unidad → entorno → sistema.
**Lección:** la estructura sirve a los permisos, no al organigrama.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Gasto sin dueño | Etiquetas libres | Definidas + obligatorias |
| 2 | Gasto inesperado | Sin cuotas | `zero` y topes |
| 3 | Acceso roto al mover | Políticas por compartimento | Revisar antes de mover |
| 4 | Confusión | Jerarquía profunda | 3 niveles |
