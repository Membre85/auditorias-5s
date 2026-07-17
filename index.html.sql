-- ============================================================
-- ESQUEMA: Auditorías 5S - FHACASA / ALIANSA
-- Ejecutar completo en: Supabase → SQL Editor → New query → Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- TABLAS ----------

create table if not exists areas (
  id uuid primary key default gen_random_uuid(),
  planta text not null check (planta in ('FHACASA','ALIANSA')),
  nombre text not null,
  creado_en timestamptz default now()
);

create table if not exists preguntas (
  id uuid primary key default gen_random_uuid(),
  categoria text not null check (categoria in ('Seiri','Seiton','Seiso','Seiketsu','Shitsuke')),
  texto text not null,
  orden int default 0,
  activa boolean default true
);

create table if not exists auditorias (
  id uuid primary key default gen_random_uuid(),
  planta text not null check (planta in ('FHACASA','ALIANSA')),
  area text not null,
  auditor text not null,
  fecha date not null,
  gps_lat double precision,
  gps_lng double precision,
  creado_en timestamptz default now()
);

create table if not exists respuestas (
  id uuid primary key default gen_random_uuid(),
  auditoria_id uuid references auditorias(id) on delete cascade,
  pregunta_id uuid references preguntas(id),
  categoria text not null,
  texto text not null,
  valor text not null check (valor in ('Cumple','No Cumple','No Aplica')),
  hallazgo text,
  comentario text,
  fotos text[],
  creado_en timestamptz default now()
);

create table if not exists acciones (
  id uuid primary key default gen_random_uuid(),
  auditoria_id uuid references auditorias(id) on delete cascade,
  respuesta_id uuid references respuestas(id) on delete cascade,
  planta text not null,
  area text not null,
  descripcion_hallazgo text,
  responsable text,
  fecha_compromiso date,
  estado text not null default 'Abierta' check (estado in ('Abierta','En Proceso','Completada')),
  foto_cierre text,
  comentario_cierre text,
  fecha_cierre date,
  creado_en timestamptz default now()
);

-- Perfil de usuario vinculado a Supabase Auth (roles)
create table if not exists usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text,
  rol text not null default 'Auditor' check (rol in ('Admin','Auditor','Lider')),
  planta_asignada text,
  creado_en timestamptz default now()
);

-- ---------- SEGURIDAD (Row Level Security) ----------
-- MVP: cualquier usuario autenticado puede leer y escribir.
-- Esto es intencionalmente simple para arrancar; se puede refinar
-- luego para que un Auditor solo vea su planta y un Líder solo su área.

alter table areas enable row level security;
alter table preguntas enable row level security;
alter table auditorias enable row level security;
alter table respuestas enable row level security;
alter table acciones enable row level security;
alter table usuarios enable row level security;

drop policy if exists "areas_all_auth" on areas;
create policy "areas_all_auth" on areas for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "preguntas_all_auth" on preguntas;
create policy "preguntas_all_auth" on preguntas for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "auditorias_all_auth" on auditorias;
create policy "auditorias_all_auth" on auditorias for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "respuestas_all_auth" on respuestas;
create policy "respuestas_all_auth" on respuestas for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "acciones_all_auth" on acciones;
create policy "acciones_all_auth" on acciones for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "usuarios_select_auth" on usuarios;
create policy "usuarios_select_auth" on usuarios for select
  using (auth.role() = 'authenticated');

drop policy if exists "usuarios_update_self" on usuarios;
create policy "usuarios_update_self" on usuarios for update
  using (auth.uid() = id);

-- Cuando alguien se registra en Supabase Auth, crear su fila en "usuarios" automáticamente
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.usuarios (id, nombre, rol)
  values (new.id, new.email, 'Auditor');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- ALMACENAMIENTO DE FOTOS ----------
insert into storage.buckets (id, name, public)
values ('evidencias','evidencias', true)
on conflict (id) do nothing;

drop policy if exists "evidencias_read_public" on storage.objects;
create policy "evidencias_read_public" on storage.objects for select
  using (bucket_id = 'evidencias');

drop policy if exists "evidencias_write_auth" on storage.objects;
create policy "evidencias_write_auth" on storage.objects for insert
  with check (bucket_id = 'evidencias' and auth.role() = 'authenticated');

-- ---------- DATOS INICIALES: ÁREAS ----------
insert into areas (planta, nombre) values
('FHACASA','Producción'),('FHACASA','Empaque'),('FHACASA','Mantenimiento'),
('FHACASA','Distribución'),('FHACASA','Logística Primaria'),('FHACASA','Logística Secundaria'),
('FHACASA','Administración'),('FHACASA','Calidad'),('FHACASA','Exteriores'),
('FHACASA','Bodegas'),('FHACASA','Laboratorio'),('FHACASA','Oficinas'),('FHACASA','Baños'),
('ALIANSA','Producción'),('ALIANSA','Mantenimiento'),('ALIANSA','Distribución'),
('ALIANSA','Logística Primaria'),('ALIANSA','Logística Secundaria'),('ALIANSA','Administración'),
('ALIANSA','Calidad'),('ALIANSA','Exteriores'),('ALIANSA','Bodegas'),
('ALIANSA','Oficinas'),('ALIANSA','Baños')
on conflict do nothing;

-- ---------- DATOS INICIALES: 50 PREGUNTAS 5S ----------
insert into preguntas (categoria, texto, orden) values
('Seiri','¿El departamento mantiene únicamente los elementos esenciales para realizar sus funciones?',1),
('Seiri','¿Se clasifican y eliminan regularmente los materiales obsoletos y no utilizados?',2),
('Seiri','¿Los elementos de trabajo están etiquetados y organizados de manera clara y precisa?',3),
('Seiri','¿Se encuentran los elementos de trabajo fácilmente accesibles para el personal?',4),
('Seiri','¿Se cuenta con un registro actualizado de todos los elementos almacenados en el departamento?',5),
('Seiri','¿Se realiza una revisión periódica de los elementos almacenados y se eliminan los innecesarios?',6),
('Seiri','¿Los elementos de trabajo están correctamente etiquetados con información sobre su uso y manipulación?',7),
('Seiri','¿Los elementos de trabajo se encuentran almacenados de acuerdo a su frecuencia de uso?',8),
('Seiri','¿El personal del departamento está capacitado en la clasificación y almacenamiento eficiente de los elementos de trabajo?',9),
('Seiri','¿Están todos los elementos de limpieza: trapos, escobas, guantes, productos en su ubicación y correctamente identificados?',10),

('Seiton','¿Están claramente definidos los pasillos, áreas de almacenamiento, lugares de trabajo?',1),
('Seiton','¿Son necesarias todas las herramientas disponibles y fácilmente identificables?',2),
('Seiton','¿Están diferenciados e identificados los materiales o semielaborados del producto final?',3),
('Seiton','¿Los equipos y herramientas se encuentran ubicados en lugares designados y fácilmente accesibles?',4),
('Seiton','¿Hay algún tipo de obstáculo cerca del elemento de extinción de incendios más cercano?',5),
('Seiton','¿Tiene el suelo algún tipo de desperfecto: grietas, sobresalto…?',6),
('Seiton','¿Están las estanterías u otras áreas de almacenamiento en el lugar adecuado y debidamente identificadas?',7),
('Seiton','¿Está correctamente distribuido el mobiliario y equipo en los espacios de trabajo de los departamentos?',8),
('Seiton','¿Se han establecido zonas específicas para la recolección y separación de residuos en cada departamento?',9),
('Seiton','¿Hay líneas blancas u otros marcadores para indicar claramente los pasillos y áreas de almacenamiento?',10),

('Seiso','¿Al revisar el suelo, los pasos de acceso y los alrededores de los equipos se encuentran manchas de aceite, polvo o residuos?',1),
('Seiso','¿Hay partes de las máquinas o equipos sucios, con manchas de aceite, polvo o residuos?',2),
('Seiso','¿Está la tubería tanto de aire como eléctrica sucia, deteriorada o en general en mal estado?',3),
('Seiso','¿Está el sistema de drenaje de los residuos de tinta o aceite obstruido (total o parcialmente)?',4),
('Seiso','¿Hay elementos de la luminaria defectuosos (total o parcialmente)?',5),
('Seiso','¿Se utilizan herramientas y equipos de limpieza adecuados para cada tipo de tarea?',6),
('Seiso','¿Se realizan inspecciones periódicas para verificar el estado de limpieza y mantenimiento de las áreas de trabajo?',7),
('Seiso','¿El departamento cuenta con un programa regular de limpieza y mantenimiento de sus áreas de trabajo?',8),
('Seiso','¿Existe una persona o equipo de personas responsable de supervisar las operaciones de limpieza?',9),
('Seiso','¿Se promueve una cultura de limpieza y mantenimiento entre el personal del departamento?',10),

('Seiketsu','¿Se han establecido normas y procedimientos estandarizados para las actividades del departamento?',1),
('Seiketsu','¿Se realizan auditorías periódicas para verificar el cumplimiento de los estándares establecidos?',2),
('Seiketsu','¿El departamento cuenta con manuales de procedimientos claros y actualizados?',3),
('Seiketsu','¿La ropa que usa el personal es inapropiada o está sucia?',4),
('Seiketsu','¿Las diferentes áreas de trabajo tienen la luz suficiente y ventilación para la actividad que se desarrolla?',5),
('Seiketsu','¿Se generan regularmente mejoras en las diferentes áreas de la empresa?',6),
('Seiketsu','¿Se actúa generalmente sobre las ideas de mejora?',7),
('Seiketsu','¿Se revisan periódicamente los procedimientos y normas para su actualización y mejora?',8),
('Seiketsu','¿Se consideran futuras normas como plan de mejora clara de la zona?',9),
('Seiketsu','¿Se mantienen las 3 primeras S (eliminar innecesario, espacios definidos, limitación de pasillos, limpieza)?',10),

('Shitsuke','¿El departamento mantiene un compromiso continuo con la mejora de sus procesos y prácticas de trabajo?',1),
('Shitsuke','¿Se realizan reuniones periódicas de seguimiento y evaluación de los resultados obtenidos?',2),
('Shitsuke','¿El departamento mantiene una comunicación abierta y transparente sobre los resultados y avances en la implementación de las mejoras?',3),
('Shitsuke','¿El personal recibe capacitación y entrenamiento periódico para mantener y mejorar los estándares de calidad y eficiencia en el departamento?',4),
('Shitsuke','¿Se fomenta la cultura de la limpieza y el orden en todos los niveles de la empresa?',5),
('Shitsuke','¿Se realizan reuniones periódicas para reforzar los principios de la metodología 5S con el personal de los departamentos?',6),
('Shitsuke','¿El departamento mantiene una actitud proactiva y comprometida con la excelencia en sus procesos y prácticas de trabajo?',7),
('Shitsuke','¿Existen procedimientos de mejora y son revisados con regularidad?',8),
('Shitsuke','¿Todas las actividades definidas en las 5S se llevan a cabo y se realizan los seguimientos definidos?',9),
('Shitsuke','¿Los hallazgos de auditorías previas están cerrados o en proceso de cierre?',10)
on conflict do nothing;
