import { shallowMount } from '@vue/test-utils';
import Frame from './Frame.vue';
import nutriplusAPI from 'dashboard/api/nutriplus';

vi.mock('dashboard/api/nutriplus', () => ({
  default: { bootstrap: vi.fn() },
}));

const ALLOWED_URL = 'https://app.crnutriplus.com/operations/crm-panel/embed';
const ALLOWED_ORIGIN = 'https://app.crnutriplus.com';

const mountFrame = config =>
  shallowMount(Frame, {
    props: {
      config,
      currentChat: { id: 189, meta: { sender: { id: 55 } } },
      isVisible: true,
      position: 0,
    },
    global: {
      mocks: {
        $store: {
          getters: {
            getCurrentUser: {
              id: 7,
              name: 'Agent',
              email: 'agent@example.com',
            },
            'contacts/getContact': () => ({
              id: 55,
              name: 'Customer',
            }),
          },
        },
      },
      stubs: { LoadingState: true },
    },
  });

describe('DashboardApp Frame NutriPlus bootstrap', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.chatwootConfig = { nutriplusDashboardAppURL: ALLOWED_URL };
    nutriplusAPI.bootstrap.mockResolvedValue({
      token: 'jwt-token',
      expires_in: 300,
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('bootstraps the exact configured NutriPlus frame and posts the token only to its origin', async () => {
    const postMessage = vi.fn();
    vi.spyOn(document, 'getElementById').mockReturnValue({
      contentWindow: { postMessage },
    });
    const wrapper = mountFrame([{ url: ALLOWED_URL }]);

    await wrapper.vm.onIframeLoad(0);

    expect(nutriplusAPI.bootstrap).toHaveBeenCalledWith(189);
    expect(postMessage).toHaveBeenCalledWith(
      JSON.stringify({
        event: 'nutriplus-dashboard-bootstrap',
        data: { token: 'jwt-token' },
      }),
      ALLOWED_ORIGIN
    );
  });

  it('does not bootstrap an untrusted Dashboard App', async () => {
    const postMessage = vi.fn();
    vi.spyOn(document, 'getElementById').mockReturnValue({
      contentWindow: { postMessage },
    });
    const wrapper = mountFrame([{ url: 'https://evil.example/app' }]);

    await wrapper.vm.onIframeLoad(0);

    expect(nutriplusAPI.bootstrap).not.toHaveBeenCalled();
  });

  it('requires an exact URL match', async () => {
    const postMessage = vi.fn();
    vi.spyOn(document, 'getElementById').mockReturnValue({
      contentWindow: { postMessage },
    });
    const wrapper = mountFrame([{ url: `${ALLOWED_URL}/` }]);

    await wrapper.vm.onIframeLoad(0);

    expect(nutriplusAPI.bootstrap).not.toHaveBeenCalled();
  });

  it('does not issue a bootstrap token from fetch-info messages', async () => {
    const postMessage = vi.fn();
    vi.spyOn(document, 'getElementById').mockReturnValue({
      contentWindow: { postMessage },
    });
    const wrapper = mountFrame([{ url: ALLOWED_URL }]);

    wrapper.vm.triggerEvent({ data: 'chatwoot-dashboard-app:fetch-info' });
    await Promise.resolve();

    expect(nutriplusAPI.bootstrap).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.any(String), '*');
  });
});
