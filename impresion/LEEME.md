# Comandas impresas en cocina · Pinchos la 17

## Cómo funciona
1. En **Ajustes → Forma de trabajo de la cocina** se elige **«Comandas impresas por zona»**.
2. Cuando la caja confirma un pedido (o lo crea ella misma), el sistema arma **una comanda por cada zona** que
   participa: el **Asador** recibe los pinchos y asados, y la **Cocina** recibe el mute y los adicionales (arroz, papa,
   yuca, guacamole). Las bebidas no salen en comanda.
3. Las comandas quedan **en cola** en el servidor. Un equipo del local las recoge cada 3 segundos y las imprime en la
   impresora de su zona. Si la impresora está apagada o sin papel, la comanda **no se pierde**: espera y sale cuando vuelve,
   y la caja ve un aviso rojo si pasan más de 40 segundos.

### Qué trae cada comanda (letra grande)
- La **zona** en blanco sobre negro, el **número del pedido** enorme y **MESA / DOMICILIO / MOSTRADOR**.
- Cada producto como **«2 x PINCHO MIXTO»** en letra doble, y debajo **cada adicional en su propio renglón**
  («+ Arroz», «+ Chorizo de cerdo»). Si un adicional lo prepara otra zona, dice «(lo hace Cocina)».
- **SIN CEBOLLA** en blanco sobre negro, para que no se pase por alto, y la **NOTA** del cliente.
- En la comanda de Cocina, el adicional dice **para qué plato es** («3 x ARROZ · Para: Pincho de carne con chunchullo»).
- Al final: cuántos productos lleva y qué otra zona está preparando el mismo pedido.

## Dos formas de imprimir (elige una)

| | Forma 1 · Desde el navegador | Forma 2 · Con el agente (recomendada) |
| --- | --- | --- |
| Impresora por **cable USB** | Sí (con su driver de Windows) | Sí |
| Impresora por **WiFi o cable de red** | Sí (instalada en Windows) | Sí, directo por su IP |
| Qué se instala | Nada (solo Chrome) | Node.js, una vez |
| Equipos necesarios | Un equipo con Chrome abierto **por cada impresora** | **Un solo** computador para todas las impresoras |
| Calidad del papel | Buena (depende del driver) | La mejor: letra nativa de la impresora, corte y pitido |

---

## Forma 2 · Agente de impresión (cable USB y WiFi en un solo programa)

### Paso 1 · Preparar el sistema
1. En el panel → **Usuarios**, crea un usuario rol **cocina** solo para esto, por ejemplo `impresora`,
   **sin** verificación en dos pasos.
2. En **Ajustes**, pon la cocina en **«Comandas impresas por zona»**.

### Paso 2 · Instalar Node.js en el computador del local (una vez)
- Descarga **Node.js LTS** de nodejs.org e instálalo con «Siguiente, Siguiente».
- Copia la carpeta del proyecto (o solo la carpeta `impresion`) a ese computador, por ejemplo en `C:\pinchos17`.

### Paso 3 · Conectar cada impresora

**A) Impresora WiFi o con cable de red**
1. Conéctala a la **misma red WiFi** que el computador (la mayoría trae una app o un botón WPS; el manual lo explica).
   En la mayoría de modelos, al encenderla con el botón FEED presionado imprime una hoja con su **IP** (ej. `192.168.1.50`).
2. Si no sabes la IP, en el computador abre una terminal en la carpeta y ejecuta:
   `node impresion/agente.mjs --buscar` → muestra las impresoras que encuentra en la red.
3. En el router, reserva esa IP para la impresora (**IP fija**). Si cambia, deja de imprimir.
4. En `config.json`: `"Asador": { "tipo": "red", "host": "192.168.1.50", "port": 9100 }`

**B) Impresora con cable USB (conectada a ESTE computador)**
1. Instala el driver de la impresora (viene en un CD o en la página de la marca: Xprinter, 3nStar, Epson…).
2. **Compártela** en Windows: Configuración → Impresoras → la impresora → Propiedades de impresora →
   pestaña **Compartir** → marca «Compartir esta impresora» y ponle un nombre corto **sin espacios**, ej. `COCINA`.
3. Para ver los nombres: `node impresion/agente.mjs --impresoras` (columna ShareName).
4. En `config.json`: `"Cocina": { "tipo": "usb", "nombre": "COCINA" }`
   - En Linux puede ser el dispositivo: `"nombre": "/dev/usb/lp0"`. En Mac: el nombre de la impresora en CUPS.

> Se pueden mezclar: una impresora WiFi para el Asador y una USB para la Cocina. Con **una sola impresora** para todo,
> usa el nombre `"todas"`: `"todas": { "tipo": "usb", "nombre": "COCINA" }`.

### Paso 4 · Configurar
1. En la carpeta `impresion`, copia `config.ejemplo.json` como **`config.json`**.
2. Completa: la dirección del sitio (`servidor`), el usuario y la clave del paso 1, y una línea por impresora.
   El nombre de cada impresora debe ser **igual al de la zona** en el sistema (`Asador`, `Cocina`).
3. Papel: `"papel": 80` (el más común) o `"papel": 58` (rollo angosto).
4. Tildes: déjalo en `false` (imprime sin tildes, funciona en todas). Si quieres tildes, ponlo en `true` y haz la
   prueba: si en vez de «ÁÉÍÓÚ Ñ» salen símbolos raros, vuelve a `false`.

### Paso 5 · Probar
`node impresion/agente.mjs --prueba` → cada impresora saca una comanda de prueba (pedido #17, mesa 4).
Si una falla, el mensaje dice por qué (apagada, IP equivocada, no está compartida…).

### Paso 6 · Dejarlo funcionando
- Doble clic en **`impresion\iniciar-agente.bat`**. Se abre una ventana negra «Comandas Pinchos la 17 – NO CERRAR».
  Si se cae internet o la impresora, reintenta solo.
- Para que arranque al prender el computador: tecla Windows + R → escribe `shell:startup` → Enter →
  copia ahí un **acceso directo** a `iniciar-agente.bat`.
- El computador **no debe suspenderse** (Configuración → Energía → Suspender: Nunca).

---

## Forma 1 · Desde el navegador (sin instalar nada)
Sirve con impresora USB o WiFi, siempre que esté **instalada en Windows** con su driver.
1. Deja la impresora térmica como **impresora predeterminada** del equipo.
2. Para que imprima sin preguntar, abre Chrome con `--kiosk-printing`: clic derecho al acceso directo de Chrome →
   Propiedades → al final de «Destino» agrega un espacio y `--kiosk-printing`. Cierra todas las ventanas de Chrome
   y ábrelo con ese acceso directo.
3. Entra con un usuario de **cocina** → **Comandas** → elige la zona (o «TODAS» si hay una sola impresora) →
   elige el papel (80 o 58 mm) → enciende **«Imprimir automáticamente»**.
4. Pulsa **«Imprimir prueba»** y deja esa página abierta.
5. En las preferencias de la impresora en Windows pon el tamaño de papel del rollo (80 o 58 mm) y márgenes en cero.

**No uses las dos formas a la vez para la misma zona**: cada comanda sale una sola vez en el primer equipo que la
recoge.

## Si algo falla
| Problema | Solución |
| --- | --- |
| Aviso rojo en caja «comanda sin imprimir» | Revisa papel, que esté encendida y (WiFi) conectada a la red. La comanda sale sola al volver. |
| «la impresora no responde» | Impresora WiFi apagada, en otra red o cambió de IP. Usa `--buscar` y fija la IP en el router. |
| «no se pudo enviar a la impresora USB» | No está compartida o el nombre no coincide. Revisa con `--impresoras`. |
| Salen símbolos raros | Pon `"tildes": false` en config.json. |
| No corta el papel | La impresora no tiene cortador automático: se corta a mano en la línea de puntos. |
| Necesito otra copia | En **Comandas** («Imprimir aquí» o «Mandar copia a la zona») o en Caja («Reimprimir en cocina»). |

`config.json` tiene una clave: **no lo subas a GitHub** (ya está en `.gitignore`).
