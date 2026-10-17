# Azure · Terraform · Estado remoto · Repaso

## Preguntas de repaso
1. ¿Qué guarda el estado de Terraform y por qué hace falta?
   - *La correspondencia entre cada bloque del código y el recurso real (ID y atributos); sin él, Terraform no sabe qué ya existe.*
2. ¿Por qué se dice que el estado es tan sensible como un secreto?
   - *Guarda los atributos de los recursos en texto claro, incluidas contraseñas generadas y cadenas de conexión; `sensitive = true` solo los oculta en pantalla.*
3. ¿Dónde se guarda el estado en Azure y cómo se bloquea?
   - *Como un blob en una cuenta de almacenamiento (backend `azurerm`); el bloqueo es un arrendamiento (lease) del blob.*
4. ¿Qué hacer ante `Error acquiring the state lock`?
   - *Esperar; si está huérfano y se confirmó que nadie aplica, `terraform force-unlock <ID>` (o romper el lease como último recurso).*
5. ¿Por qué el bloque `backend` no admite variables?
   - *Porque se evalúa antes que el resto del código; los valores variables se pasan con `-backend-config`.*
6. ¿Qué rol pide la documentación del backend con `use_azuread_auth` y dónde se asigna?
   - *Storage Blob Data Owner (o Container Blob Data Owner) sobre el contenedor.*
7. ¿Por qué desactivar las claves de la cuenta es una migración?
   - *Porque antes hay que dar roles de datos a las identidades y cambiar el backend a Entra ID/OIDC; si no, todo falla con 403.*
8. ¿Qué protegen el versionado y el borrado suave?
   - *Recuperar un estado sobrescrito o dañado (versiones) y un blob o contenedor borrado (borrado suave).*
9. ¿Cuándo dividir un estado y con qué criterio?
   - *Cuando los planes son lentos o el equipo se pisa; por ciclo de vida, dueño y radio de daño.*
10. ¿Por qué un workspace no es buena idea para separar dev y prod?
    - *Comparten backend y credenciales; dev y prod necesitan permisos distintos, así que se separan por clave/carpeta y contenedor o cuenta.*
11. ¿Qué riesgo tiene `terraform_remote_state`?
    - *Quien lo lee puede ver todo el contenido del otro estado, secretos incluidos; mejor un data source.*
12. ¿Qué diferencia hay entre `terraform init -migrate-state` y `-reconfigure`?
    - *`-migrate-state` copia el estado al nuevo backend; `-reconfigure` solo apunta al nuevo sin copiar.*
13. ¿Para qué sirven los bloques `moved`, `import` y `removed`?
    - *Renombrar sin destruir, traer lo que ya existe y dejar de administrar sin borrar; todo dentro del código y la revisión.*
14. ¿Qué hace `terraform plan -refresh-only`?
    - *Muestra la diferencia entre el estado y la realidad sin cambiar Azure; sirve para detectar drift.*
15. ¿Por qué el `plan` también necesita escribir en el contenedor?
    - *Porque toma el bloqueo del estado.*
16. ¿Por qué los ejecutores públicos de los pipelines chocan con el firewall de la cuenta?
    - *No tienen IP estable; se necesitan runners propios con Private Endpoint o IP/subredes conocidas.*
17. ¿Qué es el bootstrap del estado y cómo se resuelve el huevo y la gallina?
    - *Crear el almacén con estado local y luego migrar el estado a sí mismo con `init -migrate-state`.*
18. ¿Qué evita el bloqueo `CanNotDelete` sobre la cuenta de estados?
    - *Que se borre la cuenta entera por error; no impide leer ni escribir blobs.*
19. ¿Qué pasa si una versión nueva de Terraform escribe el estado?
    - *Las versiones antiguas pueden negarse a leerlo; por eso se fija `required_version` para todos.*
20. ¿Cómo sabes quién borró un estado?
    - *Con el diagnóstico de la cuenta enviado a Log Analytics y las consultas KQL de borrados y bloqueos rotos.*

## Mini-ejercicios
1. Escribe el `backend.hcl` y `backend.tf` de `prod/app-pedidos`, sabiendo que la cuenta es `stmodalimaprodtfstate01`.
2. Diseña las claves de estado para ModaLima: gobierno, red central, red por entorno, tres aplicaciones en dev y prod.
3. Simula un candado huérfano: ¿qué 4 comprobaciones haces antes de `force-unlock`?
4. Planifica la migración de claves de cuenta a Entra ID para 12 pipelines: orden de pasos y qué se verifica entre uno y otro.
5. Un `plan` quiere destruir y recrear la VNet tras mover el código a un módulo. Escribe el bloque que lo evita.
6. Define qué identidades tienen qué roles sobre qué plano (control y datos) para dev y prod.

## Frases para recordar
- **El estado es la memoria de Terraform y es un secreto.**
- **Remoto, privado, sin claves, versionado, con borrado suave y bloqueado contra borrado.**
- **Un estado por componente y entorno: pequeños, rápidos y con poco radio de daño.**
- **`moved`, `import` y `removed` en el código; la cirugía manual, el último recurso.**
- **`force-unlock` solo después de confirmar que nadie aplica.**
