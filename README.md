# Radar: Kubernetes UI, которого не хватало — разворачиваем в Yandex Managed K8s за 10 минут

## Введение

У каждого, кто работает с Kubernetes, рано или поздно возникает потребность «посмотреть на кластер глазами»: кто с кем связан, почему под в CrashLoopBackOff, что изменилось за ночь, какие сертификаты истекают. Вариантов обычно два — Kubernetes Dashboard (слишком бедный) или Lens / Headlamp (десктопное приложение или тяжёлый стек с зависимостями). А kubectl-специалисты откапывают причины инцидентов в простынях YAML, где сигнал тонет в `managedFields` и `status.conditions`.

[Radar](https://github.com/skyhook-io/radar) — open-source UI для Kubernetes от Skyhook (YC W23). Один бинарник на Go, без регистрации и аккаунта, бесплатный навсегда. Топология кластера, браузер ресурсов, timeline событий, менеджер Helm-релизов, GitOps для Argo CD и Flux, карта трафика, аудит безопасности, анализ impact'а перед апгрейдом K8s и даже встроенный MCP-сервер, чтобы ИИ-агенты могли смотреть кластер глазами Radar вместо сырого kubectl.

В этой статье мы запустим Radar локально за 30 секунд, затем развернём его в Yandex Managed Kubernetes через Helm — с ingress-nginx и доменом из публичного IP — и разберём все основные экраны. Разворачиваемый инстанс — общий для команды разработчиков, поэтому конфигурация строго read-only: все write-права выключены, ИИ-агенты подключаются к read-only MCP.

## Radar vs Kubernetes Dashboard vs Lens vs Headlamp vs k9s

| Метрика | Radar | Kubernetes Dashboard | Lens | Headlamp | k9s |
|---------|-------|----------------------|------|----------|-----|
| Тип | Локальный бинарник + опция in-cluster | In-cluster web UI | Десктопное приложение (Electron) | Web UI / десктоп | TUI в терминале |
| RAM | < 128 MiB | ~100–200 MiB | 500+ MiB (Electron) | ~100–200 MiB | ~50 MiB |
| Аккаунт | Не нужен | Не нужен | Нужен Lens-аккаунт (IDE-функции) | Не нужен | Не нужен |
| Топология | ✅ (Resources + Traffic) | ❌ | Платно (Lens Charts/Paid) | ❌ | ❌ |
| Timeline | ✅ (memory/sqlite) | ❌ | ❌ | ❌ | ❌ |
| Helm diff | ✅ | ❌ | Частично | ❌ | ❌ |
| GitOps | ✅ (Argo CD + Flux) | ❌ | Частично (расширения) | Частично (плагины) | ❌ |
| Карта трафика | ✅ (Hubble/Istio/Beyla/Caretta) | ❌ | ❌ | ❌ | ❌ |
| Аудит | ✅ (31 проверка) | ❌ | ❌ | ❌ | ❌ |
| Upgrade impact | ✅ | ❌ | ❌ | ❌ | ❌ |
| Cost insights | ✅ (OpenCost) | ❌ | Платно | ❌ | ❌ |
| MCP-сервер | ✅ | ❌ | ❌ | ❌ | ❌ |
| Файлы образа | ✅ | ❌ | ❌ | ❌ | ❌ |
| RBAC-visibility | ✅ | ❌ | ❌ | ❌ | ❌ |
| Сетевая диагностика | ✅ | ❌ | ❌ | ❌ | ❌ |
| Автодетект CRD | ✅ | Частично | Частично | ✅ | Частично |
| Лицензия | Apache 2.0 | Apache 2.0 | Проприетарная (OSS-режим обрезан) | MIT | Apache 2.0 |

Radar не заменит Grafana с дашбордами метрик и не тянет на полноценный лог-агрегатор. Но для ежедневного «что происходит в кластере и почему» — это, пожалуй, самый быстрый и функциональный инструмент с нулевым порогом входа.

Отличительные особенности Radar:

- **Topology** — интерактивный граф связей ресурсов в реальном времени
- **Upgrade Impact** — проверка кластера перед апгрейдом K8s (18 проверок до версии 1.36)
- **MCP-сервер** — ИИ-агенты получают кластер в token-оптимизированном виде вместо сырого kubectl
- **Timeline** — единая лента событий и diff'ов изменений по ресурсам

> Предполагается, что у вас уже есть работающий кластер Yandex Managed Kubernetes с установленным ingress-nginx. Как его поставить — описано в любом базовом гайде по Yandex K8s; статья начинается с работающего кластера.

## Часть 1. Локальный запуск за 30 секунд

Самый частый сценарий Radar — запуск с ноутбука: бинарник читает `~/.kube/config` и ходит в Kubernetes API напрямую. Ничего в кластер не ставится.

```bash
curl -fsSL https://get.radarhq.io | sh && kubectl radar
```

Откроется браузер с UI. Radar работает с тем же kubeconfig, что и kubectl: текущий контекст, все кластеры, multi-context переключение на лету.

Другие способы установки:

```bash
# Homebrew (macOS/Linux)
brew install skyhook-io/tap/radar

# Krew (kubectl-плагин)
kubectl krew install radar

# Scoop (Windows)
scoop bucket add skyhook https://github.com/skyhook-io/scoop-bucket
scoop install radar

# PowerShell (Windows)
irm https://get.radarhq.io/install.ps1 | iex
```

Есть и нативное десктоп-приложение для macOS/Linux/Windows — без терминала:

```bash
brew install --cask skyhook-io/tap/radar-desktop
```

### Полезные флаги локального запуска

| Флаг | По умолчанию | Описание |
|------|--------------|----------|
| `--namespace` | (все) | Начальный фильтр namespace'ов |
| `--port` | `9280` | Порт сервера |
| `--listen-address` | `127.0.0.1` | Только локальный доступ (по умолчанию) |
| `--timeline-storage` | `memory` | Хранилище timeline: `memory` или `sqlite` |
| `--disable-exec` | `false` | Выключить терминал и debug shell |
| `--disable-helm-write` | `false` | Выключить Helm-операции записи |
| `--no-mcp` | `false` | Выключить MCP-сервер для ИИ-агентов |

Локальный режим — приватный по дизайну: данные кластера остаются на вашей машине, никуда не выгружаются, аккаунт не нужен.

## VictoriaMetrics до Radar: зачем и как

Функции Traffic-карты, Cost Insights и MCP-инструмент `query_prometheus` требуют PromQL-совместимый бэкенд (Prometheus, VictoriaMetrics, Thanos, Mimir). Cтавим минимальный стек `victoria-metrics-k8s-stack` (vmagent + vmsingle + Grafana) и указываем этот стек в `traffic.prometheusUrl`.

### Шаг 2. Устанавливаем

```bash
helm upgrade --install vmks oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack \
  --namespace vmks --create-namespace \
  --version 0.90.2 \
  --wait --values vmks-values.yaml
```

### Шаг 3. Проверяем

```bash
# Поды стека
kubectl get pods -n vmks

# Пароль Grafana
kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode; echo

Проверить, что Radar увидел бэкенд, можно в UI на экране Traffic — источник данных подхватится из `traffic.prometheusUrl`, а MCP-инструмент `query_prometheus` начнёт отвечать на PromQL-запросы.


## Часть 2. In-cluster деплой в Yandex Managed K8s

Локальный режим удобен одному человеку. Для командной работы Radar разворачивается в кластер: один под, ClusterIP-сервис, ingress — и весь отдел видит кластер в браузере.

Архитектура до неприличия простая:

```
Браузер ──HTTPS──► ingress-nginx ──► Service (ClusterIP :9280) ──► Pod radar
                                                                          │
                                                                    K8s API (in-cluster SA)
```

Никакой базы данных, никаких зависимостей. По умолчанию — один реплика-под (128 MiB request, 512 MiB limit).

### Шаг 1. Добавляем Helm-репозиторий

```bash
helm repo add skyhook https://skyhook-io.github.io/helm-charts
helm repo update
```

В этой статье используется чарт версии **1.11.0** (совпадает с версией приложения). Посмотреть все доступные версии:

```bash
helm search repo skyhook/radar --versions
```

### Шаг 2. Аутентификация

Radar может иметь аутентификацию. Варианты:

- **Basic auth** на уровне ingress-nginx (`nginx.ingress.io/auth-type: basic` + Secret с htpasswd) — самый быстрый способ закрыть UI
- **OIDC** (`auth.mode: oidc`) — вход через корпоративный IdP (Google, Okta, Dex, Keycloak), у каждого пользователя свой RBAC через Kubernetes impersonation

### Шаг 3. values-файл

Файл `helm-values.yaml`:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: ваш-fqdn-url
      paths:
        - path: /
          pathType: Prefix

rbac:
  podLogs: true    # просмотр логов подов (включён по умолчанию)
  podExec: false   # терминал в подах — включайте осознанно
  secrets: false   # чтение Secrets — выключено по умолчанию
  helm: false      # Helm write-операции — выключено по умолчанию

timeline:
  storage: memory

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Из нестандартного здесь:

- `rbac.*` — все опасные права выключены по умолчанию: Radar стартует в read-only режиме (кроме логов — они нужны всегда)
- Инстанс рассчитан на всех разработчиков: доступ к общему Radar — read-only

### Шаг 4. Устанавливаем

```bash
helm upgrade --install radar skyhook/radar --version 1.11.0 \
  -n radar --create-namespace -f helm-values.yaml \
  --wait --timeout 5m
```

## Обзор экранов Radar

### Topology

Интерактивный граф связей ресурсов в реальном времени — визитная карточка Radar.

- Два режима: **Resources** (полная иерархия: Deployment → ReplicaSet → Pod, плюс ConfigMap'ы, Secrets, HPA, PDB) и **Traffic** (сетевой путь: Ingress/Gateway → HTTPRoute → Service → Pod)
- Группировка по namespace, app-лейблу или без неё
- Фильтр по типу ресурса, клик по ноду — полный details
- Авто-раскладка ELK.js, live-обновления через SSE

Именно здесь быстрее всего понимаешь «кто кого использует» в незнакомом namespace.

### Resources

Табличный браузер всех ресурсов кластера, включая CRD (Radar авто-детектит любые Custom Resources).

- Умные колонки для каждого типа ресурса
- Поиск по имени, фильтр по статусу и проблемам (CrashLoopBackOff, ImagePullBackOff, …)
- Кастомные колонки из любых лейблов и аннотаций
- Клик по ресурсу: YAML, related resources, логи, события

### Image Filesystem Viewer

Просмотр файловой системы container-образа прямо из Pod — без `docker pull` и `kubectl exec`.

- Дерево файлов с размерами, правами и symlink'ами
- Поиск файлов по всему образу
- Скачивание отдельных файлов
- Работает с приватными реестрами (GCR, ECR, ACR) через ImagePullSecrets кластера
- Дисковый кэш слоёв для повторного доступа

### Timeline

Единая лента событий Kubernetes и изменений ресурсов.

- Фильтр по типу (все / только warnings)
- Diff'ы изменений: что именно поменялось (replicas, images, …)
- Реальное время: новые события прилетают по SSE

### Helm

Полноценный менеджер Helm-релизов кластера.

- Все релизы по namespace'ам: статус, версия чарта, health ресурсов
- Инспекция values, rendered-манифестов, diff ревизий
- История релиза, отслеживание failed upgrades и rollback-паттернов
- Диагностика зависших hooks с подами, событиями и логами

В read-only сетапе этой статьи Radar не может видеть сами Helm-релизы: чарт хранит их в Secrets, а `rbac.secrets: false` — релизы недоступны без opt-in. Upgrade, rollback и uninstall из UI требуют `rbac.helm: true` и в эту конфигурацию не входят.

### Compare

Diff любых двух ресурсов одного вида side-by-side: staging vs production Deployment, два «одинаковых» пода.

- Side-by-side или unified, swap A ↔ B в один клик
- Diff-only — сворачивает неизменённое
- Spec-only — отбрасывает `status`
- Шум (`managedFields`, `resourceVersion`) вычищается автоматически

### TLS Certificates

Сроки действия TLS-сертификатов по всем namespace'ам — поймать истекающий сертификат до того, как он уронит прод.

### GitOps

Отдельный workspace для Argo CD и Flux.

- Fleet-вид + детальная страница по каждому приложению (Topology / Changes / Activity)
- Field-level drift, события, детект застрявших drift-лупов, parsed operation-failures
- Lifecycle-осознанность: `Terminating`-чипы, zombie-операции
- При подключении к Argo CD API — Git-rendered desired-vs-live diff (`argocd.existingSecret` в values)

Управляющие действия (sync, suspend, resume, reconcile, rollback) в read-only сетапе статьи недоступны: ClusterRole выдаёт на Argo/Flux-группы только `get/list/watch`, а контроллер с автоматической синхронизацией делает изменения за вас.

### Traffic

Живая карта сетевого трафика между сервисами.

- Автодетект источников данных: Hubble (Cilium), Istio, Caretta, Grafana Beyla
- Анимированный граф requests-per-second между сервисами
- Фильтры по namespace, протоколу, status code
- Beyla даёт eBPF L4 + HTTP видимость без service mesh
- Setup wizard: если источник не найден — предложит установить

### Capacity (Karpenter)

Read-only диагностика Karpenter-флитов: почему под pending, какой NodePool его примет, что делает disruption. Появляется автоматически при детекте NodePool'ов (RBAC-gated). Каждое значение несёт маркер достоверности (`= ≥ ≤ ?`) — недоступное никогда не отображается как ноль.

### Cost Insights

Интеграция с OpenCost: почасовая и месячная стоимость кластера, top namespaces по расходам, тренды (6h/24h/7d), разрезы по workload'ам и нодам. Появляется автоматически при детекте OpenCost-метрик в Prometheus.

### Cluster Audit

Проактивный сканер best practices — 31 проверка по безопасности, надёжности и эффективности (вдохновлён Polaris, Kubescape, Trivy и NSA/CISA guidelines).

- Security: privileged-контейнеры, privilege escalation, опасные capabilities, host namespaces, маунты container runtime socket, секреты в ConfigMaps
- Reliability: отсутствующие probes, `latest`-теги, single-replica deployments, отсутствующие PDB
- Efficiency: отсутствующие requests/limits
- Каждый finding — с описанием и remediation-гайдом
- Фильтры по категории, severity, framework (NSA/CISA, CIS)

### Network Path Diagnose

Hop-by-hop диагностика для Service, Ingress, HTTPRoute, GRPCRoute и Gateway: «если трафик пойдёт в этот ресурс — долетит ли до healthy-процесса, и если нет, какой hop ломается первым?»

- Первый критический hop называется явно
- Опциональный one-shot reachability test: DNS / TCP / TLS / HTTP пробы (прямой TCP из in-cluster Radar, через API-server proxy — с ноутбука)
- NetworkPolicies статически оцениваются на «would block»
- Каждому finding'у прилагается kubectl-репродьюсер

### Kubernetes Upgrade Impact

Открываете **Checks → Upgrade impact** перед апгрейдом control plane. Radar сравнивает кластер с целевой минорной версией K8s (каталог — 18 проверок до 1.36) и сортирует результат по требуемым действиям.

- Блокеры: скипнутые минорки, удалённые API, неподдерживаемый kubelet-skew, пересекающиеся PDB
- Влияние на эксплуатацию: FlexVolume, переименованные control-plane метрики
- Различает Passed / Review / Warning / Blocked / Incomplete / Not applicable

Для Yandex Managed K8s — прямая находка: перед апгрейдом мастер'а видно, что поедет.

### Access Control (RBAC visibility)

Что реально может ServiceAccount — без трёх `kubectl describe`.

- SA detail: прямые bindings, effective permissions, наследование через implicit groups, «какие поды это используют»
- Pod detail: Permissions-секция + blast-radius alert, если у SA wildcards, cluster-admin или escalation-глаголы
- «My Permissions»: live `SelfSubjectRulesReview` для текущего юзера

### AI Integration (MCP)

Встроенный Model Context Protocol-сервер — пожалуй, самая необычная фича Radar. ИИ-агенты (Claude, Cursor, Copilot, …) смотрят кластер не через сырой kubectl, а через token-оптимизированные данные Radar: топология, health-оценки, дедуплицированные события, отфильтрованные логи.

Для общего Radar на команду разработчиков подключать агентов нужно к read-only mount'у `/mcp-readonly`: он отдаёт только read-инструменты — write-инструменты (restart, scale, sync, …) даже не попадают в каталог, агент их не видит и не может вызвать. Полный mount `/mcp` на общий инстанс не подключайте: он экспортирует write-инструменты (RBAC вернёт 403, но агент будет их предлагать).

- Read-инструменты строго read-only (`readOnlyHint`)
- Secret-данные структурно никогда не отдаются; env-значения и логи скрабятся

Подключение к Claude Code:

```bash
claude mcp add radar --transport http http://radar.51-250-10-20.sslip.io/mcp-readonly
```

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "radar": {
      "type": "http",
      "url": "http://radar.51-250-10-20.sslip.io/mcp-readonly"
    }
  }
}
```

Cursor (`~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "radar": {
      "url": "http://radar.51-250-10-20.sslip.io/mcp-readonly"
    }
  }
}
```

Read-only каталог: `issues` («что сломано прямо сейчас?»), `diagnose` (root-cause одного workload'а в один вызов — с логами, событиями и startup-блокерами), `get_topology`, `get_neighborhood`, `list_helm_releases`, `get_cluster_audit`, `query_prometheus` и другие — всего ~25 read-инструментов.

## RBAC: что по умолчанию, а что opt-in

Чарт создаёт ClusterRole с read-only доступом к стандартным ресурсам (Pods, Deployments, Services, Events, Nodes, …) и ~45 группам CRD (Argo, Flux, cert-manager, Istio, Karpenter, KEDA, Velero, Crossplane, Kyverno, CloudNativePG, …). Опасные права выключены:

| Фича | Значение | По умолчанию |
|------|----------|--------------|
| Просмотр логов | `rbac.podLogs: true` | ✅ включён |
| Терминал в подах | `rbac.podExec: true` | ❌ выключен |
| Port forwarding | `rbac.portForward: true` | ❌ выключен |
| Чтение Secrets | `rbac.secrets: true` | ❌ выключен |
| Helm write (upgrade/rollback/uninstall) | `rbac.helm: true` | ❌ выключен |
| RBAC-объекты в браузере | `rbac.viewRBAC: true` | ❌ выключен |

Radar умеет graceful degradation: namespace-scoped ServiceAccount полностью поддерживается — что можете листать, то и видите; недоступные типы показывают copyable-сниппет ClusterRole для кластер-админа вместо вранья «0 found».

## Timeline: memory vs sqlite

In-cluster Radar по умолчанию хранит timeline в памяти — рестарт пода стирает историю. Для мультидневного audit-trail включайте SQLite на PVC:

```yaml
timeline:
  storage: sqlite
  retention: 168h   # 7 дней; "0" — без очистки
  maxSize: 800Mi    # лимит DB + WAL

persistence:
  enabled: true
  size: 1Gi
```

Ограничение: `replicaCount` обязан быть 1 (чарт упадёт с ошибкой, если совместить PVC + SQLite с несколькими репликами). Контроль очистки — через `/api/diagnostics`: `timeline.storageBytes`, `timeline.lastCleanupDeletedRows`, `timeline.lastCleanupError`.

## Подключение Prometheus (Traffic и Cost)

Для Traffic-карты и Cost Insights нужен Prometheus или VictoriaMetrics. Если автодетект не находит инстанс, укажите URL явно — в этой статье бэкенд ставится разделом выше (vmsingle в namespace `vmks`):

```yaml
traffic:
  prometheusUrl: http://vmsingle-vmks-victoria-metrics-k8s-stack.vmks.svc:8429
  # Для защищённых паролем бэкендов — заголовки из Secret:
  # prometheusHeadersFromEnv:
  #   Authorization: PROMETHEUS_TOKEN
```

`query_prometheus` из MCP и `/prometheus/query` из REST работают с любым PromQL-совместимым бэкендом: Thanos, VictoriaMetrics, Mimir.


## Безопасность

- Radar читает кластер через ваш kubeconfig / ServiceAccount и держит данные локально — ничего не выгружается в Skyhook
- Account, agent, cloud-backend не нужны
- In-cluster обязательно ставьте за аутентификацией: basic auth на ingress, встроенные proxy/OIDC-режимы
- Terminal и port forwarding — значительный доступ, включайте только в доверенной среде
- Privileged-фичи по умолчанию выключены, всё включается явным `rbac.*` флагом

## Заключение

Radar — это то, чем должен был быть Kubernetes Dashboard: быстрый локальный бинарник, топология-граф, timeline изменений, Helm и GitOps-менеджмент, аудит, upgrade-impact и MCP для ИИ-агентов — и всё это в одном поде на 128 MiB.

Ключевые преимущества:

- **Простота** — один бинарник или один Helm-чарт, ноль зависимостей
- **Скорость** — тестируется на кластерах с десятками тысяч подов, live-обновления через SSE
- **Приватность** — данные кластера остаются у вас
- **RBAC-first** — read-only по умолчанию, всё опасное — opt-in
- **ИИ-ready** — встроенный MCP-сервер из коробки

Полезные ссылки:

- GitHub: [github.com/skyhook-io/radar](https://github.com/skyhook-io/radar)
- Документация: [radarhq.io/docs](https://radarhq.io/docs)
- Helm-чарт: [artifacthub.io/packages/helm/skyhook/radar](https://artifacthub.io/packages/helm/skyhook/radar)
- Discord-сообщество: [radarhq.io/community/chat](https://radarhq.io/community/chat)
