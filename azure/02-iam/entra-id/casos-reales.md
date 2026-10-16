# Azure · Entra ID · Casos reales

## Caso 1 · "Cualquier token servía"
- **Problema:** la API de pedidos aceptaba tokens de cualquier aplicación del tenant. Una app de marketing, sin relación, podía llamarla.
- **Causa:** la API validaba firma y emisor, pero **no la audiencia (`aud`)**.
- **Solución:** exigir `aud = api://<id-de-la-api>` y los permisos (`roles`/`scp`) necesarios.
- **Lección:** un token válido no es un token **para tu API**.

## Caso 2 · El secreto que venció un viernes
- **Problema:** el servicio de facturación dejó de autenticarse a las 18:00 del viernes.
- **Causa:** el secreto de su app registration venció (dos años antes lo creó alguien que ya no está).
- **Solución corta:** nuevo secreto. **Solución real:** reemplazar el secreto por una identidad administrada y alertas de vencimiento.
- **Lección:** los secretos vencen; las identidades administradas no tienen secreto.

## Caso 3 · Servicio a servicio con app roles
- **Problema:** el servicio de inventario debía llamar al de catálogo sin usuario, y solo para leer.
- **Solución:** `catalogo-api` define el app role `Catalogo.Read`; el servicio de inventario recibe ese rol y pide tokens con client credentials. La API valida `roles` contiene `Catalogo.Read`.
- **Resultado:** permisos mínimos, sin usuarios técnicos.
- **Lección:** para máquina a máquina usa app roles.

## Caso 4 · El token enorme
- **Problema:** un usuario administrador recibía error 431 (cabeceras demasiado grandes) al llamar a la API.
- **Causa:** pertenecía a cientos de grupos y el token los listaba todos.
- **Solución:** usar permisos por **app roles** o consultar los grupos a Microsoft Graph, en vez de depender de la claim `groups`.
- **Lección:** no metas todo en el token.

## Caso 5 · Contratistas y acceso con fecha de fin
- **Problema:** una consultora externa necesitaba acceso por dos semanas.
- **Solución:** cuentas invitadas en un grupo con revisión de acceso programada y fecha de expiración.
- **Lección:** todo acceso externo tiene vencimiento.
