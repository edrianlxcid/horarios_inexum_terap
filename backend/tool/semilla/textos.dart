// Nombres y textos para generar datos FICTICIOS.
// Las combinaciones son aleatorias y no corresponden a personas reales.

const nombresNinas = [
  'Valentina', 'Camila', 'Sofía', 'Isabella', 'Emilia', 'Martina', 'Antonella', 'Renata',
  'Daniela', 'Paula', 'Victoria', 'Amelia', 'Julieta', 'Abigail', 'Luciana', 'Mía',
  'Regina', 'Ariana', 'Salomé', 'Doménica', 'Ámbar', 'Aitana', 'Allison', 'Zoe',
];

const nombresNinos = [
  'Mateo', 'Santiago', 'Sebastián', 'Thiago', 'Matías', 'Benjamín', 'Joaquín', 'Emiliano',
  'Gael', 'Dylan', 'Lucas', 'Martín', 'Nicolás', 'Samuel', 'Ian', 'Alejandro',
  'Josué', 'Elías', 'Leonardo', 'Daniel', 'Isaac', 'Gabriel', 'Adrián', 'Maximiliano',
];

const nombresAdultasF = [
  'María José', 'Andrea', 'Gabriela', 'Verónica', 'Carolina', 'Paola', 'Diana', 'Lorena',
  'Mónica', 'Fernanda', 'Cristina', 'Patricia', 'Jessica', 'Karina', 'Tatiana', 'Silvia',
  'Johanna', 'Estefanía', 'Natalia', 'Alexandra', 'Ximena', 'Viviana', 'Pamela', 'Elena',
];

const nombresAdultosM = [
  'Juan Carlos', 'Diego', 'Andrés', 'Christian', 'Jorge', 'Luis', 'Fernando', 'Pablo',
  'Roberto', 'Marco', 'Xavier', 'Esteban', 'Ricardo', 'Hugo', 'Javier', 'Ramiro',
  'Edison', 'Wilson', 'Patricio', 'Galo', 'Fabián', 'Iván', 'Rodrigo', 'Hernán',
];

const apellidos = [
  'Andrade', 'Benítez', 'Cárdenas', 'Chávez', 'Cevallos', 'Córdova', 'Espinoza', 'Flores',
  'Guerrero', 'Herrera', 'Jaramillo', 'León', 'Maldonado', 'Mena', 'Mora', 'Moreno',
  'Naranjo', 'Ortiz', 'Pazmiño', 'Proaño', 'Quishpe', 'Ramírez', 'Robalino', 'Salazar',
  'Sánchez', 'Tapia', 'Torres', 'Valencia', 'Vásquez', 'Villacís', 'Yánez', 'Zambrano',
  'Arias', 'Bustamante', 'Calderón', 'Erazo', 'Granda', 'Larrea', 'Montalvo', 'Paredes',
];

const calles = [
  'Av. Maldonado', 'Av. Napo', 'Calle Alonso de Angulo', 'Av. Teniente Hugo Ortiz', 'Calle Gatazo',
  'Av. 6 de Diciembre', 'Av. Eloy Alfaro', 'Calle Los Shyris', 'Av. De la Prensa', 'Calle El Inca',
  'Av. Interoceánica', 'Calle Juan Montalvo', 'Calle Francisco de Orellana', 'Av. Ilaló', 'Calle Gonzalo Pizarro',
];

const resumenesFamilia = [
  'Trabajó con muy buena disposición y completó todas las actividades.',
  'Hoy mejoró su atención sostenida; repetir en casa los ejercicios de la tarjeta.',
  'Le costó al inicio, pero logró terminar la secuencia con apoyo.',
  'Avanzó en la pronunciación de los sonidos trabajados.',
  'Buena coordinación motriz fina; seguir practicando el recorte.',
  'Se mostró cansado; se adaptó la sesión con actividades más cortas.',
  'Excelente participación en grupo y respeto de turnos.',
  'Logró el objetivo de la semana. ¡Felicitaciones!',
];

const notasClinicas = [
  'Se trabaja integración sensorial con circuito de propiocepción. Tolera mejor estímulos táctiles. Se observa menor evitación.',
  'Ejercicios de praxias orofaciales y discriminación auditiva de fonemas /r/ y /rr/. Mejora en posición lingual.',
  'Sesión de escucha Tomatis, fase activa. Refiere menor hipersensibilidad auditiva según reporte de la madre.',
  'Trabajo de funciones ejecutivas: planificación y memoria de trabajo con juego de secuencias. Requiere apoyo verbal.',
  'Motricidad fina: pinza trípode y trazos. Mantiene postura con apoyo. Aumenta tiempo de permanencia en mesa.',
  'Regulación emocional: identificación de emociones con pictogramas. Episodio breve de frustración, se autorregula con apoyo.',
  'Vocabulario en inglés: colores y animales. Responde a consignas simples. Participa en canción grupal.',
  'Estimulación temprana: gateo dirigido y seguimiento visual. Buena respuesta a estímulos sonoros.',
];

const objetivosTerapeuticos = [
  'Mejorar la atención sostenida en actividades de mesa hasta 15 minutos.',
  'Articular correctamente los fonemas /r/ y /rr/ en palabras.',
  'Disminuir la hipersensibilidad auditiva en ambientes ruidosos.',
  'Lograr pinza trípode funcional para la escritura.',
  'Seguir instrucciones de dos pasos sin apoyo visual.',
  'Identificar y nombrar cuatro emociones básicas.',
  'Ampliar el vocabulario expresivo en inglés a 50 palabras.',
  'Mejorar el equilibrio dinámico y la coordinación bilateral.',
  'Tolerar texturas nuevas en la alimentación.',
  'Respetar turnos en juegos de grupo.',
];

const tareasCasa = [
  ('Lectura compartida', 'Leer un cuento corto cada noche y pedir que cuente qué pasó.'),
  ('Juego de soplo', 'Soplar burbujas o una vela 5 minutos al día.'),
  ('Recortar figuras', 'Recortar 3 figuras sencillas siguiendo la línea.'),
  ('Rutina visual', 'Usar la tarjeta de rutina de la mañana durante la semana.'),
  ('Canción en inglés', 'Cantar juntos la canción de los colores vista en clase.'),
  ('Circuito en casa', 'Armar un circuito con cojines y gatear o saltar 10 minutos.'),
  ('Pictogramas', 'Nombrar la emoción del día usando los pictogramas.'),
];

const comentariosEvaluacion = [
  'Muy profesional y paciente con mi hijo.',
  'Hemos visto avances claros en casa.',
  'Siempre puntual y explica bien lo que trabajan.',
  'Mi hija la quiere mucho, se nota la conexión.',
  'Bien, aunque a veces faltó comunicación con nosotros.',
  'Esperábamos más avances en este tiempo.',
  null,
  null,
];

const motivosDemanda = [
  'Requiere contención frecuente durante la sesión.',
  'Presenta episodios de desregulación que interrumpen al grupo.',
  'Trabaja de forma autónoma la mayor parte del tiempo.',
  'Necesita apoyo de un segundo profesional en crisis.',
  'Hiperactividad marcada; se recomienda grupo reducido.',
  'Buena adaptación; necesita solo adaptaciones puntuales.',
];
