# Azure · Caso integrado · Clickstream · Repaso

## Preguntas
1. ¿Qué es una partición y por qué importa?
   - *Un carril ordenado; el paralelismo de lectura máximo es el número de particiones.*
2. ¿Qué es una clave caliente y cómo se evita?
   - *Una clave que concentra el tráfico en una partición; se evita con claves de alta cardinalidad (sesión o cubeta).*
3. ¿Por qué usar cubetas en vez de una clave por sesión?
   - *Un lote admite una sola clave; con 64 cubetas hay pocos lotes y se conserva el orden por sesión.*
4. ¿Cómo se dimensiona la capacidad?
   - *Pico × margen → MB/s y eventos/s de entrada, salida según los lectores, y unidades por la regla del nivel.*
5. ¿Para qué sirve el auto-inflate y qué riesgo tiene?
   - *Crece solo ante los picos; sin tope, el costo también crece.*
6. ¿Qué es un grupo de consumidores?
   - *Una vista independiente del flujo con sus propios puntos de control.*
7. ¿Qué pasa si dos aplicaciones comparten grupo?
   - *Se reparten las particiones y cada una ve solo una parte.*
8. ¿Qué hace Capture y por qué importa?
   - *Copia el flujo al lago en Avro; es la fuente de verdad para recalcular.*
9. ¿Por qué el agregador en línea es aproximado?
   - *Su estado está en memoria; tras un reinicio se reconstruye desde el último punto de control.*
10. ¿Qué es un evento tardío y qué se hace con él?
    - *Llega cuando su ventana ya cerró; se descarta del camino en línea y el lote lo corrige.*
11. ¿Por qué UPSERT y no sumar?
    - *Los reintentos y reprocesos no deben contar dos veces.*
12. ¿Cómo se protege la privacidad en el flujo?
    - *Seudónimos HMAC desde el colector, con la sal en Key Vault.*

## Ejercicios
1. Calcula unidades y particiones para 1 200 eventos/s de 1 KB con 2 lectores y margen 2.
2. Dibuja qué pasa con 8 particiones si hay 12 instancias lectoras.
3. Define cuántas cubetas usarías para 20 particiones y por qué.
4. Escribe el UPSERT del resumen por minuto.
5. Diseña la alerta para detectar que el agregador va 5 minutos atrasado.

## Autoevaluación
- [ ] Explico la clave de partición con un ejemplo bueno y uno malo.
- [ ] Sé calcular la capacidad con el pico.
- [ ] Distingo lo «en vivo» de lo «oficial».
- [ ] Sé qué mirar cuando una partición se atrasa.
