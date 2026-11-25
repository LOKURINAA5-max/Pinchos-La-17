# Pinchos la 17 — Sistema web de pedidos, caja, cocina, inventario y contabilidad

> Proyecto de la asignatura **Motores de Bases de Datos** · Unidades Tecnológicas de Santander (UTS)
> **Integrantes:** Juan Felipe Méndez Sarmiento · Jorge Eliecer Sánchez Jiménez

## 🔗 Aplicativo en funcionamiento

**https://pinchos17.onrender.com**

| Para probar | Cómo entrar |
|---|---|
| **Cliente** (pedir como si estuviera en el local) | Abrir el enlace. Para simular una mesa: `https://pinchos17.onrender.com/?mesa=5` |
| **Caja, cocina y administrador** | Botón **«Personal»** (arriba a la derecha) → usuario y contraseña. Las credenciales de prueba se entregan **por correo a la docente**, no se publican aquí. |

> ⏱️ El servidor está en el plan gratuito de Render: si nadie lo ha usado en los últimos 15 minutos, **la primera carga tarda unos 50 segundos** mientras se enciende. Después funciona normal.
>
> Los pedidos de clientes solo se aceptan con la **caja abierta** (Caja → *Abrir caja*). Si el menú dice «cerrado», es por eso.

---

## 📋 Descripción

**Pinchos la 17** es un restaurante de pinchos, carnes y bebidas ubicado en la Calle 17 # 25-78 de Bucaramanga. Este sistema reemplaza
la libreta y la calculadora: el cliente pide desde su celular, caja cobra, la cocina ve qué preparar y el dueño controla
inventario, costos y ganancias. Todo funciona en el navegador (celular, tablet o PC); no hay que instalar nada.

El núcleo del proyecto es una **base de datos PostgreSQL de 27 tablas y 45 claves foráneas** con reglas de negocio aplicadas
en la propia base: restricciones `CHECK`, transacciones con bloqueo de filas (`SELECT … FOR UPDATE`), triggers que impiden
modificar facturas y turnos cerrados, y migraciones versionadas que se aplican solas al arrancar.

### Funcionalidades por rol

| Rol | Qué hace |
|---|---|
| **Cliente** (QR en la mesa o domicilio) | Ve la carta con fotos y categorías, quita ingredientes, elige adicionales, pide en mesa o a domicilio (con mapa y ubicación por GPS o dirección) y sigue el estado de su pedido en vivo. Nunca ve costos ni inventario. |
| **Caja** (POS) | Abre y cierra la caja con conteo de billetes, confirma pedidos, cobra en efectivo o Nequi con **cálculo de vueltos**, junta varios pedidos en una sola factura, registra retiros e ingresos e imprime recibos. |
| **Cocina** (por zona: Asador / Cocina) | Ve las tareas de su zona con cronómetro de colores, marca lo preparado y despacha. Las **comandas se imprimen** en impresora térmica por cable USB o WiFi (agente ESC/POS en `impresion/`). |
| **Administrador** | Carta separada en **platos** (se preparan; costo por receta o manual) y **productos de tienda** (gaseosas, cervezas; costo de compra). Inventario de materias primas y productos con **mínimos y máximos** y **pedido a proveedores** automático, compras, conteos físicos, contabilidad (estado de resultados, márgenes por plato, flujo de caja, CSV), usuarios con verificación en dos pasos y auditoría. |

**Reglas importantes que garantiza la base de datos**
- El inventario se descuenta **una sola vez**, cuando cocina empieza a preparar, incluyendo la merma: `cantidad ÷ (1 − merma)`.
- Un pedido tiene 0 o 1 factura; una factura agrupa 1 o más pedidos. Las facturas y los turnos cerrados son **inmutables**.
- Solo puede haber **un turno de caja abierto** a la vez.
- Cuando un insumo o producto baja de su mínimo, el administrador recibe una alerta en tiempo real.

---

## 🛠️ Tecnologías utilizadas

| Capa | Tecnología |
|---|---|
| Base de datos | **PostgreSQL** (en la nube: **Neon**, AWS US-West-2). DDL en `db/schema.sql`, migraciones `db/migracion_*.sql`, DML en `db/dml_pinchos17.sql` |
| Servidor | **Node.js 22** + **Express 5**, driver `pg` (consultas parametrizadas), API REST en JSON |
| Tiempo real | Server-Sent Events (SSE) para avisar a caja, cocina y administrador |
| Interfaz | HTML5, CSS3 y JavaScript sin frameworks; mapas con **Leaflet + OpenStreetMap** |
| Seguridad | `helmet` (CSP), `bcryptjs`, JWT en cookie `httpOnly`, verificación en dos pasos (TOTP), `express-rate-limit` |
| Impresión | Agente Node.js con comandos **ESC/POS** (impresoras térmicas USB o en red, puerto 9100) |
| Despliegue | **GitHub** (código) → **Render** (servidor, Docker) + **Neon** (PostgreSQL administrado) |
| Diagramas | Mermaid (ER y UML), código fuente en `docs/diagramas/fuentes/` |

Arquitectura cliente-servidor de tres capas:

```
Navegador (celular / tablet / PC)  ──HTTPS + JSON──▶  Render: Node.js + Express  ──SQL (SSL)──▶  Neon: PostgreSQL
        public/index.html                                  src/server.js                          db/schema.sql
                 ▲                                              │
                 └──────── tiempo real (Server-Sent Events) ────┘
```

---

## 💻 Instrucciones de ejecución local

**Requisitos:** [Node.js](https://nodejs.org) 20.6 o superior (recomendado 22) y [PostgreSQL](https://www.postgresql.org/download/) 13 o superior.

```bash
# 1. Descargar el proyecto
git clone https://github.com/LOKURINAA5-max/Pinchos-La-17.git
cd Pinchos-La-17

# 2. Instalar dependencias
npm install

# 3. Crear la base de datos vacía (o desde pgAdmin: Create → Database → pinchos17)
createdb -U postgres pinchos17

# 4. Configurar las variables de entorno
cp .env.example .env          # en Windows: copy .env.example .env
```

Abrir `.env` y completar como mínimo:

```ini
DATABASE_URL=postgres://postgres:TU_CLAVE_DE_POSTGRES@localhost:5432/pinchos17
JWT_SECRET=<48 caracteres aleatorios>    # generarlo con: node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
ADMIN_USUARIO=admin
ADMIN_CLAVE=<mínimo 10 caracteres, con letras y números>
CARGAR_CATALOGO_EJEMPLO=false
```

```bash
# 5. Arrancar
npm start
```

Abrir **http://localhost:3000**. En el primer arranque el sistema crea **solo** todas las tablas, aplica las migraciones y crea
el administrador de `.env`. Luego:

1. **Personal** → entrar con `ADMIN_USUARIO` / `ADMIN_CLAVE`.
2. **Carta → «Cargar la carta de Pinchos la 17»** (75 platos y productos).
3. **Caja → Abrir caja**, y ya se puede pedir como cliente en otra pestaña (`http://localhost:3000/?mesa=1`).

Otros comandos útiles:

| Comando | Para qué |
|---|---|
| `npm run dev` | Arranca y se reinicia solo al cambiar el código |
| `node --env-file=.env scripts/crear-usuario.js cajero1 "Clave12345" caja` | Crear usuarios (`admin`, `caja` o `cocina`) |
| `psql -U postgres -d pinchos17 -f db/dml_pinchos17.sql` | Ejecutar los ejemplos de DML del informe (después de cargar la carta; agrega datos de demostración) |
| `node impresion/agente.mjs --prueba` | Probar la impresora de comandas (ver `impresion/LEEME.md`) |

> Con Docker: `docker compose up` levanta PostgreSQL y el servidor juntos (ver `DESPLIEGUE.md`).

---

## 🗂️ Modelo entidad-relación

27 tablas y 45 claves foráneas, agrupadas en 5 módulos. Las imágenes se generan desde la base real (cada línea es una clave foránea existente).

![Modelo entidad-relación — vista general](docs/diagramas/er/general.png)

<details>
<summary><b>Ver el modelo por módulos</b> (ventas, cocina, carta, inventario, control)</summary>

### Ventas y caja
![ER ventas](docs/diagramas/er/ventas.png)

### Cocina
![ER cocina](docs/diagramas/er/cocina.png)

### Carta, opciones y promociones
![ER carta](docs/diagramas/er/carta.png)

### Inventario
![ER inventario](docs/diagramas/er/inventario.png)

### Seguridad y control
![ER control](docs/diagramas/er/control.png)

</details>

## 📐 Diagramas UML

### Casos de uso
| Cliente | Caja | Cocina, administrador e impresora |
|---|---|---|
| ![Casos de uso cliente](docs/diagramas/uml/uc_cliente.png) | ![Casos de uso caja](docs/diagramas/uml/uc_caja.png) | ![Casos de uso cocina y administrador](docs/diagramas/uml/uc_cocina.png) |

### Clases
![Clases — ventas y caja](docs/diagramas/uml/clases1.png)
![Clases — carta y cocina](docs/diagramas/uml/clases2.png)
![Clases — inventario y control](docs/diagramas/uml/clases3.png)

<details>
<summary><b>Ver estados, secuencia y despliegue</b></summary>

### Estados de un pedido
![Estados del pedido](docs/diagramas/uml/estados.png)

### Secuencia: del pedido al cobro
![Secuencia](docs/diagramas/uml/secuencia.png)

### Despliegue
![Despliegue](docs/diagramas/uml/despliegue.png)

</details>

## 📄 Documentación

| Documento | Contenido |
|---|---|
| [`docs/Pinchos17_BD_ER_UML_DML_Riesgos.pdf`](docs/Pinchos17_BD_ER_UML_DML_Riesgos.pdf) | Informe completo: modelo ER, diccionario de tablas, diagramas UML, 33 bloques de DML con su resultado y matriz de riesgos (14 riesgos) |
| [`db/schema.sql`](db/schema.sql) | DDL: creación de tablas, restricciones, índices, vistas y triggers |
| [`db/dml_pinchos17.sql`](db/dml_pinchos17.sql) | DML: `INSERT`, `UPDATE`, `DELETE`, `SELECT` con `JOIN`, agregaciones y transacciones |
| [`INSTALAR_PINCHOS17.md`](INSTALAR_PINCHOS17.md) | Instalación y novedades de cada versión |
| [`DESPLIEGUE_NEON_RENDER.md`](DESPLIEGUE_NEON_RENDER.md) | Publicar el sistema con GitHub + Render + Neon |
| [`impresion/LEEME.md`](impresion/LEEME.md) | Conectar la impresora de comandas (USB o WiFi) |

## 📁 Estructura del repositorio

```
src/
  server.js          servidor Express: rutas de la API y reglas de negocio
  arranque.js        crea las tablas, aplica migraciones y el primer administrador
  cocina.js          comandas, descuento de inventario, costos y alertas de stock
  v8.js              facturas, compras, ajustes, carga de la carta
  geocodificar.js    búsqueda de direcciones para domicilios (Bucaramanga y área metropolitana)
  menu-carta.js      carta de Pinchos la 17
public/              interfaz web (index.html, css/, js/ por rol, vendor/leaflet)
db/                  schema.sql (DDL), migraciones, dml_pinchos17.sql (DML), seed
docs/                informe PDF, diagramas ER y UML (PNG + fuentes Mermaid)
impresion/           agente de impresión de comandas ESC/POS
scripts/             crear usuarios, copias de seguridad, migrar, limpiar pruebas
render.yaml · Dockerfile · docker-compose.yml   despliegue
```

## 🔒 Seguridad

- El archivo `.env` (cadena de conexión, `JWT_SECRET`, contraseñas) **no se sube** al repositorio: está en `.gitignore`. Se publica solo `.env.example`, sin valores.
- Contraseñas con bcrypt, bloqueo tras 5 intentos fallidos, verificación en dos pasos opcional, sesión en cookie `httpOnly`.
- Todas las consultas son parametrizadas (sin inyección SQL) y los precios los calcula el servidor, no el navegador.
- La conexión a Neon es cifrada (SSL). Las credenciales de prueba del aplicativo se comparten por un canal privado.
