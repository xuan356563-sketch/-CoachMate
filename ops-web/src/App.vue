<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import { loadDashboard, type OpsDashboard } from './api'

const dashboard = ref<OpsDashboard | null>(null)
const loading = ref(false)
const errorMessage = ref('')
const refreshedAt = ref<Date | null>(null)

const serviceStatus = computed(() => {
  if (loading.value && dashboard.value === null) return '检查中'
  if (errorMessage.value) return '异常'
  return dashboard.value === null ? '未知' : '正常'
})

function formatTime(value: string | null): string {
  if (value === null) return '暂无'
  return new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

async function refresh(): Promise<void> {
  loading.value = true
  errorMessage.value = ''
  try {
    dashboard.value = await loadDashboard()
    refreshedAt.value = new Date()
  } catch (error) {
    errorMessage.value =
      error instanceof Error ? error.message : '运营数据读取失败'
  } finally {
    loading.value = false
  }
}

onMounted(refresh)
</script>

<template>
  <main class="shell">
    <header class="hero">
      <div>
        <p class="eyebrow">TRAINMATE / PRIVATE OPS</p>
        <h1>内测运营概览</h1>
        <p class="subtitle">只展示聚合健康、同步、AI 用量和删除任务状态。</p>
      </div>
      <button :disabled="loading" type="button" @click="refresh">
        {{ loading ? '刷新中…' : '刷新数据' }}
      </button>
    </header>

    <div v-if="errorMessage" class="notice error" role="alert">
      {{ errorMessage }}。请检查私网隧道和 Ops API。
    </div>
    <div v-else class="notice">
      服务状态：<strong>{{ serviceStatus }}</strong>
      <span v-if="refreshedAt"> · 更新于 {{ refreshedAt.toLocaleTimeString('zh-CN') }}</span>
    </div>

    <section v-if="dashboard" class="metrics" aria-label="聚合指标">
      <article>
        <span>用户总数</span>
        <strong>{{ dashboard.summary.users_total }}</strong>
        <small>已同步 {{ dashboard.summary.synced_users_total }}</small>
      </article>
      <article>
        <span>24 小时同步冲突</span>
        <strong>{{ dashboard.summary.sync_conflicts_24h }}</strong>
        <small>变更 {{ dashboard.syncHealth.mutations_24h }}</small>
      </article>
      <article>
        <span>24 小时 AI 请求</span>
        <strong>{{ dashboard.summary.ai_requests_24h }}</strong>
        <small>不含提示词和用户标识</small>
      </article>
      <article>
        <span>待删除任务</span>
        <strong>{{ dashboard.deletionJobs.pending }}</strong>
        <small>已撤销 {{ dashboard.deletionJobs.cancelled }}</small>
      </article>
    </section>

    <section v-if="dashboard" class="grid">
      <article class="panel">
        <h2>同步健康</h2>
        <dl>
          <div><dt>最新游标</dt><dd>{{ dashboard.syncHealth.latest_cursor }}</dd></div>
          <div><dt>24 小时冲突</dt><dd>{{ dashboard.syncHealth.conflicts_24h }}</dd></div>
          <div><dt>最后变更</dt><dd>{{ formatTime(dashboard.syncHealth.latest_mutation_at) }}</dd></div>
        </dl>
      </article>

      <article class="panel">
        <h2>删除生命周期</h2>
        <dl>
          <div><dt>等待清理</dt><dd>{{ dashboard.deletionJobs.pending }}</dd></div>
          <div><dt>已撤销</dt><dd>{{ dashboard.deletionJobs.cancelled }}</dd></div>
          <div><dt>下次到期</dt><dd>{{ formatTime(dashboard.deletionJobs.next_due_at) }}</dd></div>
        </dl>
      </article>

      <article class="panel wide">
        <h2>24 小时 AI 用量</h2>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>供应商</th>
                <th>模型</th>
                <th>结果码</th>
                <th>请求</th>
                <th>输入 Token</th>
                <th>输出 Token</th>
                <th>平均耗时</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="group in dashboard.aiUsage.groups" :key="`${group.provider}:${group.model}:${group.result_code}`">
                <td>{{ group.provider }}</td>
                <td>{{ group.model }}</td>
                <td><code>{{ group.result_code }}</code></td>
                <td>{{ group.requests }}</td>
                <td>{{ group.input_tokens }}</td>
                <td>{{ group.output_tokens }}</td>
                <td>{{ group.average_latency_ms }} ms</td>
              </tr>
              <tr v-if="dashboard.aiUsage.groups.length === 0">
                <td colspan="7" class="empty">当前时间窗没有 AI 用量记录</td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </section>

    <p class="privacy">
      本页面不请求邮箱、训练明细、提示词、密钥或其他个人信息，仅允许通过私网或 SSH 隧道访问。
    </p>
  </main>
</template>
