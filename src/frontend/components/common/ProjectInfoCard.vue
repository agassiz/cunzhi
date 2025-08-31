<script setup lang="ts">
import { useMessage } from 'naive-ui'
import { computed, onMounted } from 'vue'
import { useVersionCheck } from '../../composables/useVersionCheck'

const message = useMessage()
const { versionInfo, manualCheckUpdate, safeOpenUrl, lastCheckTime, isChecking, getVersionInfo } = useVersionCheck()

// 格式化最后检查时间
const formattedLastCheckTime = computed(() => {
  return lastCheckTime.value ? lastCheckTime.value.toLocaleString('zh-CN') : ''
})

// 安全打开GitHub链接
async function openGitHub() {
  try {
    await safeOpenUrl('https://github.com/agassiz/cunzhi')
    message.success('正在打开GitHub页面...')
  }
  catch (error) {
    const errorMsg = error instanceof Error ? error.message : '打开GitHub失败，请手动访问'
    if (errorMsg.includes('已复制到剪贴板')) {
      message.warning(errorMsg)
    }
    else {
      message.error(errorMsg)
    }
  }
}

// 安全打开GitHub Star页面
async function openGitHubStars() {
  try {
    await safeOpenUrl('https://github.com/agassiz/cunzhi/stargazers')
    message.success('正在打开Star页面...')
  }
  catch (error) {
    const errorMsg = error instanceof Error ? error.message : '打开Star页面失败，请手动访问'
    if (errorMsg.includes('已复制到剪贴板')) {
      message.warning(errorMsg)
    }
    else {
      message.error(errorMsg)
    }
  }
}

// 检查版本更新
async function checkVersion() {
  try {
    const info = await manualCheckUpdate()
    if (info?.hasUpdate) {
      message.info(`发现新版本 v${info.latest}！`)
    }
    else {
      message.success('当前已是最新版本')
    }
  }
  catch (error) {
    console.error('检查版本失败:', error)
    message.error('检查版本失败，请稍后重试')
  }
}

// 组件挂载时初始化版本信息
onMounted(async () => {
  try {
    await getVersionInfo()
  }
  catch (error) {
    console.error('初始化版本信息失败:', error)
  }
})
</script>

<template>
  <n-card
    size="small"
    class="transition-all duration-200 hover:shadow-md"
  >
    <!-- 主要内容区域 -->
    <div class="flex items-center justify-between mb-2">
      <!-- 左侧：项目信息 -->
      <div class="flex items-center gap-3">
        <div class="w-8 h-8 rounded-lg bg-blue-100 dark:bg-blue-900 flex items-center justify-center">
          <div class="i-carbon-logo-github text-blue-600 dark:text-blue-400" />
        </div>
        <div>
          <h3 class="font-semibold text-gray-900 dark:text-white text-sm">
            寸止 {{ versionInfo ? `v${versionInfo.current}` : 'v0.2.0' }}
          </h3>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            智能代码审查工具，支持MCP协议集成
          </p>
        </div>
      </div>

      <!-- 右侧：版本检查区域 -->
      <div class="flex flex-col items-end gap-1">
        <n-button
          size="medium"
          secondary
          :loading="isChecking"
          @click="checkVersion"
        >
          <template #icon>
            <div class="i-carbon-renew text-green-600 dark:text-green-400" />
          </template>
          检查更新
        </n-button>

        <!-- 最后检查时间 -->
        <div
          v-if="formattedLastCheckTime"
          class="text-xs text-gray-400 dark:text-gray-500"
        >
          最后检查: {{ formattedLastCheckTime }}
        </div>
      </div>
    </div>

    <!-- 底部：GitHub区域 -->
    <div class="flex items-center justify-between border-t border-gray-100 dark:border-gray-700 pt-2">
      <div class="flex items-center gap-1">
        <n-button
          size="medium"
          type="primary"
          @click="openGitHub"
        >
          <template #icon>
            <div class="i-carbon-logo-github" />
          </template>
          GitHub
        </n-button>

        <n-button
          size="medium"
          secondary
          @click="openGitHubStars"
        >
          <template #icon>
            <div class="i-carbon-star text-yellow-500" />
          </template>
          Star
        </n-button>
      </div>

      <!-- 弱化的提示文字 -->
      <p class="text-xs text-gray-400 dark:text-gray-500">
        如果对您有帮助，请给我们一个 Star ⭐
      </p>
    </div>
  </n-card>
</template>
