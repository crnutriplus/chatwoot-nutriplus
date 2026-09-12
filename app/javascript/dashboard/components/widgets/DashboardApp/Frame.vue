<script>
import nutriplusAPI from 'dashboard/api/nutriplus';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

export default {
  components: {
    LoadingState,
  },
  props: {
    config: {
      type: Array,
      default: () => [],
    },
    currentChat: {
      type: Object,
      default: () => ({}),
    },
    isVisible: {
      type: Boolean,
      default: false,
    },
    position: {
      type: Number,
      required: true,
    },
  },
  data() {
    return {
      hasOpenedAtleastOnce: false,
      iframeLoading: true,
    };
  },
  computed: {
    dashboardAppContext() {
      return {
        conversation: this.currentChat,
        contact: this.$store.getters['contacts/getContact'](this.contactId),
        currentAgent: this.currentAgent,
      };
    },
    contactId() {
      return this.currentChat?.meta?.sender?.id;
    },
    currentAgent() {
      const { id, name, email } = this.$store.getters.getCurrentUser;
      return { id, name, email };
    },
  },
  watch: {
    isVisible() {
      if (this.isVisible) {
        this.hasOpenedAtleastOnce = true;
      }
    },
  },
  mounted() {
    window.addEventListener('message', this.triggerEvent);
  },
  unmounted() {
    window.removeEventListener('message', this.triggerEvent);
  },
  methods: {
    triggerEvent(event) {
      if (!this.isVisible) return;
      if (event.data === 'chatwoot-dashboard-app:fetch-info') {
        this.sendDashboardAppContext(0);
      }
    },
    getFrameId(index) {
      return `dashboard-app--frame-${this.position}-${index}`;
    },
    sendDashboardAppContext(index) {
      const frameElement = document.getElementById(this.getFrameId(index));
      if (!frameElement?.contentWindow) return;
      const eventData = { event: 'appContext', data: this.dashboardAppContext };
      frameElement.contentWindow.postMessage(JSON.stringify(eventData), '*');
      this.iframeLoading = false;
    },
    isNutriplusFrame(index) {
      const allowedURL = window.chatwootConfig?.nutriplusDashboardAppURL;
      const frameURL = this.config[index]?.url;
      return Boolean(allowedURL && frameURL === allowedURL);
    },
    async bootstrapNutriplus(index) {
      if (!this.isNutriplusFrame(index)) return;

      const frameElement = document.getElementById(this.getFrameId(index));
      if (!frameElement?.contentWindow) return;

      let targetOrigin;
      try {
        targetOrigin = new URL(window.chatwootConfig.nutriplusDashboardAppURL)
          .origin;
      } catch {
        return;
      }

      const conversationId = this.currentChat?.id;
      if (conversationId == null) return;

      try {
        const { token } = await nutriplusAPI.bootstrap(conversationId);
        if (!token) return;
        const eventData = {
          event: 'nutriplus-dashboard-bootstrap',
          data: { token },
        };
        frameElement.contentWindow.postMessage(
          JSON.stringify(eventData),
          targetOrigin
        );
      } catch {
        // Keep the Dashboard App usable if the NutriPlus bootstrap fails.
      }
    },
    async onIframeLoad(index) {
      this.sendDashboardAppContext(index);
      await this.bootstrapNutriplus(index);
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="hasOpenedAtleastOnce" class="dashboard-app--container">
    <div
      v-for="(configItem, index) in config"
      :key="index"
      class="dashboard-app--list"
    >
      <LoadingState
        v-if="iframeLoading"
        :message="$t('DASHBOARD_APPS.LOADING_MESSAGE')"
        class="dashboard-app_loading-container"
      />
      <iframe
        v-if="configItem.type === 'frame' && configItem.url"
        :id="getFrameId(index)"
        :src="configItem.url"
        @load="() => onIframeLoad(index)"
      />
    </div>
  </div>
</template>

<style scoped>
.dashboard-app--container,
.dashboard-app--list,
.dashboard-app--list iframe {
  height: 100%;
  width: 100%;
}

.dashboard-app--list iframe {
  border: 0;
}
.dashboard-app_loading-container {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  width: 100%;
}
</style>
