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
- El aviso centrado **“For better quality, use Roblox's high graphics settings.”** permanece visible hasta tocar **OK** o cerrar el script. No tiene temporizador y no se elimina al activar el vuelo, morir o reaparecer. No cambia la configuración gráfica de Roblox.
- Si mueres con el vuelo en ON, la preferencia se conserva y el vuelo vuelve al reaparecer. Si estaba OFF, sigue OFF.
- **No Fall Damage** queda armado automáticamente, sin botón, en Natural Disaster Survival (`PlaceId = 189707`), igual que el script proporcionado. Continúa con el vuelo apagado y tras reaparecer; se retira al cerrar el panel. La manipulación local de velocidad no constituye una protección universal contra daño calculado por el servidor.

## Aura

Aura local amarilla y semidorada inspirada en la referencia del meteorito: envoltura ancha de fuego con centro amarillo claro, capas exteriores doradas/naranjas y chispas. Las líneas finas sin textura se sustituyen por ocho pares de capas curvas texturizadas, con variaciones suaves de anchura y forma. Una estela nativa corta conserva el recorrido reciente del personaje.

Al moverse, las llamas y las puntas se inclinan en dirección contraria al desplazamiento: delante, atrás, ambos lados, ascenso y descenso. La orientación usa la velocidad suavizada del controlador para que el pulso de No Fall Damage no provoque temblores. Los giros se interpolan, incluso al invertir completamente la dirección. En reposo, el fuego vuelve a subir desde los pies. Se revela durante 0.9 s y se desvanece durante 0.6 s al apagar el vuelo, conservando su orientación durante la salida. No incluye audio, vídeo ni efectos globales de iluminación.

Los 22 emisores, 16 `Beam` y un `Trail` se reutilizan por personaje. Las vidas y tasas de emisión mantienen un presupuesto teórico inferior a 240 partículas continuas al completar el encendido, además de la ráfaga inicial. La estela dura 0.28 s y tiene una longitud máxima de 16 studs; la geometría visual permanece acotada aunque se introduzcan velocidades muy grandes. Roblox simula las partículas, la estela y el desplazamiento de las texturas; la intensidad y la geometría de las capas se actualizan a 30 Hz. No se crean instancias ni secuencias nuevas cada fotograma. Los controles físicos se actualizan antes de la simulación mediante `LinearVelocity` y `AlignOrientation`.

El panel conserva sus medidas y controles, con carbón metálico, reflejos dorados suaves y una pequeña aura exterior de fuego. Sus 18 imágenes reutilizadas quedan detrás del panel para no tapar el texto ni capturar pulsaciones; acompañan el arrastre y el desvanecimiento. La iluminación aumenta al activar el vuelo y sigue funcionando aunque el personaje esté reapareciendo.

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

Compilación con Luau y 32 pruebas deterministas: estado inicial, movimiento de teclado y joystick, cámara inclinada, pausa al escribir o perder foco, respawn, piezas tardías/reemplazadas, permisos de animación, aparición y retirada del aura, seis direcciones de movimiento, inversión suave, personaje rotado, geometría acotada a velocidades extremas, objetos reutilizados, fuego del panel durante arrastre y ausencia de personaje, aviso persistente y cierre manual, velocidad editable, pasos de 2, rueda, valores grandes/decimales/inválidos, reejecución, cierre y restauración de velocidad. El arnés comprueba la lógica y los recursos; **no ejecuta física, renderiza partículas ni simula la replicación de Roblox**.

Pendiente de comprobación en Roblox: aspecto final del fuego en Android, vuelo en la experiencia de destino, efectividad del No Fall Damage y visibilidad del paquete desde un segundo cliente R15 autorizado. El código no modifica los scripts del repositorio Reyzn X.
