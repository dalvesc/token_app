# Token Pool Service

## Resumo

Este projeto implementa um serviço de alocação de _tokens_ concorrente, com regras rígidas de disponibilidade, tempo máximo de uso e substituição (eviction).

### Regras de negócio

- Existem **exatamente 100 tokens** no sistema. Cada token tem um UUID fixo.
- No máximo **100 tokens podem estar ativos simultaneamente**.
- Quando um usuário solicita acesso, ele recebe um token ativo.
- Um token **só pode ficar com um usuário por até 2 minutos**. Após esse tempo, ele é automaticamente liberado e volta ao pool.
- Se todos os 100 tokens estiverem ativos e um novo usuário pedir um token:
  - o sistema **remove o token mais antigo ainda ativo**
  - fecha o uso anterior desse token
  - **reatribui esse mesmo token** ao usuário novo  
    → Isso é a política de `evict oldest`.
- Todo uso de token é armazenado no banco (`token_usages`) com:
  - quem usou (`user_uuid`)
  - quando começou (`started_at`)
  - quando terminou (`released_at`)
- É possível consultar:
  - tokens ativos e disponíveis agora
  - estado de um token específico
  - histórico completo de um token
- Existe também um endpoint para **limpar todos os usos ativos na hora**.

---

## Arquitetura

### Componentes principais

- **Phoenix (API JSON)**  
  Exposição de rotas REST.
- **PostgreSQL + Ecto**  
  Armazena:

  - Tabela `tokens`: lista fixa dos 100 tokens disponíveis no sistema.
  - Tabela `token_usages`: cada sessão de uso de um token por um usuário.  
    Um token está "ativo" se tem um `usage` sem `released_at`.

- **TokenPool (GenServer + ETS)**  
  Processo supervisionado que faz o controle de concorrência e expiração:
  - Mantém em memória (ETS) quais tokens estão ativos agora, quem está usando e desde quando.
  - Garante que duas requisições simultâneas nunca recebam o mesmo token.
  - Enforce do TTL de 2 minutos via timers.
  - Implementa `evict oldest` quando não há tokens disponíveis.
  - Faz `sweep` periódico para garantir liberação de tokens expirados.
  - Ao reiniciar a aplicação, reconstrói o estado lendo o banco e reagendando timers.

### Por que usar um GenServer?

- Todas as requisições que querem alocar token passam por um único processo (`TokenPool`).
- Isso serializa a decisão crítica: "qual token vou entregar agora?"
- Assim evitamos corridas (race conditions) mesmo com alta concorrência.
- O banco continua sendo a verdade permanente do histórico. O GenServer apenas mantém um snapshot rápido (ETS) e timers de expiração.

### Recuperação após restart

- Quando a aplicação sobe, o `TokenPool`:
  - lê todos os usos abertos (`released_at IS NULL`) no banco
  - recria o estado interno de quais tokens estão ativos
  - calcula quanto tempo falta para cada expiração de 2 minutos
  - agenda novos timers
  - se algum já passou do tempo máximo, libera imediatamente

Isso garante que, mesmo depois de um crash, nenhum token continue "preso" para sempre.

---

## Setup / Como rodar local

### Pré-requisitos

- Elixir & Erlang (testado com Elixir 1.17 / OTP 27)
- Docker e Docker Compose
- Git

### 1. Clonar o repositório

```bash
git clone <SEU_REPO_GITHUB_AQUI>
cd token_app
```

### 2. Subir Postgres com Docker

```bash
docker compose up -d
```

Isso sobe um Postgres 16 local em `localhost:5432` com:

- user: `postgres`

- pass: `postgres`

- db: `token_app_dev`

### 3. Instalar deps

```bash
mix deps.get
```

### 4. Criar e migrar banco

```bash
mix ecto.create
mix ecto.migrate
```

### 5. Popular os 100 tokens iniciais

```bash
mix run priv/repo/seeds.exs
```

### 6. Rodar o servidor

```bash
mix phx.server
```

A API estará disponível em http://localhost:4000/api.

---

## Endpoints

### 1. Alocar um token

`POST /api/tokens/allocate`

Body:

```json
{
  "user_id": "4b8d55d6-f7be-4c5b-8fc7-2f6a96d8eabc"
}
```

Resposta:

```json
{
  "token_id": "2caa9c9b-3e6f-4b0f-9e5d-8a63fd1e75e1",
  "user_id": "4b8d55d6-f7be-4c5b-8fc7-2f6a96d8eabc",
  "expires_in_seconds": 120,
  "evicted_user": null
}
```

Se todos os 100 tokens já estavam ativos, você ainda recebe um token,
mas agora com evicted_user indicando quem foi substituído.

### 2. Listar estado atual

`GET /api/tokens`

Resposta:

```json
{
  "active": [
    {
      "token_id": "2caa9c9b-3e6f-4b0f-9e5d-8a63fd1e75e1",
      "user_id": "4b8d55d6-f7be-4c5b-8fc7-2f6a96d8eabc",
      "started_at": "2025-10-25T14:23:10Z",
      "expires_at": "2025-10-25T14:25:10Z"
    }
  ],
  "available": [
    { "token_id": "5a1b19df-2b92-4a68-8bf3-6e2bb94b1d3a" },
    { "token_id": "..." }
  ]
}
```

### 3. Ver status de um token específico

`GET /api/tokens/:token_id`

Resposta se ativo:

```json
{
  "token_id": "2caa9c9b-3e6f-4b0f-9e5d-8a63fd1e75e1",
  "status": "active",
  "current_user": {
    "user_id": "4b8d55d6-f7be-4c5b-8a63fd1e75e1",
    "started_at": "2025-10-25T14:23:10Z",
    "expires_at": "2025-10-25T14:25:10Z"
  }
}
```

Resposta se disponível:

```json
{
  "token_id": "5a1b19df-2b92-4a68-8bf3-6e2bb94b1d3a",
  "status": "available",
  "current_user": null
}
```

### 4. Histórico de um token

`GET /api/tokens/:token_id/history`

```json
[
  {
    "user_id": "4b8d55d6-f7be-4c5b-8a63fd1e75e1",
    "started_at": "2025-10-25T14:23:10Z",
    "released_at": "2025-10-25T14:24:30Z"
  },
  {
    "user_id": "9c11a20e-8ef4-44da-badf-9c00e3a822c1",
    "started_at": "2025-10-25T14:20:00Z",
    "released_at": "2025-10-25T14:22:00Z"
  }
]
```

### 5. Liberar todos os tokens imediatamente

`POST /api/tokens/clear`

Resposta:

```json
{
  "cleared": true,
  "released_count": 37
}
```

---