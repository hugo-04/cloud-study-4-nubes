# Oracle OCI · IAM · Grupos dinámicos y principales · Casos reales

## 1. El `ANY` que incluyó a todos
**Qué pasó:** una VM de pruebas leyó el bucket de producción.
**Causa:** la regla era `ANY {instance.compartment.id = 'a', instance.compartment.id = 'b'}` y `b` era sandbox.
**Arreglo:** un grupo por entorno con `ALL` y un solo compartimento.
**Lección:** cada compartimento extra en `ANY` ensancha el acceso.

## 2. La etiqueta que cambió de dueño
**Qué pasó:** un desarrollador etiquetó su VM con `app=tienda` y obtuvo permisos de producción.
**Causa:** la pertenencia dependía de una etiqueta que cualquiera podía poner.
**Arreglo:** regla con compartimento + etiqueta y permisos de etiquetado restringidos.
**Lección:** quien controla la etiqueta, controla el acceso.

## 3. Las llaves dentro de la VM
**Qué pasó:** una llave API de un usuario terminó en una imagen compartida.
**Causa:** el código leía `~/.oci/config`.
**Arreglo:** `InstancePrincipalsAuthenticationDetailsProvider` y revocación de la llave.
**Lección:** las máquinas se autentican con su identidad, no con llaves.

## 4. «Not authenticated» recién creada la VM
**Qué pasó:** la app falló los primeros segundos.
**Causa:** propagación del grupo y la política.
**Arreglo:** reintentos con espera al arrancar.
**Lección:** los cambios de IAM no son instantáneos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Lectura entre entornos | `ANY` amplio | `ALL` por entorno |
| 2 | Permisos inesperados | Etiqueta libre | Restringir etiquetado |
| 3 | Llave filtrada | Config de usuario en la VM | Instance principal |
| 4 | Fallo al arrancar | Propagación | Reintentos |
