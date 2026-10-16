# Azure · App Service · Repaso

## Preguntas de repaso
1. ¿Qué diferencia hay entre el *plan* y la *app*?
   - *El plan son las máquinas (y se factura); la app es tu código dentro del plan. Varias apps pueden compartir un plan.*
2. ¿Qué diferencia hay entre VNet Integration y Private Endpoint?
   - *VNet Integration controla la **salida** de la app; Private Endpoint controla la **entrada**. A menudo hacen falta las dos.*
3. ¿Para qué sirven los slots y qué es un slot setting?
   - *Desplegar y calentar una versión sin afectar producción y hacer swap sin caída; un slot setting no viaja con el swap.*
4. ¿Por qué `X-Forwarded-Proto` importa en Spring Boot/Quarkus?
   - *El TLS termina en el front end; sin esa cabecera el framework cree que es HTTP y genera redirecciones y enlaces incorrectos.*
5. ¿Por qué un `@Scheduled` puede ejecutarse varias veces?
   - *Corre en cada instancia del plan; hay que usar bloqueo distribuido o mover la tarea.*
6. ¿Qué hace el health check de la plataforma y qué requisito tiene?
   - *Consulta una ruta cada minuto y saca instancias enfermas; necesita 2 o más instancias.*
7. ¿Qué es ARR affinity y cuándo se desactiva?
   - *Cookie que pega al cliente a una instancia; se desactiva en APIs sin estado.*
8. ¿Dónde se puede guardar un archivo que sobreviva a un reinicio?
   - *Solo `/home` (compartido) o, mejor, Blob Storage; el resto del disco es efímero.*
9. ¿Cómo se despliega sin secretos desde GitHub?
   - *Credencial federada (OIDC) sobre una identidad con *Website Contributor*; `azure/login` sin contraseña.*
10. ¿Cómo lee la app un secreto sin tener la contraseña en su configuración?
    - *Referencia a Key Vault `@Microsoft.KeyVault(...)` con la identidad de la app, o SDK con `DefaultAzureCredential`.*
11. ¿Cuánto dura como máximo una petición HTTP en el front end?
    - *Del orden de 230 segundos: para trabajos largos, responde 202.*
12. ¿Cuándo prefieres Container Apps o AKS a App Service?
    - *Escala a cero o muchos microservicios con políticas de red y mallas, respectivamente.*

## Entrevista
- Describe un despliegue sin caída de una API Spring Boot en App Service.
- Tu API tarda 40 s en estar lista tras cada swap: ¿qué investigas y qué cambias?
- Una API en App Service no alcanza a su PostgreSQL privado. Recorre el diagnóstico.
- ¿Cómo evitas que un cron de resumen diario se ejecute en las 3 instancias?
- ¿Cuándo un único plan para 15 apps es mala idea?

## Ejercicio práctico
1. Ejecuta `ejemplos/cli/app-service.sh` hasta la sección 5 y despliega un JAR de ejemplo al slot `staging`.
2. Haz el swap y vuelve a hacerlo para practicar el rollback.
3. Entra a Kudu y usa `nameresolver` y `tcpping` contra un recurso privado.
4. Provoca un 503 cambiando el puerto y encuéntralo en el *Log stream*.
