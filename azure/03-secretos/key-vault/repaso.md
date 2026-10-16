# Azure · Key Vault · Repaso

## Preguntas de repaso
1. ¿Qué diferencia hay entre un secreto, una clave y un certificado?
   - *El secreto se lee; la clave se usa sin leerla (cifrar, firmar); el certificado es una clave + metadatos + ciclo de vida.*
2. ¿Por qué un Contributor sobre el vault no puede leer secretos?
   - *Contributor es plano de control (administra el contenedor); leer es plano de datos y exige un rol como Key Vault Secrets User.*
3. ¿Por qué RBAC es preferible a las access policies?
   - *Permisos por secreto, un solo modelo de gestión, auditoría y PIM, condiciones.*
4. ¿Qué protegen *soft delete* y *purge protection*?
   - *Soft delete: lo borrado se puede recuperar. Purge protection: nadie puede vaciar la papelera antes de tiempo.*
5. ¿Qué es el cifrado de sobre y por qué se usa?
   - *Clave de datos local que cifra el archivo + clave maestra del vault que la envuelve; el vault no ve datos grandes y la clave maestra no sale.*
6. ¿Cómo evitas una caída al rotar una contraseña de base de datos?
   - *Doble credencial + nueva versión del secreto + app que relee con caché corta.*
7. ¿Qué haces ante un `429`?
   - *Cachear el secreto; un vault por aplicación y entorno; no reintentar más.*
8. ¿Cómo se descarga un certificado con su clave privada?
   - *Pidiendo el secreto con el mismo nombre (PKCS12 en Base64).*
9. ¿Qué cuatro cosas deben cumplirse para que una app lea un secreto por red privada?
   - *Identidad, rol de datos, ruta/Private Endpoint y DNS privado.*
10. ¿Las variables de entorno creadas desde el CSI se actualizan al rotar?
    - *No hasta reiniciar el pod; los archivos montados sí con rotación activada.*
11. ¿Qué pasa si borras o deshabilitas una CMK?
    - *El servicio pierde acceso a los datos cifrados; por eso purge protection es obligatoria.*
12. ¿Por qué guardar el identificador de versión de la clave junto al dato cifrado?
    - *Tras rotar, hay que desenvolver con la versión que envolvió.*

## Entrevista
- Diseña cómo un pod en AKS obtiene la contraseña de la base de datos sin que esté en el código ni en una variable estática.
- Un secreto expuesto en Git: ¿cuáles son tus primeros 5 pasos y en qué orden?
- ¿Cómo diseñas la rotación mensual sin downtime de la clave de una API de terceros?
- Un servicio recibe 429 de Key Vault bajo carga: ¿qué cambias en el código y en la arquitectura?
- ¿Cuándo usarías Managed HSM en vez de Key Vault Standard?
- ¿Qué pones en Key Vault y qué en App Configuration?

## Ejercicio práctico
1. Crea un vault con RBAC, soft delete y purge protection (`ejemplos/cli/keyvault.sh`).
2. Guarda un secreto con expiración y lee su versión desde Java (`ejemplos/java/KeyVaultCheck.java`).
3. Cierra el acceso público, agrega Private Endpoint y comprueba el `nslookup`.
4. Provoca un 403 quitando el rol y reconoce el mensaje en Log Analytics.
