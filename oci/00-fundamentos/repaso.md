# Oracle OCI · 00 Fundamentos · Repaso

## Preguntas
1. ¿Qué diferencia hay entre tenancy y compartimento?
2. ¿Hasta cuántos niveles se anidan los compartimentos?
3. ¿Qué recursos son globales al tenancy y cuáles regionales?
4. ¿Qué es la región *home* y por qué importa?
5. ¿Qué diferencia hay entre dominio de disponibilidad y dominio de fallas?
6. ¿Qué proveedor de autenticación usa el SDK de Java en una VM de OCI? ¿Y en OCI Functions?
7. ¿Qué es un OCID?
8. ¿Para qué sirven las etiquetas definidas frente a las libres?
9. ¿Cuál es la diferencia entre cuota y límite de servicio?
10. ¿Qué haces el primer día para controlar el gasto?

## Respuestas
1. El tenancy es la cuenta raíz; el compartimento es una carpeta lógica dentro de él para aislar recursos y permisos.
2. Hasta 6 niveles (verifica).
3. Globales: compartimentos, políticas, grupos, dominios de identidad, etiquetas. Regionales: VCN, buckets, OKE, bases de datos, colas.
4. Es la región donde se crean los recursos de identidad; no se cambia después.
5. El AD es un centro de datos de la región; el FD es un grupo de hardware aislado dentro de un AD.
6. Instance principal en una VM (`InstancePrincipalsAuthenticationDetailsProvider`); resource principal en Functions.
7. El identificador único de cualquier recurso.
8. Las definidas viven en un namespace con valores controlados y permiten reglas de costos y políticas; las libres no tienen esquema.
9. La cuota la fijas tú por compartimento; el límite lo impone Oracle por tenancy/región y se amplía por solicitud.
10. Presupuesto con alerta por compartimento y etiquetas de costo.

## Ejercicios
1. Dibuja la jerarquía de compartimentos para una empresa con 3 equipos y 3 entornos.
2. Elige el proveedor de autenticación para: laptop, pod en OKE, función, VM.
3. Define tres etiquetas definidas de costo y dónde se aplican por defecto.
