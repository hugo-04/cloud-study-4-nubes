# AWS · 00 Fundamentos · Repaso

## Preguntas de repaso
1. ¿Cuál es la jerarquía de AWS, de arriba hacia abajo?
   - *Organización → Raíz → OU → Cuenta → Recursos (regionales).*
2. ¿Por qué la cuenta es la frontera de aislamiento?
   - *Los permisos entre cuentas están cerrados por defecto; se abren con roles.*
3. ¿Qué hace una SCP y qué no hace?
   - *Pone un techo de lo permitido en cuentas/OU; no concede permisos por sí sola.*
4. ¿Qué diferencia hay entre HA y DR?
   - *HA = varias AZ de una región; DR = otra región.*
5. ¿Qué es un ARN?
   - *El nombre único de un recurso: `arn:partición:servicio:región:cuenta:recurso`.*
6. ¿Por qué usar ID de AZ y no el nombre?
   - *El nombre se baraja por cuenta; el ID identifica el mismo edificio.*
7. ¿Qué comando dice en qué cuenta y con qué identidad estás?
   - *`aws sts get-caller-identity`.*
8. ¿En qué orden busca credenciales el SDK de Java?
   - *Propiedades, variables de entorno, identidad web (IRSA), perfil/SSO, contenedor (ECS/Pod Identity), instancia (EC2).*
9. ¿Por qué no deben usarse claves de acceso permanentes?
   - *Se filtran y no caducan; los roles entregan credenciales temporales.*
10. Menciona tres costos que sorprenden.
    - *NAT Gateway, transferencia de datos entre AZ/regiones o a internet, IPv4 pública y recursos olvidados.*
11. ¿Para qué sirven las etiquetas y qué hay que hacer para repartir costos con ellas?
    - *Organizar y repartir costos; hay que activarlas como etiquetas de asignación de costos.*
12. ¿Qué haces el primer día con la cuenta raíz?
    - *MFA, no usarla y no crearle claves.*

## Ejercicios
1. Dibuja la jerarquía de tu empresa (OU y cuentas) y justifica cada cuenta.
2. Crea un perfil SSO y ejecuta `sts get-caller-identity`.
3. Crea un presupuesto de 20 USD con alerta del 80 %.
4. Lista las regiones habilitadas y elige una justificando latencia, precio y servicios.
5. Etiqueta un bucket con `env`, `owner`, `app`, `costcenter`.

## Autoevaluación
- [ ] Explico cuenta, OU y SCP en 30 segundos.
- [ ] Sé verificar dónde estoy parado antes de crear nada.
- [ ] Sé qué costos vigilar.
- [ ] Sé por qué los servicios usan roles y no claves.
