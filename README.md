# FLY DBZ · 1.0

Script independiente de Reyzn X: [`FLY-SSJ3.lua`](FLY-SSJ3.lua).

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/FLY-SSJ3/main/FLY-SSJ3.lua"))()
```

## Uso

- El panel empieza en **OFF** y con velocidad **5**. El interruptor activa el vuelo, su animación y No Fall Damage en el juego compatible. OFF apaga las tres funciones.
- **SPEED:** toca el número para escribir la velocidad y confirma con Enter o sal del campo. Los botones **− / +** y la rueda del ratón sobre esa fila ajustan de **5 en 5**. El intervalo es **5–5000**; las entradas numéricas se redondean a enteros y se limitan a ese intervalo. Texto vacío, inválido o infinito conserva el último valor.
- La velocidad se puede cambiar **durante el vuelo**, sin apagarlo ni recrear sus controles o animación. El valor elegido se conserva después de morir, aunque las funciones quedan apagadas.
- **Android:** joystick normal. **PC:** W, A, S, D. Dirige la cámara hacia arriba o abajo y avanza para cambiar de altura. Al soltar el movimiento, frena suavemente y queda flotando. Escribir en un campo detiene el desplazamiento sin desactivar el vuelo.
- Arrastra el título **FLY DBZ** para mover el panel. La **×** apaga las funciones y elimina inmediatamente el GUI y los recursos de esta ejecución.

## Muerte y reinicio

Al morir, reiniciar o cambiar de personaje, el interruptor vuelve a **OFF**. Se retiran los controles físicos, se detienen y destruyen las pistas de animación, se cancela cualquier carga anterior y se desactiva No Fall Damage. Si había un pulso pendiente de velocidad, se restaura sin sobrescribir un cambio externo.

Reaparecer **no reactiva nada automáticamente**. Es necesario pulsar ON de nuevo con el personaje vivo y disponible. Pulsar mientras el personaje está muerto o incompleto no deja una activación pendiente. Reemplazar el Humanoid o la raíz también obliga a activar manualmente. Una suspensión temporal por asiento o anclaje, dentro del mismo personaje vivo, mantiene la solicitud de vuelo y reanuda al liberarse.

No Fall Damage conserva el filtro de Natural Disaster Survival (`PlaceId = 189707`). Solo actúa durante una sesión de vuelo activa en ese juego. La técnica local de velocidad no garantiza protección frente a todos los sistemas de daño calculados en servidor.

## Interfaz

Panel compacto de 240 × 156, carbón y gris, texto claro y controles táctiles separados. El número de velocidad tiene más espacio y los botones de incremento/decremento miden 44 × 44. El botón del límite alcanzado se muestra atenuado. Se mantienen el arrastre y el interruptor ON/OFF.

No contiene fuego, aura, partículas, estelas, luces, destellos, reflejos en movimiento ni aviso gráfico. Solo quedan el GUI, el controlador de vuelo y las animaciones del personaje. Las transiciones del interruptor son ajustes simples del propio control.

## Animaciones y visibilidad

Paquete solicitado: [SSJ3 Goku DBZ Animation Pack](https://www.roblox.com/bundles/146661355470855/SSJ3-Goku-DBZ-Animation-Pack), de AvatarVerse. Los IDs y la procedencia están registrados en [`docs/animation-pack.json`](docs/animation-pack.json).

Los clips Idle, Run, Climb y Fall se resuelven y cargan únicamente al activar ON, sobre el **Animator ya existente** del personaje. Los objetos importados se inspeccionan sin introducirlos en el mundo y luego se destruyen; no se ejecuta código importado. Las pistas de una activación anterior nunca se reproducen después de apagar o cambiar de personaje.

**El paquete requiere R15 y permiso de Roblox para cargar los assets.** La resolución mediante `game:GetObjects` requiere un contexto autorizado y no está disponible en un LocalScript estándar. Si la resolución o los permisos fallan, el vuelo continúa disponible y se informa en consola. No se sustituye el personaje ni se crea un Animator local. En R6 se conserva el vuelo sin aplicar el paquete R15.

Según la [documentación de Animator](https://create.roblox.com/docs/reference/engine/classes/Animator), las animaciones del cliente propietario pueden replicarse cuando su Animator fue creado en el servidor. El script utiliza ese Animator; no garantiza que otro juego permita todos los assets.

## Verificación

```bash
python tests/run.py /ruta/a/luau
```

Compilación Luau y **26 pruebas de comportamiento**: inicio apagado, ausencia de efectos/aviso, protección vinculada a ON, restauración de velocidad, filtros del juego, teclado/joystick, pérdida de foco, animaciones y permisos, muerte/reset, piezas y Animator tardíos o reemplazados, cancelación de cargas anteriores, reejecución, arrastre, cierre, límites de velocidad, pasos de 5, cambios durante el vuelo y conservación de ajustes tras morir.

Las pruebas verifican lógica y limpieza de recursos; **no ejecutan la física, el renderizado ni la replicación de Roblox**. La comprobación en la experiencia de destino sigue siendo manual. Esta modificación no cambia el repositorio Reyzn X.
