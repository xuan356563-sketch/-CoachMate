export interface OpsSummary {
  users_total: number
  synced_users_total: number
  sync_conflicts_24h: number
  ai_requests_24h: number
  deletion_pending: number
}

export interface SyncHealth {
  mutations_24h: number
  conflicts_24h: number
  latest_cursor: number
  latest_mutation_at: string | null
}

export interface AiUsageGroup {
  provider: string
  model: string
  result_code: string
  requests: number
  input_tokens: number
  output_tokens: number
  average_latency_ms: number
}

export interface AiUsage {
  groups: AiUsageGroup[]
}

export interface DeletionJobs {
  pending: number
  cancelled: number
  next_due_at: string | null
}

export interface OpsDashboard {
  summary: OpsSummary
  syncHealth: SyncHealth
  aiUsage: AiUsage
  deletionJobs: DeletionJobs
}

async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(path, {
    headers: { Accept: 'application/json' },
    credentials: 'same-origin',
  })
  if (!response.ok) {
    throw new Error(`运营接口返回 ${response.status}`)
  }
  return (await response.json()) as T
}

export async function loadDashboard(): Promise<OpsDashboard> {
  const [summary, syncHealth, aiUsage, deletionJobs] = await Promise.all([
    getJson<OpsSummary>('/ops/v1/summary'),
    getJson<SyncHealth>('/ops/v1/sync-health'),
    getJson<AiUsage>('/ops/v1/ai-usage'),
    getJson<DeletionJobs>('/ops/v1/deletion-jobs'),
  ])
  return { summary, syncHealth, aiUsage, deletionJobs }
}
