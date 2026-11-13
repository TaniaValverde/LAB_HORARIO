type MapValue = Record<string, unknown>;

function isMap(value: unknown): value is MapValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function cp1252(value: string): Buffer {
  const special = new Map<number, number>([
    [0x2013, 0x96], [0x2014, 0x97], [0x2018, 0x91], [0x2019, 0x92],
    [0x201c, 0x93], [0x201d, 0x94], [0x2022, 0x95], [0x20ac, 0x80],
  ]);
  const bytes: number[] = [];
  for (const character of value) {
    const point = character.codePointAt(0)!;
    bytes.push(point <= 0xff ? point : (special.get(point) ?? 0x3f));
  }
  return Buffer.from(bytes);
}

function wrap(text: string, width = 92): string[] {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    if (line && line.length + word.length + 1 > width) {
      lines.push(line);
      line = word;
    } else {
      line = line ? `${line} ${word}` : word;
    }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [''];
}

function escapePdfText(text: string): string {
  return cp1252(text).toString('hex').toUpperCase();
}

function isoDate(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  if (isMap(value) && typeof value.toDate === 'function') {
    const date = (value.toDate as () => unknown)();
    if (date instanceof Date && Number.isFinite(date.getTime())) return date.toISOString();
  }
  return '';
}

/** Minimal, self-contained PDF using the standard WinAnsi Helvetica font. */
export function buildFinalDeclarationPdf(input: {
  declarationId: string;
  declaration: MapValue;
  declarantSignatureEvent: MapValue;
  superiorSignatureEvent: MapValue;
  oathTextVersion: number;
  oathText: string;
}): Buffer {
  const { declaration } = input;
  const payload = isMap(declaration.payload) ? declaration.payload : {};
  const profile = isMap(payload.profile) ? payload.profile : {};
  const lines: string[] = [
    'DECLARACION JURADA DE HORARIO',
    '',
    `Identificador: ${input.declarationId}`,
    `Periodo: ${String(declaration.periodId ?? '')}`,
    `Version formal: ${String(declaration.version ?? '')}`,
    `Estado: ${String(declaration.status ?? '')}`,
    '',
    `JURAMENTO INSTITUCIONAL APROBADO (VERSION ${input.oathTextVersion})`,
    input.oathText,
    '',
    'PERSONA DECLARANTE',
    `Nombre: ${String(profile.name ?? '')}`,
    `Identificacion: ${String(profile.identification ?? '')}`,
    `Correo: ${String(profile.email ?? '')}`,
    `Unidad: ${String(profile.unit ?? '')}`,
    '',
  ];
  const appendJobs = (key: string, title: string) => {
    const jobs = Array.isArray(payload[key]) ? payload[key] as unknown[] : [];
    lines.push(title);
    jobs.forEach((raw, index) => {
      const job = isMap(raw) ? raw : {};
      lines.push(`${index + 1}. ${String(job.workplace ?? job.institution ?? '')} - ${String(job.position ?? '')}`);
      lines.push(`Vigencia: ${String(job.startsOn ?? '')} a ${String(job.endsOn ?? '')}`);
      if (typeof job.courseCode === 'string' && job.courseCode.trim()) {
        lines.push(`Sigla del curso: ${job.courseCode}`);
      }
      lines.push(`Jornada semanal declarada: ${String(job.weeklyMinutes ?? '')} minutos`);
      const blocks = Array.isArray(job.blocks) ? job.blocks as unknown[] : [];
      const workloadLabels: Record<string, string> = {
        fullTime: 'Tiempo completo', halfTime: 'Medio tiempo', quarterTime: '1/4 de tiempo',
      };
      if (typeof job.workloadType === 'string' && workloadLabels[job.workloadType]) {
        lines.push(`Tipo de jornada: ${workloadLabels[job.workloadType]}`);
        const minutesFor = (activity: string) => blocks.reduce<number>((total, rawBlock) => {
          const block = isMap(rawBlock) ? rawBlock : {};
          return total + (block.activity === activity && typeof block.start === 'number' && typeof block.end === 'number'
            ? block.end - block.start : 0);
        }, 0);
        const duration = (minutes: number) => `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
        lines.push(`Clases: ${duration(minutesFor('teaching'))}; consultas: ${duration(minutesFor('consultation'))}`);
        lines.push('Distribucion: 30 minutos de consulta por cada hora de clase.');
      }
      for (const rawBlock of blocks) {
        const block = isMap(rawBlock) ? rawBlock : {};
        const activity = block.activity === 'teaching' ? ' - Clase' : block.activity === 'consultation' ? ' - Consulta' : '';
        lines.push(`  Dia ${String(block.day ?? '')}: ${String(block.start ?? '')}-${String(block.end ?? '')} minutos desde medianoche${activity}`);
      }
    });
    if (jobs.length === 0) lines.push('Sin registros.');
    lines.push('');
  };
  appendJobs('appointments', 'NOMBRAMIENTOS INSTITUCIONALES');
  appendJobs('externalJobs', 'OTRAS INSTITUCIONES');
  lines.push('OBSERVACIONES', String(payload.observations ?? ''), '', 'FIRMAS ELECTRONICAS INTERNAS');
  lines.push(`Declarante UID: ${String(input.declarantSignatureEvent.actorId ?? '')}`);
  lines.push(`Identificador de firma: ${String(declaration.declarantSignature ?? '')}`);
  lines.push(`Hash SHA-256 del contenido: ${String(input.declarantSignatureEvent.contentHash ?? declaration.declarantContentHash ?? 'No registrado')}`);
  lines.push(`Fecha y hora: ${isoDate(declaration.declarantSignedAt)}`);
  lines.push(`Version/revision: ${String(declaration.version ?? '')} / ${String(declaration.revision ?? '')}`);
  lines.push('');
  lines.push(`Superior UID: ${String(input.superiorSignatureEvent.actorId ?? '')}`);
  lines.push(`Identificador de firma: ${String(declaration.superiorSignature ?? '')}`);
  lines.push(`Hash SHA-256 del contenido: ${String(input.superiorSignatureEvent.contentHash ?? declaration.superiorContentHash ?? 'No registrado')}`);
  lines.push(`Fecha y hora: ${isoDate(declaration.superiorSignedAt)}`);
  lines.push('');
  lines.push('Este registro corresponde a una firma electronica interna del sistema; no afirma ser firma digital certificada.');

  const wrapped = lines.flatMap((line) => wrap(line));
  const pages: string[][] = [];
  for (let index = 0; index < wrapped.length; index += 56) pages.push(wrapped.slice(index, index + 56));
  if (pages.length === 0) pages.push(['']);
  const objects: Buffer[] = [];
  const object = (id: number, body: Buffer | string) => {
    const content = Buffer.isBuffer(body) ? body : Buffer.from(body, 'binary');
    objects[id] = Buffer.concat([Buffer.from(`${id} 0 obj\n`, 'binary'), content, Buffer.from('\nendobj\n', 'binary')]);
  };
  const pageIds = pages.map((_, index) => 4 + index * 2);
  const kids = pageIds.map((id) => `${id} 0 R`).join(' ');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, `<< /Type /Pages /Kids [${kids}] /Count ${pages.length} >>`);
  object(3, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  pages.forEach((page, index) => {
    const pageId = pageIds[index];
    const contentId = pageId + 1;
    const textCommands = page.map((line, lineIndex) =>
      `<${escapePdfText(line)}> Tj${lineIndex === page.length - 1 ? '' : ' T*'}`,
    ).join('\n');
    const stream = Buffer.from(`BT\n/F1 10 Tf\n50 750 Td\n12 TL\n${textCommands}\nET`, 'binary');
    object(pageId, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentId} 0 R >>`);
    object(contentId, Buffer.concat([
      Buffer.from(`<< /Length ${stream.length} >>\nstream\n`, 'binary'), stream,
      Buffer.from('\nendstream', 'binary'),
    ]));
  });
  const header = Buffer.from('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n', 'binary');
  const body = Buffer.concat([header, ...objects.slice(1)]);
  const offsets: number[] = [0];
  let offset = header.length;
  for (const item of objects.slice(1)) {
    offsets.push(offset);
    offset += item.length;
  }
  const xrefOffset = body.length;
  const xref = [
    `xref\n0 ${objects.length}\n`,
    '0000000000 65535 f \n',
    ...offsets.slice(1).map((value) => `${String(value).padStart(10, '0')} 00000 n \n`),
    `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`,
  ].join('');
  return Buffer.concat([body, Buffer.from(xref, 'binary')]);
}
