# AWS · Caso integrado · Landing zone · Casos reales

## 1. Las dos redes que no se podían conectar
**Qué pasó:** `pagos-prod` y `catalogo-prod` usaban `10.0.0.0/16`; al conectarlas con Transit Gateway no había forma.
**Arreglo:** asignador de CIDR con reservas (on-premises incluido) y rechazo de solapamientos.
**Lección:** el solapamiento de redes es irreversible sin recrear.

## 2. El trail apagado a las 3 a. m.
**Qué pasó:** alguien con permisos amplios detuvo CloudTrail «para probar».
**Arreglo:** SCP en la raíz que impide `StopLogging/DeleteTrail`.
**Lección:** lo crítico se impide, no solo se documenta.

## 3. La cuenta de producción en la carpeta equivocada
**Qué pasó:** `pagos-prod` estaba en NoProd y no heredaba las barandas estrictas.
**Arreglo:** regla en el plan y en la verificación: `-prod` solo en la OU Prod.
**Lección:** la ubicación es una configuración de seguridad.

## 4. El verificador que decía «todo bien»
**Qué pasó:** el informe no mostraba hallazgos… porque el rol de auditoría no existía en cuentas nuevas y los errores se ignoraban.
**Arreglo:** «no se pudo verificar» es un hallazgo de gravedad ALTA.
**Lección:** ausencia de evidencia no es evidencia de cumplimiento.

## 5. `terraform destroy` en la cuenta equivocada
**Qué pasó:** al borrar una entrada del mapa, Terraform intentó cerrar la cuenta.
**Arreglo:** `prevent_destroy`, `close_on_deletion = false` y revisión obligatoria del plan.
**Lección:** las cuentas no son recursos desechables.

## 6. El gasto de un sandbox olvidado
**Qué pasó:** una cuenta de pruebas acumuló gasto durante un mes.
**Arreglo:** presupuesto por cuenta con alerta de pronóstico y etiquetas de equipo.
**Lección:** quien crea la cuenta define su techo de gasto.

## Resumen
| # | Síntoma | Pieza que lo evita |
|---|---|---|
| 1 | Redes solapadas | Asignador de CIDR |
| 2 | Auditoría apagada | SCP en la raíz |
| 3 | Cuenta fuera de la OU | Validación + verificación |
| 4 | Informe engañoso | «No verificable» = hallazgo |
| 5 | Cuenta borrada por error | `prevent_destroy` y revisión |
| 6 | Gasto sin dueño | Presupuesto y etiquetas |
