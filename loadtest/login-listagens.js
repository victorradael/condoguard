// Primeiro roteiro k6: login + listagens, pelo caminho k6 → Caddy → API.
// Metas: FAB-3 › metas (seção 2). Rodar com `make loadtest SCENARIO=...`.
//
// Cenários (variável SCENARIO):
//   smoke  1 VU por 30 s (padrão; usado no CI)
//   carga  50 VUs por 10 min (carga contínua)
//   pico   0 → 150 VUs em 1 min, 2 min no topo (limites de p95 em dobro)
//
// Cada VU usa um IP fictício próprio em Cf-Connecting-IP (o Caddy usa esse
// cabeçalho na porta interna :8080), então o limite por IP vale por usuário,
// como na vida real. Respostas 429 contam à parte e não entram como erro.
//
// Conta: K6_EMAIL/K6_PASSWORD (contas do seed: `make seed-poc` na API com
// SEED_PASSWORD; o porteiro entra sem segundo fator). Sem elas, o setup()
// cria uma conta descartável via /auth/register.

import http from 'k6/http';
import { check, fail, sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://caddy:8080';
// API_URL aponta direto para a API (sem o prefixo /api do Caddy).
const API = __ENV.API_URL || `${BASE_URL}/api`;
const SCENARIO = __ENV.SCENARIO || 'smoke';
const FATOR = SCENARIO === 'pico' ? 2 : 1;

const cenarios = {
  smoke: { executor: 'constant-vus', vus: 1, duration: '30s' },
  carga: { executor: 'constant-vus', vus: 50, duration: '10m' },
  pico: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '1m', target: 150 },
      { duration: '2m', target: 150 },
      { duration: '15s', target: 0 },
    ],
  },
};

if (!cenarios[SCENARIO]) {
  throw new Error(`SCENARIO desconhecido: ${SCENARIO} (use smoke, carga ou pico)`);
}

const erros = new Rate('condoguard_erros');
const limitadas = new Counter('condoguard_429');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 429));

export const options = {
  scenarios: { [SCENARIO]: cenarios[SCENARIO] },
  thresholds: {
    condoguard_erros: ['rate<0.005'],
    'http_req_duration{grupo:login}': [`p(95)<${400 * FATOR}`],
    'http_req_duration{grupo:listagem}': [`p(95)<${150 * FATOR}`],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Listagens da 1c no seed-poc (3 blocos, 120 unidades, ~300 pessoas): a
// primeira página, a busca por trecho do nome e o filtro por bloco.
const LISTAGENS = [
  '/people',
  '/people?pageSize=100',
  '/people?q=silva',
  '/people?active=true&page=2',
  '/units',
  '/units?pageSize=100&sort=number',
  '/blocks',
];

function headersDoVU(extra) {
  const vu = __VU || 0;
  const ip = `10.77.${Math.floor(vu / 250) % 250}.${(vu % 250) + 1}`;
  return Object.assign(
    {
      'Content-Type': 'application/json',
      'Cf-Connecting-IP': ip,
      // Sem o Caddy (API_URL direto na API, com TRUSTED_PROXIES): o Caddy
      // sobrescreve este cabeçalho com o de cima.
      'X-Real-IP': ip,
    },
    extra || {},
  );
}

function registrar(res) {
  if (res.status === 429) {
    limitadas.add(1);
    return;
  }
  erros.add(res.status >= 400);
}

export function setup() {
  let email = __ENV.K6_EMAIL;
  let password = __ENV.K6_PASSWORD;
  if (!email) {
    const sufixo = `${Date.now()}`;
    const username = `k6-${sufixo}`;
    email = `${username}@k6.condoguard.local`;
    password = `K6-senha-${sufixo}-${Math.random().toString(36).slice(2)}`;
    const res = http.post(
      `${API}/auth/register`,
      JSON.stringify({ username, email, password }),
      { headers: headersDoVU() },
    );
    if (res.status !== 201) fail(`cadastro da conta do k6 falhou: ${res.status} ${res.body}`);
  }
  return { email, password };
}

let token = null;

function login(conta) {
  const res = http.post(
    `${API}/auth/login`,
    JSON.stringify({ email: conta.email, password: conta.password }),
    { headers: headersDoVU(), tags: { grupo: 'login', name: 'POST /auth/login' } },
  );
  registrar(res);
  check(res, { 'login 200': (r) => r.status === 200 });
  if (res.status === 200) token = res.json('accessToken');
}

export default function (conta) {
  if (!token) {
    login(conta);
    if (!token) {
      sleep(1);
      return;
    }
  }

  const path = LISTAGENS[Math.floor(Math.random() * LISTAGENS.length)];
  const res = http.get(`${API}${path}`, {
    headers: headersDoVU({ Authorization: `Bearer ${token}` }),
    tags: { grupo: 'listagem', name: `GET ${path}` },
  });
  registrar(res);
  check(res, { 'listagem 200': (r) => r.status === 200 });
  if (res.status === 401) token = null;

  sleep(1 + Math.random() * 2);
}

export function handleSummary(data) {
  const arquivo = `/results/${SCENARIO}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  return {
    stdout: textoResumo(data),
    [arquivo]: JSON.stringify(data, null, 2),
  };
}

function textoResumo(data) {
  const m = data.metrics;
  const p95 = (nome) => {
    const met = m[nome];
    return met && met.values ? `${met.values['p(95)'].toFixed(1)} ms` : 'n/d';
  };
  const linhas = [
    `\ncenário: ${SCENARIO}  (limites de p95 × ${FATOR})`,
    `login     p95 = ${p95('http_req_duration{grupo:login}')}  (meta ≤ ${400 * FATOR} ms)`,
    `listagem  p95 = ${p95('http_req_duration{grupo:listagem}')}  (meta ≤ ${150 * FATOR} ms)`,
    `erros     = ${((m.condoguard_erros?.values.rate || 0) * 100).toFixed(2)}%  (meta < 0,5%)`,
    `429       = ${m.condoguard_429?.values.count || 0}`,
    '',
  ];
  return linhas.join('\n');
}
