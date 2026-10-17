# AWS · Parameter Store · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El deploy para cambiar un número
**Qué pasó:** cambiar el tamaño del pool de la base exigía recompilar y desplegar. **Solución:** `/prod/pedidos/db/pool-max` en Parameter Store, leído al arrancar. **Lección:** la configuración que cambia sin código va fuera del código.

## 2. Mil lecturas por segundo
**Qué pasó:** cada petición consultaba `GetParameter` y llegó `ThrottlingException`. **Solución:** `GetParametersByPath` de toda la rama al iniciar y refresco cada 5 minutos. **Lección:** una llamada por rama, no una por valor.

## 3. Contraseña rotativa en Parameter Store
**Qué pasó:** se guardó la contraseña de la base como SecureString y nadie la rotó en un año. **Solución:** moverla a Secrets Manager con rotación; en Parameter Store quedó una **referencia** al secreto. **Lección:** configuración aquí, credenciales rotativas en Secrets Manager.

## 4. Permiso demasiado amplio
**Qué pasó:** el rol de Pedidos podía leer `/prod/*` y vio parámetros de Facturas. **Solución:** permisos por ruta (`/prod/pedidos/*`). **Lección:** la jerarquía es el modelo de permisos.

## 5. La bandera que se rompió en producción
**Qué pasó:** una bandera con un valor mal escrito (`"ture"`) llegó a todos los pods al instante. **Solución:** validación tipada en la aplicación (valor por defecto seguro y alerta), y AppConfig con despliegue gradual para banderas críticas. **Lección:** la configuración también necesita ser desplegada con cuidado.

## 6. Cuál era el valor de ayer
**Qué pasó:** un incidente por un cambio de umbral; nadie sabía qué valor había antes. **Solución:** el historial de versiones del parámetro (`GetParameterHistory`) y etiquetas (`estable`). **Lección:** el historial es auditoría gratis.

| Problema | Solución |
|---|---|
| Cambiar un valor = deploy | Parameter Store |
| Throttling | Leer rama + caché |
| Contraseña sin rotar | Secrets Manager |
| Permiso amplio | Por ruta |
| Valor mal escrito | Validación + AppConfig |
| Falta de historial | Versiones y etiquetas |
