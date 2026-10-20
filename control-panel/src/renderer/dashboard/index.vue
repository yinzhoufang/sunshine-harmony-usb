<template>
  <div class="dashboard-container">
    <h1 class="dashboard-title">控制面板</h1>
    <div class="grid-container">
      <!-- 快捷入口卡片 -->
      <a 
        v-for="(item, index) in shortcutItems" 
        :key="index" 
        class="dashboard-card"
        :href="item.path"
      >
        <div class="card-icon">
          {{ item.icon }}
        </div>
        <h3 class="card-title">{{ item.title }}</h3>
        <p class="card-desc">{{ item.description }}</p>
      </a>
    </div>
  </div>
</template>

<script setup>
import { reactive } from 'vue';

// 快捷入口配置数据
const shortcutItems = reactive([
  {
    icon: '🔗',
    title: '配对',
    description: '开始配对',
    path: '/pin'
  },
  {
    icon: '🛡️',
    title: '',
    description: '安全与隐私设置',
    path: '/security.html'
  },
  {
    icon: '🌐',
    title: '网络设置',
    description: '网络连接配置',
    path: '/network.html'
  },
  {
    icon: '💾',
    title: '存储管理',
    description: '存储空间设置',
    path: '/storage.html'
  },
  {
    icon: '🖥️',
    title: '显示设置',
    description: '显示与分辨率设置',
    path: '/display.html'
  },
  {
    icon: '🔔',
    title: '通知中心',
    description: '通知管理设置',
    path: '/notifications.html'
  },
  {
    icon: '🔌',
    title: '客户端管理',
    description: '配对客户端设置',
    path: '/pin'
  },
  {
    icon: '🔋',
    title: '电源设置',
    description: '电源管理选项',
    path: '/power-settings'
  }
]);
</script>

<style lang="less" scoped>
@dashboard-padding: 2rem;
@card-min-width: 280px;
@grid-gap: 1.5rem;
@title-color: #2c3e50;
@card-bg: white;
@border-color: #eee;

.dashboard-container {
  padding: @dashboard-padding;
  max-width: 1200px;
  margin: 0 auto;

  .dashboard-title {
    text-align: center;
    margin-bottom: 2rem;
    color: @title-color;
  }

  .grid-container {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(@card-min-width, 1fr));
    gap: @grid-gap;
    padding: 1rem;

    .dashboard-card {
      background: @card-bg;
      border-radius: 12px;
      padding: 1.5rem;
      cursor: pointer;
      transition: transform 0.2s, box-shadow 0.2s;
      border: 1px solid @border-color;

      &:hover {
        transform: translateY(-5px);
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      }

      .card-icon {
        font-size: 2.5rem;
        margin-bottom: 1rem;
      }

      .card-title {
        color: #34495e;
        margin-bottom: 0.5rem;
      }

      .card-desc {
        color: #7f8c8d;
        font-size: 0.9rem;
      }
    }
  }
}
</style>
