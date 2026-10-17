# AWS · SG, NACL, rutas y NAT · Repaso

## Preguntas
1. ¿Qué significa que un SG tenga estado?
   - *Si se permite la ida, la respuesta se permite sola.*
2. ¿Puedes escribir una regla de denegación en un SG?
   - *No; solo permisos.*
3. ¿Y en una NACL?
   - *Sí, permite y deniega, con reglas numeradas.*
4. ¿Por qué una NACL necesita puertos efímeros?
   - *No tiene estado: la vuelta se declara.*
5. ¿Qué ventaja tiene referenciar SG en lugar de CIDR?
   - *Sigue a las identidades aunque cambien las IP.*
6. ¿Qué ruta gana si hay varias que coinciden?
   - *La de prefijo más largo.*
7. ¿Dónde debe estar el NAT Gateway?
   - *En una subred pública, con Elastic IP.*
8. ¿Cuánto tarda el NAT en cortar una conexión inactiva?
   - *350 s (verifica el valor vigente).*
9. ¿Qué diferencia hay entre «timeout» y «refused»?
   - *Timeout: algo descarta el paquete; refused: llegó y nadie escucha.*
10. ¿Cuándo usar NACL?
    - *Para un bloqueo puntual o una capa extra en datos; no como control principal.*

## Ejercicios
1. Diseña los SG de `alb`, `app` y `datos` y sus reglas por referencia.
2. Escribe la NACL de la subred de datos para el 5432 desde las subredes de app, con retorno.
3. Dibuja las tablas de rutas de pública, app y datos.
4. Audita una cuenta con `auditar-sg.sh` y lista tres hallazgos.

## Autoevaluación
- [ ] Sé el camino completo de un paquete.
- [ ] Diferencio SG y NACL.
- [ ] Sé cuándo falla un NAT y qué medir.
- [ ] Sé por qué referencio SG.
