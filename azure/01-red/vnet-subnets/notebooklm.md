# NotebookLM · Azure · VNet y Subnets

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Virtual Network y Subnets, para un ingeniero Java que trabaja con microservicios.
No compares con otras nubes.

Estructura obligatoria:
1. Qué es una VNet, con la analogía del edificio, los pisos y las puertas.
2. Cómo funciona por dentro: address space, subnets, enrutamiento automático, DNS de la plataforma, las 5 IP reservadas. Muestra el diagrama de una VNet con sus subnets.
3. Cálculo de CIDR paso a paso con ejemplos (/16, /24, /27, /28) y IP útiles reales.
4. Subnets con nombre obligatorio y subnets delegadas: qué servicios las exigen y por qué.
5. Cómo se crea: portal, CLI y Terraform, mostrando el código de las fuentes.
6. IAM: roles necesarios y qué significa el permiso de unirse a una subnet.
7. Los 4 casos reales (base expuesta, rangos solapados, subnet llena, VM sin salida) contados como historias, con problema, solución y lección.
8. Cómo afecta a Java: timeouts, caché de DNS de la JVM, idle timeout y pools de conexiones, en Spring Boot y Quarkus, imperativo y reactivo.
9. Qué hacer, qué NO hacer, y la tabla de troubleshooting.

Reglas: no omitas ninguna tabla, comando ni caso. Define cada término la primera vez. Cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
