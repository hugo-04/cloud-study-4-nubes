# Google Cloud · Gobierno · Presupuestos y costos · Casos reales

## 1. El clúster olvidado
**Qué pasó:** un GKE de pruebas de ModaLima quedó encendido un mes con 20 nodos.
**Causa:** sin presupuesto en el proyecto.
**Arreglo:** presupuesto con umbral pronosticado del 80 % y reacción que escala nodos a cero en sandbox.
**Lección:** el aviso temprano vale más que el detalle tardío.

## 2. «¿Cuánto cuesta el equipo de pagos?»
**Qué pasó:** finanzas de Café Andino no podía repartir la factura.
**Causa:** exportación activada recién ese mes y sin labels.
**Arreglo:** labels obligatorios y consulta por `labels.equipo`.
**Lección:** la exportación no es retroactiva.

## 3. La llave filtrada que minaba
**Qué pasó:** una llave de SA filtrada creó VMs con GPU en otra región.
**Causa:** sin cuotas ni restricción de regiones.
**Arreglo:** `gcp.resourceLocations`, cuotas de GPU en cero y sin llaves de SA.
**Lección:** cuotas y políticas son control de costos.

## 4. La reacción que borró datos
**Qué pasó:** una función desvinculó la facturación de un proyecto con datos de clientes.
**Causa:** automatización aplicada también a producción.
**Arreglo:** acción solo en proyectos con tag `entorno=sandbox`.
**Lección:** acota la automatización.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Gasto olvidado | Sin presupuesto | Pronosticado + reacción |
| 2 | Sin reparto | Sin exportación/labels | Exportar + labels |
| 3 | Abuso | Sin cuotas | Cuotas + políticas |
| 4 | Daño | Automatización amplia | Solo sandbox |
