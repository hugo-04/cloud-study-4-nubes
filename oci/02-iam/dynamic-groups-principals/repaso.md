# Oracle OCI · IAM · Grupos dinámicos y principales · Repaso

## Preguntas
1. ¿Qué es un grupo dinámico?
2. ¿Qué diferencia hay entre `ALL` y `ANY`?
3. ¿Qué es un instance principal?
4. ¿Qué es un resource principal?
5. ¿Por qué es riesgoso usar etiquetas en la regla?
6. ¿De dónde obtiene la VM su token?
7. ¿Qué reglas debes evitar?
8. ¿Por qué un grupo por aplicación?
9. ¿Qué proveedor de credenciales usas en una función de OCI?
10. ¿Qué haces si falla justo al crear la VM?

## Respuestas
1. Un conjunto de recursos definido por una regla, que puede citarse en políticas.
2. `ALL` exige todas las condiciones; `ANY`, al menos una.
3. La VM actúa como identidad con credenciales emitidas por OCI.
4. Una función u otro servicio que actúa como identidad.
5. Quien pueda etiquetar puede entrar al grupo.
6. Del servicio de metadatos local.
7. `ANY` sin acotar, o sin compartimento.
8. Para dar el mínimo permiso y revisar mejor.
9. `ResourcePrincipalAuthenticationDetailsProvider`.
10. Reintentar con espera: la propagación toma unos segundos.

## Ejercicios
1. Escribe una regla `ALL` para las VM de `tienda-prod` etiquetadas `app.nombre=tienda`.
2. Reescribe `ANY {instance.compartment.id='a', instance.compartment.id='b'}` de forma segura.
3. Define la política para que ese grupo lea solo el bucket `comprobantes`.
