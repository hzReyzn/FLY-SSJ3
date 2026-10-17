# FLY DBZ · 1.0

Script independiente de Reyzn X: [`FLY-SSJ3.lua`](FLY-SSJ3.lua).

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/FLY-SSJ3/main/FLY-SSJ3.lua"))()
```

## Uso

- El panel compacto empieza en **OFF**. Toca la fila para activar o desactivar el vuelo.
- **SPEED:** toca el número para escribir la velocidad y confirma con Enter o sal del campo. Los botones **− / +** y la rueda del ratón sobre esa fila ajustan de **2 en 2**. El cambio se aplica durante el vuelo y se conserva al reaparecer. Empieza en **58**; **0** mantiene la suspensión. No hay máximo configurado: se aceptan valores no negativos y finitos que Roblox pueda representar; entradas vacías, inválidas o infinitas restauran el último valor.
- **Android:** joystick normal. **PC:** W, A, S, D. Dirige la cámara hacia arriba o abajo y avanza para cambiar de altura. Al soltar el movimiento, frena suavemente y queda flotando.
- Arrastra el título **FLY DBZ** para mover el panel. La **×** apaga el vuelo y retira todos los recursos de esta instancia del script.
- Si mueres con el vuelo en ON, la preferencia se conserva y el vuelo vuelve al reaparecer. Si estaba OFF, sigue OFF.
- **No Fall Damage** queda armado automáticamente, sin botón, en Natural Disaster Survival (`PlaceId = 189707`), igual que el script proporcionado. Continúa con el vuelo apagado y tras reaparecer; se retira al cerrar el panel. La manipulación local de velocidad no constituye una protección universal contra daño calculado por el servidor.

## Aura

Aura local amarilla y semidorada, inspirada en la referencia SSJ3: llamas más grandes y saturadas, ocho columnas curvas de energía con núcleo fino, textura ascendente, puntas de distintas alturas sobre la cabeza y chispas. Las capas se ensanchan alrededor del torso y oscilan con fases diferentes. La mezcla de color conserva contraste bajo el cielo claro sin convertir todo el cuerpo en un bloque blanco. Se revela desde los pies durante 0.9 s y se desvanece durante 0.6 s al apagar el vuelo, sin colapsar las puntas durante el desvanecimiento. No incluye audio, vídeo ni efectos globales de iluminación.

Los 22 emisores y los 16 `Beam` se reutilizan por personaje. Las vidas y tasas de emisión mantienen un presupuesto teórico inferior a 240 partículas activas al completar el encendido. Roblox simula las partículas y el desplazamiento de las texturas; la intensidad y la geometría de las capas se actualizan a 30 Hz. No se crean instancias ni secuencias nuevas cada fotograma. Los controles físicos se actualizan antes de la simulación mediante `LinearVelocity` y `AlignOrientation`.

## Animaciones y visibilidad

Paquete solicitado: [SSJ3 Goku DBZ Animation Pack](https://www.roblox.com/bundles/146661355470855/SSJ3-Goku-DBZ-Animation-Pack), de AvatarVerse. Los IDs y la procedencia están registrados en [`docs/animation-pack.json`](docs/animation-pack.json).

El script obtiene los clips internos de los paquetes Idle, Run, Climb y Fall y los reproduce con transiciones sobre el **Animator ya existente** del personaje. Los objetos importados se inspeccionan sin introducirlos en el mundo y luego se destruyen; no se ejecuta código importado.

**La animación requiere R15 y permiso de Roblox para cargar los assets.** La consulta pública de los contenidos internos respondió HTTP 401 durante el desarrollo; esos IDs no se inventaron ni se confundieron con los IDs del catálogo. La resolución se intenta dentro del cliente mediante `game:GetObjects`, que requiere un contexto autorizado y no está disponible en un LocalScript estándar. Si la resolución o los permisos fallan, el vuelo y el aura siguen funcionando y se informa en la consola. No se sustituye el personaje ni se crea un Animator local para aparentar replicación.

Según la [documentación de Animator](https://create.roblox.com/docs/reference/engine/classes/Animator), las animaciones del cliente propietario pueden replicarse cuando su Animator fue creado en el servidor. Este script utiliza esa ruta; no puede garantizar que otro juego permita todos los assets. En R6 no se aplica este paquete R15.

**El aura es visible en el cliente que ejecuta el script.** Para mostrar emisores a todos los jugadores se necesita implementar el efecto en el servidor de una experiencia que controles; un script local en un juego ajeno no lo puede garantizar.

## Verificación

```bash
python tests/run.py /ruta/a/luau
```

Compilación con Luau y 26 pruebas deterministas: estado inicial, movimiento de teclado y joystick, cámara inclinada, pausa al escribir o perder foco, respawn, piezas tardías/reemplazadas, permisos de animación, aparición y retirada del aura, geometría ascendente y movimiento de las capas, objetos reutilizados, velocidad editable, pasos de 2, rueda, valores grandes/decimales/inválidos, reejecución, cierre y restauración de velocidad. El arnés comprueba la lógica y los recursos; **no ejecuta física, renderiza partículas ni simula la replicación de Roblox**.

Pendiente de comprobación en Roblox: aspecto final del fuego en Android, vuelo en la experiencia de destino, efectividad del No Fall Damage y visibilidad del paquete desde un segundo cliente R15 autorizado. El código no modifica los scripts del repositorio Reyzn X.
