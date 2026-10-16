# Azure · Managed Identity · Repaso

## Preguntas de repaso
1. ¿Qué problema resuelve una managed identity?
   - *Que la aplicación acceda a servicios sin guardar secretos.*
2. ¿Cuándo eliges user-assigned y cuándo system-assigned?
   - *User-assigned para varios recursos, IaC con roles antes del recurso o credenciales federadas; system-assigned para un solo recurso simple.*
3. ¿Dónde usas `client_id` y dónde `principal ID`?
   - *`client_id` en el código para elegir identidad; `principal ID` para asignar roles.*
4. ¿Por qué `DefaultAzureCredential` funciona en local y en Azure?
   - *Prueba varias fuentes: en Azure la managed identity; en local `az login`.*
5. ¿Una managed identity funciona en mi laptop?
   - *No; en local usa `az login` o credenciales federadas.*
6. ¿Qué haces con una base de datos que pide contraseña?
   - *Crear un usuario ligado a la identidad y usar token de Entra ID.*
7. ¿Por qué reutilizar el cliente del SDK?
   - *Cachea el token y evita límites de peticiones.*

## Entrevista
- Diseña cómo accede una App Service a Storage, Key Vault y Azure SQL sin secretos.
- Un recurso tiene dos identidades y recibes 403: ¿qué haces?
- ¿Por qué es mejor una identidad por servicio que una compartida?
