# AWS · Secrets Manager · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La rotación que tumbó los pedidos
**Qué pasó:** la rotación cambió la clave de Aurora y las conexiones del pool de la aplicación, con la clave vieja, empezaron a fallar con `password authentication failed`. **Solución:** estrategia de **usuarios alternos**, caché con TTL corto y recarga del secreto ante un fallo de autenticación (reintentando una vez con la versión actual). **Lección:** rotar es un acuerdo entre el secreto, la base y la aplicación.

## 2. Mil llamadas por segundo
**Qué pasó:** cada petición leía el secreto; la factura y la latencia se dispararon y llegó el error `ThrottlingException`. **Solución:** caché en memoria con TTL de 5 minutos y refresco en segundo plano. **Lección:** el secreto se lee al arrancar y cuando cambia, no por petición.

## 3. La clave de API en el repositorio
**Qué pasó:** una clave de un proveedor de pagos quedó en `application-prod.yml`. **Solución:** rotar la clave, moverla a un secreto, detectar secretos en el CI y dar el permiso solo al rol del servicio. **Lección:** un secreto en Git ya está comprometido.

## 4. Secreto compartido entre cuentas
**Qué pasó:** la cuenta de reportes no podía leer un secreto de la cuenta de datos: `AccessDeniedException` aun con política de recurso. **Causa:** el secreto usaba la clave gestionada `aws/secretsmanager`, que no se puede compartir. **Solución:** CMK propia con política que permite la cuenta de reportes. **Lección:** entre cuentas necesitas CMK.

## 5. El borrado accidental
**Qué pasó:** un `terraform destroy` en dev borró un secreto de prod con el mismo nombre. **Solución:** ventana de recuperación de 30 días (se restauró) y nombres con prefijo de entorno más permisos separados. **Lección:** la ventana de recuperación salvó el día.

## 6. ECS no refrescaba
**Qué pasó:** tras la rotación, las tareas de ECS siguieron con la clave vieja. **Causa:** la inyección por `secrets:` solo ocurre al **arrancar** la tarea. **Solución:** que la aplicación lea con el SDK y caché (o relanzar las tareas tras rotar). **Lección:** conoce cuándo se inyecta cada integración.

| Problema | Solución |
|---|---|
| Rotación rompe conexiones | Usuarios alternos + recarga |
| Costo y límite de API | Caché con TTL |
| Secreto en Git | Rotar + escaneo + secreto |
| Entre cuentas | CMK propia |
| Borrado | Ventana de 30 días |
| Inyección no refresca | Leer con SDK + caché |
