// Carta de «Pinchos la 17» (Calle 17 # 25-78 · WhatsApp 311 532 0476).
// Se carga desde el panel: Carta → «Cargar la carta de Pinchos la 17». Después todo se ajusta desde el panel.
// Formato de cada producto: [nombre, precio, descripción, zonas, extras]
//   zonas: [['Asador'|'Cocina', parte]] · sin zona = no pasa por cocina (bebidas)
//   extras.grupos: [{ nombre, obligatorio, multiple, opciones: [{ nombre, extra, zona }] }]
//   precio null = precio pendiente: se carga en $0 y AGOTADO, para que el cliente no lo pida hasta ponerle precio.
const AS = [['Asador', null]], CO = [['Cocina', null]], NO = [];

// Adicionales que se pueden sumar a pinchos y asados ($1.500 cada uno, se pueden elegir varios)
const ADICIONALES = {
  nombre: 'Adicionales', obligatorio: false, multiple: true, opciones: [
    { nombre: 'Arroz', extra: 1500, zona: 'Cocina' },
    { nombre: 'Papa', extra: 1500, zona: 'Cocina' },
    { nombre: 'Yuca', extra: 1500, zona: 'Cocina' },
    { nombre: 'Guacamole', extra: 1500, zona: 'Cocina' },
    { nombre: 'Chorizo de cerdo', extra: 1500, zona: 'Asador' },
  ],
};
const sabor = (...s) => ({ grupos: [{ nombre: 'Sabor', obligatorio: true, multiple: false, opciones: s.map((nombre) => ({ nombre, extra: 0, zona: null })) }] });
const conAdicionales = { grupos: [ADICIONALES] };

export const CARTA = [
  { cat: 'Pinchos', emoji: '🍢', items: [
    ['Pincho de carne con chunchullo', 8000, 'A la brasa', AS, conAdicionales],
    ['Pincho mixto', 8000, 'Carne y pollo a la brasa', AS, conAdicionales],
    ['Pincho solo carne', 8000, 'A la brasa', AS, conAdicionales],
    ['Pincho solo pollo', 8000, 'A la brasa', AS, conAdicionales],
    ['Pincho de mazorca', 8000, 'A la brasa', AS, conAdicionales],
    ['Pincho de chorizo de cerdo', 8000, 'A la brasa', AS, conAdicionales],
    ['Pincho de rellena', 8000, 'A la brasa', AS, conAdicionales],
  ] },
  { cat: 'Asados', emoji: '🔥', items: [
    ['Sobrebarriga asada', 22000, '', AS, conAdicionales],
    ['Chatas asadas', 22000, '', AS, conAdicionales],
    ['Chuleta de cerdo', 22000, '', AS, conAdicionales],
    ['Pechuga asada', 15000, '', AS, conAdicionales],
    ['Pierna pernil asada', 13000, '', AS, conAdicionales],
  ] },
  { cat: 'Típicos', emoji: '🍲', items: [
    ['Mute santandereano', 14000, '', CO],
  ] },
  { cat: 'Adicionales', emoji: '➕', items: [
    ['Adicional de arroz', 1500, '', CO], ['Adicional de papa', 1500, '', CO], ['Adicional de yuca', 1500, '', CO],
    ['Adicional de guacamole', 1500, '', CO], ['Adicional de chorizo de cerdo', 1500, '', AS],
  ] },
  { cat: 'Cervezas', emoji: '🍺', items: [
    ['Buchona Poker 1000 ml', null, '', NO],
    ['Buchona Águila Light 1000 ml', null, '', NO],
    ['Buchona Águila Negra 1000 ml', null, '', NO],
    ['Stella Artois 310 ml', null, '', NO],
    ['Águila Original botella 330 ml', null, '', NO],
    ['Coronita 210 ml', null, '', NO],
    ['Club Colombia botella 330 ml', null, '', NO],
    ['Lata Águila Original 330 ml', null, '', NO],
    ['Lata Águila Light 330 ml', null, '', NO],
    ['Lata Club Colombia Trigo 330 ml', null, '', NO],
    ['Lata Club Colombia Roja 330 ml', null, '', NO],
    ['Lata Club Colombia Dorada 330 ml', null, '', NO],
    ['Lata Budweiser 330 ml', null, '', NO],
    ['Lata Costeña Bacana 330 ml', null, '', NO],
    ['Lata Poker 330 ml', null, '', NO],
  ] },
  { cat: 'Bebidas personales', emoji: '🥤', items: [
    ['Agua Cristal pequeña 300 ml', null, '', NO],
    ['Agua Cristal con gas pequeña 250 ml', null, '', NO],
    ['Agua Cristal personal 600 ml', null, '', NO],
    ['H2O personal 600 ml', null, '', NO],
    ['Gatorade 500 ml', null, '', NO, sabor('Rojo', 'Naranja')],
    ['Pony Malta pequeña 200 ml', null, '', NO],
    ['Pony Malta personal 330 ml', null, '', NO],
    ['Pony Malta botella 330 ml', null, '', NO],
    ['Mr. Tea personal limón 500 ml', null, '', NO],
    ['Mr. Tea botella personal 250 ml', null, '', NO, sabor('Durazno', 'Limón')],
    ['Hit personal 500 ml', null, '', NO, sabor('Mango', 'Mora', 'Tropical')],
    ['Hit botella 350 ml', null, '', NO, sabor('Mango', 'Mora', 'Tropical')],
    ['Hit caja 200 ml', null, '', NO],
    ['Amper 473 ml', null, '', NO],
    ['Vive 100 380 ml', null, '', NO],
    ['Cola y Pola lata 330 ml', null, '', NO],
    ['Gaseosa pequeña 250 ml', null, '', NO, sabor('7Up', 'Piña', 'Cola', 'Naranja', 'Manzana')],
    ['Gaseosa personal 350 ml', null, '', NO, sabor('Cola', 'Piña', 'Uva', 'Naranja', 'Manzana')],
    ['Soda personal 350 ml', null, '', NO],
  ] },
  { cat: 'Gaseosas litro', emoji: '🧃', items: [
    ['Gaseosa 1250 ml', null, '', NO, sabor('Manzana', 'Cola', 'Uva', 'Piña', '7Up')],
    ['Hit litro', null, '', NO, sabor('Mango', 'Tropical', 'Mora')],
    ['Agua Cristal litro 1000 ml', null, '', NO],
    ['Pony Malta litro 1000 ml', null, '', NO],
    ['H2O lima limón 1500 ml', null, '', NO],
    ['Mr. Tea litro 1500 ml', null, '', NO, sabor('Durazno', 'Limón')],
    ['Econolitro 1000 ml', null, '', NO, sabor('Cola', 'Manzana', 'Pepsi', 'Colombiana')],
    ['Soda litro 1500 ml', null, '', NO],
    ['Gaseosa plástica 1500 ml', null, '', NO, sabor('Colombiana', 'Piña', 'Manzana', 'Cola')],
    ['Gaseosa 2500 ml', null, '', NO, sabor('Cola', 'Pepsi', 'Manzana')],
    ['Cola y Pola 1500 ml', null, '', NO],
  ] },
  { cat: 'Coca-Cola', emoji: '🥤', items: [
    ['Coca-Cola 237 ml', null, '', NO],
    ['Coca-Cola 350 ml', null, '', NO],
    ['Coca-Cola plástica 400 ml', null, '', NO, sabor('Original', 'Cero')],
    ['Coca-Cola 1000 ml', null, '', NO],
    ['Coca-Cola 1500 ml', null, '', NO],
    ['Coca-Cola 2250 ml', null, '', NO],
    ['Quatro 350 ml', null, '', NO],
    ['Quatro 1000 ml', null, '', NO],
    ['Quatro 1500 ml', null, '', NO],
    ['Agua con gas personal 600 ml', null, '', NO],
    ['Agua manzana 600 ml', null, '', NO],
    ['Gurú Energy 473 ml', null, '', NO],
  ] },
];
export const TOTAL_PRODUCTOS = CARTA.reduce((n, c) => n + c.items.length, 0);
