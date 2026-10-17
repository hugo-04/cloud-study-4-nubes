# Oracle OCI · Gobierno · Presupuestos y costos · Casos reales

## 1. El aviso del día 30
**Qué pasó:** ModaLima supo que se había pasado del presupuesto cuando ya era fin de mes.
**Causa:** solo alertas sobre gasto real al 100 %.
**Arreglo:** alerta proyectada al 100 % y real al 80 %.
**Lección:** proyecta, no solo mires el pasado.

## 2. «El presupuesto no apagó nada»
**Qué pasó:** Café Andino esperaba que el presupuesto detuviera los recursos al llegar al tope.
**Causa:** los presupuestos solo avisan.
**Arreglo:** cuotas en no-prod y una función que apaga entornos de prueba ante la alerta (con aprobación).
**Lección:** avisar y frenar son herramientas distintas.

## 3. El servicio que subió en silencio
**Qué pasó:** el costo de salida de datos se triplicó sin que el total pasara el umbral.
**Causa:** alertas solo sobre el total.
**Arreglo:** reporte diario por servicio con variación contra la semana anterior.
**Lección:** mira la composición, no solo el total.

## 4. Gasto huérfano
**Qué pasó:** el 35 % del gasto no tenía `centro_costo`.
**Causa:** recursos creados antes de la etiqueta obligatoria.
**Arreglo:** campaña de etiquetado con el revisor de gobierno y etiqueta por defecto.
**Lección:** etiqueta desde el día uno.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Aviso tardío | Solo alerta real | Alerta proyectada |
| 2 | Recursos siguen | Presupuesto no frena | Cuotas / automatización |
| 3 | Subida oculta | Solo total | Por servicio |
| 4 | Gasto sin dueño | Sin etiquetas | Etiqueta obligatoria |
