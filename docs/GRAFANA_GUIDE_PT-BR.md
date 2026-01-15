# Guia Passo a Passo: Monitorando seu Cluster K3s no Grafana

Este guia vai te ensinar a monitorar seu cluster Kubernetes usando o Grafana. Vamos cobrir:

- CPU e Memória de cada Node
- Namespaces do cluster
- Consumo de recursos por Namespace
- Quantidade de Pods por Node
- Pods com falha

---

## 1. Acessando o Grafana

### Passo 1.1: Abra o navegador

Acesse o Grafana pelo endereço:

```
http://192.168.1.201
```

### Passo 1.2: Faça login

- **Usuário:** `admin`
- **Senha:** `prom-operator`

![Login Screen](https://grafana.com/static/img/docs/getting-started/login-screen.png)

---

## 2. Navegando pelos Dashboards

### Passo 2.1: Acessar o menu de Dashboards

1. No menu lateral esquerdo, clique no ícone de **quatro quadrados** (Dashboards)
2. Ou use o atalho de teclado: **`d`** depois **`b`**

### Passo 2.2: Encontrar os dashboards do Kubernetes

1. Clique em **"Browse"** ou **"Dashboards"**
2. Você verá várias pastas. Clique na pasta **"General"** ou procure por dashboards que começam com **"Kubernetes"**

---

## 3. Ver CPU e Memória de Cada Node

### Dashboard: "Kubernetes / Compute Resources / Node (Pods)"

#### Passo 3.1: Abrir o dashboard

1. No menu lateral, clique em **Dashboards** → **Browse**
2. Na barra de busca, digite: **`node`**
3. Clique em **"Kubernetes / Compute Resources / Node (Pods)"**

#### Passo 3.2: Selecionar o Node

1. No topo do dashboard, você verá um dropdown chamado **"node"**
2. Clique nele e selecione o node que deseja visualizar:
   - `master` (ou o nome do seu node master)
   - `worker01`
   - `worker02`

#### O que você vai ver:

| Painel | Descrição |
|--------|-----------|
| **CPU Usage** | Uso de CPU do node em cores |
| **CPU Quota** | Quanto de CPU os pods estão solicitando vs limite |
| **Memory Usage** | Uso de memória RAM em bytes |
| **Memory Quota** | Quanto de memória os pods estão solicitando vs limite |

#### Dica: Ver todos os nodes de uma vez

1. Busque por **"Kubernetes / Compute Resources / Cluster"**
2. Este dashboard mostra todos os nodes lado a lado

---

## 4. Ver Todos os Namespaces do Cluster

### Dashboard: "Kubernetes / Compute Resources / Namespace (Pods)"

#### Passo 4.1: Abrir o dashboard

1. No menu lateral, clique em **Dashboards** → **Browse**
2. Na barra de busca, digite: **`namespace`**
3. Clique em **"Kubernetes / Compute Resources / Namespace (Pods)"**

#### Passo 4.2: Ver a lista de namespaces

1. No topo do dashboard, clique no dropdown **"namespace"**
2. Você verá a lista completa de namespaces:
   - `default`
   - `kube-system`
   - `monitoring`
   - `metallb-system`
   - `cloudflare`
   - etc.

---

## 5. Consumo de Recursos por Namespace

### Dashboard: "Kubernetes / Compute Resources / Namespace (Pods)"

Este é o mesmo dashboard do passo anterior.

#### Passo 5.1: Selecionar um namespace

1. No dropdown **"namespace"**, selecione o namespace desejado
   - Exemplo: `monitoring`

#### Passo 5.2: Analisar os painéis

| Painel | O que mostra |
|--------|--------------|
| **CPU Usage** | Quanto de CPU o namespace está consumindo |
| **CPU Quota** | Requests vs Limits de CPU |
| **Memory Usage** | Quanto de memória o namespace está consumindo |
| **Memory Quota** | Requests vs Limits de memória |
| **Current Network Usage** | Tráfego de rede do namespace |

#### Dica: Comparar namespaces

1. Busque por **"Kubernetes / Compute Resources / Cluster"**
2. Role até a seção **"Namespace"** para ver uma tabela comparativa

---

## 6. Quantidade de Pods por Node

### Dashboard: "Kubernetes / Compute Resources / Node (Pods)"

#### Passo 6.1: Abrir o dashboard

1. Busque por **"Kubernetes / Compute Resources / Node (Pods)"**
2. Selecione um node no dropdown

#### Passo 6.2: Ver os pods

1. Role a página para baixo
2. Você verá uma **tabela com todos os pods** rodando naquele node
3. A tabela mostra:
   - Nome do pod
   - Namespace
   - CPU usado
   - Memória usada

### Alternativa: Ver distribuição de pods

1. Busque por **"Kubernetes / Kubelet"**
2. Este dashboard mostra:
   - **Running Pods** - Quantidade de pods por node
   - **Running Containers** - Quantidade de containers

---

## 7. Encontrar Pods com Falha

### Método 1: Dashboard "Kubernetes / Compute Resources / Cluster"

#### Passo 7.1: Abrir o dashboard

1. Busque por **"Kubernetes / Compute Resources / Cluster"**

#### Passo 7.2: Verificar status dos pods

1. No topo do dashboard, procure por painéis que mostram:
   - **Pods Running** - Pods funcionando
   - **Pods Pending** - Pods aguardando recursos
   - **Pods Failed** - Pods com falha
   - **Pods Succeeded** - Pods que completaram (Jobs)

### Método 2: Criar uma Query Personalizada

#### Passo 7.2.1: Abrir o Explore

1. No menu lateral esquerdo, clique em **Explore** (ícone de bússola)

#### Passo 7.2.2: Executar a query

1. Certifique-se que **Prometheus** está selecionado no dropdown de data source
2. Cole esta query:

```promql
kube_pod_status_phase{phase=~"Failed|Pending|Unknown"}
```

3. Clique em **Run Query** (ou pressione Shift+Enter)

#### O que você vai ver:

Uma lista de pods que estão em estado:
- **Failed** - Falhou
- **Pending** - Aguardando (pode indicar problema de recursos)
- **Unknown** - Estado desconhecido

---

## 8. Criar um Dashboard Personalizado (Opcional)

Se você quiser ter todas as informações em um único lugar:

### Passo 8.1: Criar novo dashboard

1. Menu lateral → **Dashboards** → **New** → **New Dashboard**

### Passo 8.2: Adicionar painéis

Clique em **"Add visualization"** e adicione os seguintes painéis:

#### Painel 1: CPU por Node
```promql
sum(rate(container_cpu_usage_seconds_total{node!=""}[5m])) by (node)
```
- Visualization: **Time series** ou **Gauge**
- Title: "CPU Usage por Node"

#### Painel 2: Memória por Node
```promql
sum(container_memory_working_set_bytes{node!=""}) by (node) / 1024 / 1024 / 1024
```
- Visualization: **Time series** ou **Gauge**
- Title: "Memória (GB) por Node"

#### Painel 3: Pods por Node
```promql
count(kube_pod_info) by (node)
```
- Visualization: **Stat** ou **Bar gauge**
- Title: "Pods por Node"

#### Painel 4: Pods por Namespace
```promql
count(kube_pod_info) by (namespace)
```
- Visualization: **Pie chart** ou **Bar gauge**
- Title: "Pods por Namespace"

#### Painel 5: Pods com Problema
```promql
kube_pod_status_phase{phase=~"Failed|Pending|Unknown"} > 0
```
- Visualization: **Table**
- Title: "Pods com Problema"

### Passo 8.3: Salvar o dashboard

1. Clique no ícone de **disquete** (💾) no topo
2. Dê um nome: "Meu Cluster K3s"
3. Clique em **Save**

---

## 9. Resumo: Dashboards Mais Úteis

| Objetivo | Dashboard |
|----------|-----------|
| Visão geral do cluster | Kubernetes / Compute Resources / Cluster |
| CPU e Memória por Node | Kubernetes / Compute Resources / Node (Pods) |
| Recursos por Namespace | Kubernetes / Compute Resources / Namespace (Pods) |
| Pods por Workload | Kubernetes / Compute Resources / Workload |
| Status dos Nodes | Kubernetes / Kubelet |
| Uso de rede | Kubernetes / Networking / Cluster |

---

## 10. Dicas Extras

### Mudar o período de tempo

No canto superior direito, você pode ajustar o intervalo de tempo:
- **Last 5 minutes** - Últimos 5 minutos
- **Last 1 hour** - Última hora
- **Last 24 hours** - Últimas 24 horas

### Atualização automática

Ao lado do seletor de tempo, você pode configurar atualização automática:
- Clique no dropdown e selecione **"10s"** ou **"30s"**

### Favoritar dashboards

Clique na **estrela** (☆) no topo do dashboard para adicioná-lo aos favoritos.

---

## Pronto!

Agora você sabe como:
- ✅ Ver CPU e Memória de cada node
- ✅ Listar todos os namespaces
- ✅ Ver consumo por namespace
- ✅ Contar pods por node
- ✅ Identificar pods com falha

Se tiver dúvidas, explore os outros dashboards disponíveis - eles são pré-configurados e muito úteis!
