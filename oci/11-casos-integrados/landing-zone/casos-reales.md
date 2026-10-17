# Oracle OCI · Caso integrado · Landing zone · Casos reales

## 1. El CIDR repetido
**Qué pasó:** la nueva unidad de Café Andino no podía conectarse a la central por el DRG.
**Causa:** su VCN usaba el mismo rango que otra unidad.
**Arreglo:** planificador que lee las VCN existentes y reserva un rango libre; registro de rangos en el repositorio.
**Lección:** las direcciones se planifican antes de crear.

## 2. La unidad que se dio más permisos
**Qué pasó:** los admins de la unidad editaron sus políticas y se dieron acceso a la red compartida.
**Causa:** `manage all-resources` incluía `policies`.
**Arreglo:** excluir IAM y red compartida del alcance de la unidad.
**Lección:** quien recibe permisos no debe poder ampliarlos.

## 3. Apply exitoso, landing incompleta
**Qué pasó:** el `apply` terminó «bien» pero la regla de Cloud Guard nunca se creó por un error de región ignorado.
**Causa:** sin verificación posterior.
**Arreglo:** verificador que revisa cada pieza; si no puede leer algo, lo reporta.
**Lección:** comprueba el resultado, no solo el proceso.

## 4. La primera factura sorpresa
**Qué pasó:** en la primera semana se gastó el presupuesto del mes en pruebas de carga.
**Causa:** presupuesto y cuotas se iban a configurar «después».
**Arreglo:** cuotas y alertas proyectadas como parte de la landing.
**Lección:** los guardarraíles se instalan antes de abrir.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin conectividad | CIDR solapado | Planificador |
| 2 | Escalada de permisos | Alcance amplio | Excluir IAM/red |
| 3 | Piezas faltantes | Sin verificación | Verificador |
| 4 | Gasto temprano | Controles tardíos | Cuotas + presupuesto al inicio |
