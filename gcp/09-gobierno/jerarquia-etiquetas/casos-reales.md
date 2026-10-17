# Google Cloud · Gobierno · Jerarquía y etiquetas · Casos reales

## 1. El editor en la organización
**Qué pasó:** un contratista de ModaLima tenía `roles/editor` en la organización y borró un bucket de producción.
**Causa:** permiso dado arriba para «agilizar».
**Arreglo:** roles en carpetas de no-prod y política de denegación de borrado en prod.
**Lección:** la herencia también hereda errores.

## 2. Costos sin dueño
**Qué pasó:** el 30 % de la factura de Café Andino no tenía equipo asignado.
**Causa:** labels opcionales y con nombres distintos.
**Arreglo:** labels obligatorios validados en el pipeline y reporte semanal.
**Lección:** sin label no hay *showback*.

## 3. La clasificación que cualquiera cambiaba
**Qué pasó:** un label `datos=publicos` permitió saltar una regla interna.
**Causa:** cualquiera con permiso de edición cambia labels.
**Arreglo:** tag `clasificacion` con `tagUser` solo para seguridad.
**Lección:** decisiones de seguridad con tags.

## 4. El proyecto borrado
**Qué pasó:** un `terraform destroy` en el workspace equivocado borró un proyecto.
**Causa:** sin lien.
**Arreglo:** restaurarlo dentro del periodo de gracia y poner liens.
**Lección:** candado en lo crítico.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Borrado en prod | Rol heredado | Roles por carpeta |
| 2 | Costos huérfanos | Labels libres | Validación en CI |
| 3 | Regla saltada | Label editable | Tag con permisos |
| 4 | Proyecto borrado | Sin lien | Lien |
