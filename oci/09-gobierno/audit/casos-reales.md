# Oracle OCI · Gobierno · Audit · Casos reales

## 1. ¿Quién borró la base de pruebas?
**Qué pasó:** desapareció una base de no-prod de ModaLima y todos negaban haberla tocado.
**Causa:** —
**Arreglo:** Audit mostró `DeleteAutonomousDatabase` por el usuario del pipeline a las 02:13; un `destroy` en el directorio equivocado.
**Lección:** Audit convierte discusiones en hechos.

## 2. La auditoría de hace dos años
**Qué pasó:** un auditor de Café Andino pidió los cambios de IAM de hace 18 meses.
**Causa:** retención de 365 días y sin copia.
**Arreglo:** Service Connector continuo a Object Storage con retención de 7 años.
**Lección:** la retención de cumplimiento se planifica antes de necesitarla.

## 3. El cambio a las 3 a. m.
**Qué pasó:** una política se amplió de madrugada desde una IP extranjera.
**Causa:** credenciales de API filtradas.
**Arreglo:** detector de operaciones sensibles fuera de horario e IP no habitual, rotación de llaves y MFA.
**Lección:** mira Audit en tiempo casi real, no solo forense.

## 4. La cuenta compartida
**Qué pasó:** no se pudo saber qué persona hizo un cambio.
**Causa:** cinco personas usaban el mismo usuario.
**Arreglo:** usuarios nominales vía federación.
**Lección:** Audit solo es útil si las identidades son personales.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Recurso borrado | — | Evidencia en Audit |
| 2 | Sin datos antiguos | Retención | Copia a Object Storage |
| 3 | Cambio sospechoso | Credencial filtrada | Detección + rotación |
| 4 | Autor desconocido | Cuenta compartida | Usuarios nominales |
