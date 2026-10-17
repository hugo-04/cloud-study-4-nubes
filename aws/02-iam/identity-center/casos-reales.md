# AWS · IAM Identity Center · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La persona que se fue y su clave se quedó
**Qué pasó:** una desarrolladora salió de la empresa y su usuario IAM con clave siguió activo seis meses. **Solución:** Identity Center con SCIM: al darla de baja en el directorio, todos los accesos desaparecen en minutos. **Lección:** el acceso humano debe morir con el contrato.

## 2. Administrador en producción «por comodidad»
**Qué pasó:** diez personas con administrador en producción; una borró una tabla en horario de trabajo. **Solución:** `SoloLectura` por defecto, `AdministradorPlataforma` solo para el grupo de plataforma y bajo aprobación; sesión de 1 h. **Lección:** el privilegio se pide, no se tiene.

## 3. La región que no se pudo cambiar
**Qué pasó:** se activó Identity Center en la región equivocada y la organización exigía otra. **Solución:** ser consciente de que es una decisión de una sola vez y planificarla (en este caso, rehacer la configuración). **Lección:** elige la región de origen con calma.

## 4. El proveedor de identidad cayó
**Qué pasó:** una interrupción del proveedor externo dejó a todos sin acceso durante una caída. **Solución:** cuenta de emergencia con MFA físico, en una bóveda, probada cada trimestre y con alarma. **Lección:** el plan B se prueba antes.

## 5. Cien asignaciones a mano
**Qué pasó:** cada alta era un trámite de 15 clics por cuenta. **Solución:** asignaciones como código por grupo × cuenta × conjunto de permisos. **Lección:** lo repetitivo se automatiza.

## 6. ABAC por departamento
**Qué pasó:** un conjunto de permisos por proyecto: 40 conjuntos casi iguales. **Solución:** un conjunto con atributos (`proyecto`) que llegan del directorio y condiciones por etiqueta. **Lección:** atributos bien mantenidos sustituyen la proliferación.

| Problema | Solución |
|---|---|
| Bajas lentas | SCIM |
| Administrador permanente | Mínimo + bajo demanda |
| Región equivocada | Decisión planificada |
| Proveedor caído | Cuenta de emergencia |
| Altas manuales | Asignaciones como código |
| Explosión de conjuntos | ABAC |
