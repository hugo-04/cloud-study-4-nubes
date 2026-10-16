# NotebookLM · Azure · Key Vault

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Key Vault, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la caja fuerte con registro de visitas; secretos vs claves vs certificados; Standard, Premium y Managed HSM.
2. Cómo funciona por dentro: plano de control vs plano de datos, autenticación con token, RBAC vs access policies y los roles de datos. Dibuja el flujo de una lectura.
3. Las piezas internas: versiones, atributos, soft delete, purge protection, logs de auditoría y eventos.
4. Claves: encrypt, wrapKey, sign; cifrado de sobre paso a paso; rotación de claves y por qué guardar la versión.
5. Certificados: el trío certificado-clave-secreto, emisión y renovación.
6. Red: firewall, Private Endpoint, zona privatelink y servicios de confianza.
7. Las cuatro formas de leer un secreto (SDK, referencia de App Service, Container Apps, CSI en AKS) y cuándo usar cada una.
8. Rotación: eventos, doble credencial y caché.
9. Los 8 casos reales como historias, con su lección.
10. Código Java: SecretClient, caché con TTL, Spring Boot (imperativo y WebFlux), Quarkus (CDI, CredentialsProvider y Mutiny), rotación de contraseña con pool, envelope encryption y certificados como KeyStore.
11. Qué hacer, qué NO hacer, límites y la tabla de troubleshooting con la secuencia Identidad, Permiso, Red, DNS y Servicio.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
